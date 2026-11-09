# Shared DEV helpers for both independent environments. Requires Windows PowerShell 5.1+.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Assert-Exit([string] $Step) {
    if ($LASTEXITCODE -ne 0) { throw "$Step failed (exit $LASTEXITCODE)." }
}
function Step([string] $Message) { Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Require-Command([string] $Exe) {
    if (-not (Get-Command $Exe -ErrorAction SilentlyContinue)) { throw "Missing '$Exe' on PATH. Consult README.md." }
}
function Assert-File([string] $Name) {
    if (-not (Test-Path -LiteralPath $Name -PathType Leaf)) { throw "Required file missing: $Name" }
}
function Read-Env([string] $Path) {
    $result = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $result }
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $s = $line.Trim()
        if (-not $s -or $s.StartsWith('#')) { continue }
        $parts = $s -split '=', 2
        if ($parts.Length -ne 2) { throw "Malformed environment file: $Path" }
        $result[$parts[0].Trim()] = $parts[1].Trim()
    }
    return $result
}
function Write-Env([string] $Path, [hashtable] $Data) {
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $lines = @('# Generated private DEV credentials. Do not commit or share this file.')
    foreach ($key in ($Data.Keys | Sort-Object)) { $lines += "${key}=$($Data[$key])" }
    [IO.File]::WriteAllLines($Path, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
}
function Get-Connection([string]$Service, [string]$Password) {
    return ('Host=postgres;Port=5432;Database=fcg_{0};Username=fcg_{0}_app;Password={1}' -f $Service,$Password)
}
function Ensure-Docker {
    Require-Command docker
    & docker info '--format={{.ServerVersion}}' 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return }
    Write-Host 'Starting Docker Desktop...' -ForegroundColor Yellow
    try { & docker desktop start | Out-Null } catch { }
    for ($i=0; $i -lt 75; $i++) {
        Start-Sleep -Seconds 3
        & docker info '--format={{.ServerVersion}}' 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return }
    }
    throw 'Docker Desktop is not ready. Start it in Linux container mode and retry.'
}
# DEMONSTRATION ONLY. The same credential is deliberately used for academic DEV.
# Override runtime/compose.env and runtime/k8s.env manually for non-academic uses.
function New-EnvValues([string] $Type) {
    $demo='Fiap@123456'
    $r=@{
        POSTGRES_ADMIN_PASSWORD=$demo
        RABBITMQ_USER='fcg'
        RABBITMQ_PASSWORD=$demo
        IDENTITY_ADMIN_PASSWORD=$demo
        WEB_BFF_SECRET=$demo
        ORDERS_CLIENT_SECRET=$demo
    }
    foreach ($s in @('IDENTITY','PAYMENTS','LIBRARY','CATALOG','PROMOTIONS','ORDERS','NOTIFICATIONS')) {
        $r['PG_'+$s+'_PASSWORD'] = $demo
    }
    return $r
}
function Get-ComposeSecrets([string]$Root) {
    $path=Join-Path $Root 'runtime/compose.env'
    if (Test-Path $path) {
        $prior=Read-Env $path
        if (-not $prior.ContainsKey('PG_NOTIFICATIONS_PASSWORD')) {
            $prior['PG_NOTIFICATIONS_PASSWORD']='Fiap@123456'
            Write-Env $path $prior
            Write-Host 'Existing Compose credentials kept; added only PG_NOTIFICATIONS_PASSWORD.' -ForegroundColor Yellow
        }
        return $prior
    }
    $values=New-EnvValues 'Compose'
    # Never guess passwords for an existing installation. A previous database might
    # belong to an entirely different Compose revision and contain irreplaceable data.
    # Docker inspect reports an error when the container has not been created yet.
    # Enumerating containers works on the first boot and is safe in Windows PowerShell 5.1.
    $existingContainers = @(& docker container ls --all --format '{{.Names}}')
    Assert-Exit 'List existing Docker containers'
    if ($existingContainers -contains 'fcg-postgres') {
        throw 'Existing fcg-postgres detected, but runtime/compose.env is missing. Recover the original credentials or use a clean Docker volume. No container was modified.'
    }
    $legacyVolume=(& docker volume ls --format '{{.Name}}' | Select-String -Pattern '(^|_)fcg_postgres_data$' | Out-String).Trim()
    if ($legacyVolume) {
        throw 'Existing FCG PostgreSQL Docker volume detected without runtime/compose.env. Recover the original credentials first. Database was not modified.'
    }
    Write-Env $path $values
    return $values
}
function Get-K8sSecret([string]$name, [string]$key) {
    $json=(& kubectl -n fcg get secret $name -o json --ignore-not-found=true | Out-String).Trim()
    Assert-Exit "Read Secret $name"
    if (-not $json) { return '' }
    $o=$json | ConvertFrom-Json
    $prop=$o.data.PSObject.Properties[$key]
    if ($null -eq $prop -or [string]::IsNullOrWhiteSpace([string]$prop.Value)) {return ''}
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$prop.Value))
}
function Get-K8sSecrets([string]$Root) {
    $path=Join-Path $Root 'runtime/k8s.env'
    if (Test-Path $path) {
        $prior=Read-Env $path
        if (-not $prior.ContainsKey('PG_NOTIFICATIONS_PASSWORD')) {
            $prior['PG_NOTIFICATIONS_PASSWORD']='Fiap@123456'
            Write-Env $path $prior
            Write-Host 'Existing K8s credentials kept; added only PG_NOTIFICATIONS_PASSWORD.' -ForegroundColor Yellow
        }
        return $prior
    }
    $values=New-EnvValues 'K8s'
    $ex=Get-K8sSecret 'fcg-dev-secrets' 'postgres-admin-password'
    if ($ex) {
        $values.POSTGRES_ADMIN_PASSWORD=$ex
        $values.RABBITMQ_USER=Get-K8sSecret 'fcg-dev-secrets' 'rabbitmq-username'
        $values.RABBITMQ_PASSWORD=Get-K8sSecret 'fcg-dev-secrets' 'rabbitmq-password'
        $values.IDENTITY_ADMIN_PASSWORD=Get-K8sSecret 'fcg-dev-secrets' 'identity-admin-password'
        $values.WEB_BFF_SECRET=Get-K8sSecret 'fcg-dev-secrets' 'web-bff-secret'
        foreach($s in @('identity','payments','library','catalog','promotions','orders','notifications')) {
            $which=if($s -in @('identity','payments','library')){'fcg-dev-secrets'}else{'fcg-domain-dev-secrets'}
            $conn=Get-K8sSecret $which "$s-connection-string"
            if (-not $conn -and $s -eq 'notifications') {
                # Notifications is a new service. Older six-service clusters have no user or DB yet.
                # No existing account credentials are replaced by this fallback.
                $values.PG_NOTIFICATIONS_PASSWORD='Fiap@123456'
                continue
            }
            if (-not $conn) { throw "Existing K8s secret missing connection string for $s. Cannot guess DB password." }
            $match=[regex]::Match($conn,'(?i)(?:^|;)\s*Password=([^;]+)')
            if (-not $match.Success) {throw "Cannot recover password for $s from existing K8s connection string."}
            $values['PG_'+$s.ToUpperInvariant()+'_PASSWORD']=$match.Groups[1].Value
        }
        $ordersSecret=Get-K8sSecret 'fcg-domain-dev-secrets' 'orders-client-secret'
        if (-not $ordersSecret) {throw 'Missing orders-client-secret in existing Kubernetes configuration.'}
        $values.ORDERS_CLIENT_SECRET=$ordersSecret
        Write-Host 'Reusing existing K8s Secret values. No passwords rotated.' -ForegroundColor Yellow
    }
    Write-Env $path $values
    return $values
}
# One-click selection shared by the Compose and Kubernetes incremental paths.
# Keep API/Worker/Migrations names centralized so a targeted update cannot
# accidentally build or restart unrelated microservices.
function Get-ServicePlan([string]$Service) {
    $valid=@('identity','payments','library','catalog','promotions','orders','notifications')
    if ($Service -notin $valid) { throw "Unknown service '$Service'. Valid: $($valid -join ', ')." }
    $hasWorker=$Service -in @('payments','library','orders','notifications')
    $composeApi=if($Service -eq 'identity'){'identity'}else{"$Service-api"}
    $worker=if($hasWorker){"$Service-worker"}else{''}
    $ports=@{identity=5081;payments=5082;library=5083;catalog=5084;promotions=5085;orders=5086;notifications=5087}
    $apiManifest=if($Service -eq 'library'){'library-api.yaml'}else{'api.yaml'}
    $workerManifest=if($Service -eq 'library'){'library-worker.yaml'}else{'worker.yaml'}
    $migrationManifest=if($Service -eq 'library'){'library-migrations-job.yaml'}else{'migrations-job.yaml'}
    return [pscustomobject]@{
        Name=$Service
        ComposeApi=$composeApi
        Worker=$worker
        Migrations="$Service-migrations"
        K8sApi="$Service-api"
        ApiManifest=$apiManifest
        WorkerManifest=$workerManifest
        MigrationsManifest=$migrationManifest
        ComposePort=[int]$ports[$Service]
    }
}

function Get-BuildComposeArgs([string]$Root) {
    # K8s builds from Compose recipes but must NEVER initialize/rotate Compose secrets.
    $original=Join-Path $Root 'runtime/compose.env'
    if (Test-Path $original) { return Get-ComposeArgs $Root }
    $placeholder=Join-Path $Root 'runtime/k8s-build-only.env'
    if (-not (Test-Path $placeholder)) { Write-Env $placeholder (New-EnvValues 'BuildOnly') }
    return @('compose','--project-directory',$Root,'--env-file',$placeholder,'-f',(Join-Path $Root 'docker-compose.yml'))
}
function Get-ComposeArgs([string]$Root) {
    return @('compose','--project-directory',$Root,'--env-file',(Join-Path $Root 'runtime/compose.env'),'-f',(Join-Path $Root 'docker-compose.yml'))
}

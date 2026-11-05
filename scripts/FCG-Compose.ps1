[CmdletBinding()]
param(
    [switch]$Status,
    [switch]$NoBuild,
    [switch]$NoBrowser,
    [ValidateSet('identity','payments','library','catalog','promotions','orders','notifications')]
    [string]$Service,
    [switch]$SkipMigrations
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if($SkipMigrations -and -not $Service){throw '-SkipMigrations is supported only with -Service. Full install still runs all migrations.'}
# Keep Docker Compose's actual error output: migrations, ports, dependencies,
# and container-engine failures are not necessarily RabbitMQ problems.
function Show-ComposeStartFailure([string[]]$ComposeCliArgs, [string]$LogPath) {
    Step 'Docker Compose error details (recent messages)'
    if (Test-Path -LiteralPath $LogPath) {
        $recent = @(Get-Content -LiteralPath $LogPath -Tail 120 -ErrorAction SilentlyContinue)
        $errors = @($recent | Where-Object { $_ -match '(?i)(error|fail|unhealthy|exited|port is already allocated|address already in use|permission denied|dependency|cannot|no space left|bind:)' })
        $lines = if($errors.Count -gt 0) { @($errors | Select-Object -Last 35) } else { @($recent | Select-Object -Last 30) }
        foreach($line in $lines) { Write-Host "  $line" -ForegroundColor Yellow }
    }
    Step 'Docker Compose status (including Created and Exited)'
    & docker @ComposeCliArgs ps --all
    Step 'Docker Engine details for containers that failed to start'
    $ids = @(& docker @ComposeCliArgs ps --all -q)
    foreach($id in $ids) {
        if(-not $id) { continue }
        $details = (& docker inspect --format '{{json .State}}' $id | Out-String).Trim()
        if($LASTEXITCODE -ne 0 -or -not $details) { continue }
        try { $state = $details | ConvertFrom-Json } catch { continue }
        $status = [string]$state.Status
        $reason = [string]$state.Error
        $exitCode = [int]$state.ExitCode
        if($reason -or $status -in @('created','dead','restarting') -or ($status -eq 'exited' -and $exitCode -ne 0)) {
            $name = (& docker inspect --format '{{.Name}}' $id | Out-String).Trim().TrimStart('/')
            Write-Host ("  {0}: status={1}, exit={2}" -f $name,$status,$exitCode) -ForegroundColor Yellow
            if($reason) { Write-Host "    Engine error: $reason" -ForegroundColor Red }
            if($status -eq 'exited' -and $exitCode -ne 0) {
                Write-Host "    Recent logs for $name :" -ForegroundColor Yellow
                & docker logs --tail 35 $id
            }
        }
    }
    Write-Host "Full Compose output saved to: $LogPath" -ForegroundColor Cyan
}
function Invoke-ComposeUpLogged([string[]]$ComposeCliArgs, [string[]]$UpArgs, [string]$Root, [string]$Label) {
    $logDir = Join-Path $Root 'runtime/logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $safeLabel = $Label -replace '[^a-zA-Z0-9-]', '-'
    $logPath = Join-Path $logDir ("compose-{0}-{1}.log" -f $safeLabel,(Get-Date -Format 'yyyyMMdd-HHmmss'))
    $priorErrorActionPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 can turn redirected native stderr into an
        # ErrorRecord. Preserve every CLI line, then test the actual exit code.
        $ErrorActionPreference = 'Continue'
        & docker @ComposeCliArgs @UpArgs 2>&1 | ForEach-Object { [string]$_ } | Tee-Object -FilePath $logPath
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $priorErrorActionPreference
    }
    if($exitCode -ne 0) {
        Show-ComposeStartFailure $ComposeCliArgs $logPath
        throw "Docker Compose up failed (exit $exitCode). See the Compose/Docker errors above, NOT only RabbitMQ logs. Persistent volumes were kept. Log: $logPath"
    }
}
Push-Location $root
try {
    Ensure-Docker
    $composeArgs=@(
        'compose',
        '--project-directory',$root,
        '-f',(Join-Path $root 'docker-compose.yml'))
    if ($Status) {
        & docker @composeArgs ps
        Assert-Exit 'Compose status'
        exit 0
    }
    if($Service) {
        # Targeted path deliberately does not recreate PostgreSQL, RabbitMQ,
        # databases, credentials, or unrelated microservices.
        $plan=Get-ServicePlan $Service
        Step "Updating ONLY Compose service: $Service"
        foreach($infra in @('postgres','rabbitmq')) {
            $running=(& docker @composeArgs ps -q --status running $infra | Out-String).Trim()
            Assert-Exit "Check running $infra"
            if(-not $running){throw "Compose $infra is not running. Run FCG-COMPOSE.cmd without -Service for the initial installation."}
        }
        $existing=(& docker @composeArgs ps -q --all $plan.ComposeApi | Out-String).Trim()
        Assert-Exit "Check existing $($plan.ComposeApi)"
        if(-not $existing){throw "Service $Service is not deployed. Run FCG-COMPOSE.cmd without -Service first."}
        $targets=@($plan.ComposeApi)
        if($plan.Worker){$targets+=$plan.Worker}
        if(-not $NoBuild) {
            $buildTargets=@($targets)
            if(-not $SkipMigrations){$buildTargets+= $plan.Migrations}
            Step "Building only: $($buildTargets -join ', ')"
            & docker @composeArgs build @buildTargets
            Assert-Exit "Build images for $Service"
        } else {
            Write-Host 'NoBuild: reusing existing Compose images.' -ForegroundColor Yellow
        }
        if(-not $SkipMigrations) {
            Step "Running only $Service migrations"
            # A single foreground migration service; its exit code determines success.
            & docker @composeArgs up --no-deps --force-recreate --abort-on-container-exit --exit-code-from $plan.Migrations $plan.Migrations
            Assert-Exit "Migration $($plan.Migrations)"
        } else {
            Write-Host 'SkipMigrations: database migrations were not executed.' -ForegroundColor Yellow
        }
        Step "Recreating only: $($targets -join ', ')"
        $targetUpArgs = @('up','-d','--no-deps','--force-recreate') + @($targets)
        Invoke-ComposeUpLogged $composeArgs $targetUpArgs $root "service-$Service"
        $port=$plan.ComposePort
        $uri="http://127.0.0.1:${port}/health/ready"
        $ready=$false
        for($i=0;$i -lt 90;$i++) {
            try {
                $r=Invoke-WebRequest -UseBasicParsing -Uri $uri -TimeoutSec 3
                if([int]$r.StatusCode -eq 200){$ready=$true;break}
            }catch { }
            Start-Sleep -Seconds 2
        }
        if(-not $ready) {
            & docker @composeArgs ps --all @targets
            Step "Recent Compose logs for API $Service"
            & docker @composeArgs logs --no-color --tail=80 $plan.ComposeApi
            throw "API $Service on port $port did not become ready. See $($plan.ComposeApi) logs above."
        }
        & docker @composeArgs ps @targets
        Assert-Exit "Status $Service"
        Step "Compose update completed: $Service. Other services and volumes untouched."
        Write-Host "  Ready: $uri" -ForegroundColor Green
        if(-not $NoBrowser){Start-Process "http://127.0.0.1:${port}/swagger"}
        exit 0
    }
    # The Compose graph owns database provisioning. Each EF Core migration waits
    # for PostgreSQL and creates its logical database with the DEV postgres user.
    Step 'Building images and starting ALL Docker Compose services'
    $fullUpArgs = @('up','-d','--remove-orphans')
    if(-not $NoBuild) { $fullUpArgs += '--build' }
    Invoke-ComposeUpLogged $composeArgs $fullUpArgs $root 'full-up'
    Step 'Waiting for 7 API readiness endpoints'
    $apiServices = @('identity','payments-api','library-api','catalog-api','promotions-api','orders-api','notifications-api')
    $ports = @(5081,5082,5083,5084,5085,5086,5087)
    for($apiIndex=0; $apiIndex -lt $ports.Count; $apiIndex++) {
        $port = $ports[$apiIndex]
        $apiService = $apiServices[$apiIndex]
        $uri="http://127.0.0.1:${port}/health/ready"
        $ready=$false
        for($i=0;$i -lt 90;$i++) {
            try {
                $r=Invoke-WebRequest -UseBasicParsing -Uri $uri -TimeoutSec 3
                if([int]$r.StatusCode -eq 200) {$ready=$true;break}
            } catch { }
            Start-Sleep -Seconds 2
        }
        if(-not $ready) {
            & docker @composeArgs ps --all $apiService
            Step "Recent logs for $apiService"
            & docker @composeArgs logs --no-color --tail=80 $apiService
            throw "API $apiService on port $port did not become ready. Check its logs above."
        }
        Write-Host "  Ready: $uri" -ForegroundColor Green
    }
    $pluginText=(& docker exec fcg-rabbitmq rabbitmq-plugins list -e | Out-String)
    Assert-Exit 'RabbitMQ plugin check'
    if($pluginText -notmatch '(?m)^\[E\*\]\s+rabbitmq_delayed_message_exchange\b') {throw 'RabbitMQ delayed-message plugin is not running.'}
    Step 'Docker Compose status'
    & docker @composeArgs ps
    Assert-Exit 'Docker Compose status'
    $urls=@('http://127.0.0.1:5081/swagger','http://127.0.0.1:5082/swagger','http://127.0.0.1:5083/swagger','http://127.0.0.1:5084/swagger','http://127.0.0.1:5085/swagger','http://127.0.0.1:5086/swagger','http://127.0.0.1:5087/swagger','http://127.0.0.1:15672')
    Step 'Compose ready - URLs'
    $urls | ForEach-Object { Write-Host $_ -ForegroundColor Green }
    Write-Host 'PostgreSQL: 127.0.0.1:5433; DEV credentials in config/compose/infrastructure/postgres.env.'
    if (-not $NoBrowser) { Start-Process 'http://127.0.0.1:5086/swagger' }
} finally {Pop-Location}

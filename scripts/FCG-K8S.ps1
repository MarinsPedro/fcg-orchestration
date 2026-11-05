[CmdletBinding()]
param(
    [switch]$Status,
    [switch]$NoBuild,
    [switch]$NoBrowser,
    [switch]$StopAccess,
    [ValidateSet('identity','payments','library','catalog','promotions','orders','notifications')]
    [string]$Service,
    [switch]$SkipMigrations
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'Access.ps1')
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$parent=(Resolve-Path (Join-Path $root '..')).Path
$ns='fcg'
if($SkipMigrations -and -not $Service){throw '-SkipMigrations is supported only with -Service. Full install still runs all migrations.'}
Push-Location $root
try {
    if($StopAccess){Stop-Access $root;Write-Host 'Only local access tunnels stopped; Kubernetes Pods remain running.';exit 0}
    Ensure-Docker
    Require-Command kubectl
    
    $ctx=(& kubectl config view -o 'jsonpath={.current-context}' | Out-String).Trim()
    $reachable=$false
    if($ctx){& kubectl cluster-info --request-timeout=5s 2>$null | Out-Null;$reachable=($LASTEXITCODE -eq 0)}
    if(-not $reachable) {
        if($Service){throw 'No active Kubernetes cluster. -Service requires a running FCG installation; run FCG-K8S.cmd without -Service first.'}
        Require-Command kind
        Step 'No Kubernetes cluster active. Creating an isolated local Kind cluster named fcg'
        $clusters=@(& kind get clusters)
        if('fcg' -notin $clusters){ & kind create cluster --name fcg --wait 240s;Assert-Exit 'kind create cluster' }
        & kubectl config use-context kind-fcg | Out-Null
        Assert-Exit 'kubectl context'
        $ctx='kind-fcg'
    }
    if($ctx -notin @('docker-desktop','kind-fcg')){throw "Unsafe Kubernetes context '$ctx'. Use docker-desktop or kind-fcg only."}
    if($Status) {
        & kubectl get deployment,sts,pvc -n $ns
        Write-Host 'URLs are localhost:5181-5187, RabbitMQ:15673, PostgreSQL:55432.'
        exit 0
    }
    if($Service) {
        # Fast path only for an EXISTING deployment. Never create a new cluster,
        # replace shared Secrets, or touch other services in a targeted update.
        $plan=Get-ServicePlan $Service
        Step "Updating ONLY Kubernetes service: $Service"
        & kubectl get namespace $ns -o name | Out-Null
        Assert-Exit "Existing namespace $ns (run full OneClick first)"
        foreach($infra in @('postgres','rabbitmq')) {
            & kubectl rollout status "statefulset/$infra" -n $ns --timeout=120s
            Assert-Exit "Existing infrastructure $infra (run full OneClick first)"
        }
        $deployments=@($plan.K8sApi)
        if($plan.Worker){$deployments+= $plan.Worker}
        foreach($d in $deployments) {
            & kubectl get deployment $d -n $ns -o name | Out-Null
            Assert-Exit "Existing Deployment $d (run full OneClick first)"
        }
        $folder=Join-Path $parent "fcg-$Service-service/k8s"
        $apiFile=Join-Path $folder $plan.ApiManifest
        Assert-File $apiFile
        if($plan.Worker) {$workerFile=Join-Path $folder $plan.WorkerManifest; Assert-File $workerFile}
        if(-not $SkipMigrations) {$migrationFile=Join-Path $folder $plan.MigrationsManifest; Assert-File $migrationFile}

        # Only this service's API/Worker/Migrations ConfigMaps are applied.
        foreach($kind in @('api','worker','migrations')) {
            $file=Join-Path $root "config/k8s-$Service-$kind.env"
            if(-not (Test-Path $file)){continue}
            $name="fcg-$Service-$kind-config"
            & kubectl create configmap $name -n $ns "--from-env-file=$file" --dry-run=client -o yaml | & kubectl apply -f -
            Assert-Exit "Update ConfigMap $name"
        }

        if(-not $NoBuild) {
            $targets=@($plan.ComposeApi)
            if($plan.Worker){$targets+=$plan.Worker}
            if(-not $SkipMigrations){$targets+=$plan.Migrations}
            $composeArgs=Get-BuildComposeArgs $root
            Step "Building only: $($targets -join ', ')"
            & docker @composeArgs build @targets
            Assert-Exit "Build images for $Service"
            $images=@()
            foreach($target in $targets) {
                # Identity's Compose service is called 'identity', but its K8s API
                # image is called 'fcg-identity-api:local'.
                $imageName=if($target -eq 'identity'){'identity-api'}else{$target}
                $tag="fcg-${imageName}:local"
                & docker tag "fcg-orchestration-${target}:latest" $tag
                Assert-Exit "Tag $tag"
                $images+= $tag
            }
            if($ctx -eq 'kind-fcg') {
                Require-Command kind
                Step "Loading only $Service images into Kind cluster fcg"
                & kind load docker-image @images --name fcg
                Assert-Exit "Load $Service images into Kind"
            } else {
                Write-Host 'Using Docker Desktop Kubernetes image mirror.' -ForegroundColor Yellow
            }
        } else {
            Write-Host 'NoBuild: reusing images already present in the cluster.' -ForegroundColor Yellow
        }

        if(-not $SkipMigrations) {
            $job=$plan.Migrations
            Step "Running only $Service migrations"
            & kubectl delete job $job -n $ns --ignore-not-found=true --wait=true
            Assert-Exit "Delete previous Job $job"
            & kubectl apply -f $migrationFile
            Assert-Exit "Start migrations $job"
            & kubectl wait -n $ns --for=condition=complete "job/$job" --timeout=300s
            if($LASTEXITCODE -ne 0){
                & kubectl logs -n $ns "job/$job" --tail=100
                throw "Migration $job FAILED; API/Worker were not restarted."
            }
            if($Service -eq 'identity') {
                $v=Get-K8sSecrets $root
                Ensure-OrdersClient 'K8s' $v
            }
        } else {
            Write-Host 'SkipMigrations: database migrations were not executed.' -ForegroundColor Yellow
        }

        Step "Deploying and restarting only $($deployments -join ', ')"
        & kubectl apply -f $apiFile
        Assert-Exit "Apply $Service API"
        if($plan.Worker) {
            & kubectl apply -f $workerFile
            Assert-Exit "Apply $Service Worker"
        }
        # A constant :local tag requires a restart even when the YAML is unchanged.
        # ConfigMaps injected as env vars also require new Pods.
        foreach($d in $deployments) {
            & kubectl rollout restart "deployment/$d" -n $ns
            Assert-Exit "Restart $d"
        }
        foreach($d in $deployments) {
            & kubectl rollout status "deployment/$d" -n $ns --timeout=300s
            Assert-Exit "Rollout $d"
        }
        # port-forward is bound to the old Pod; refresh only this service's tunnel.
        Restart-ServiceAccess $root $Service -NoBrowser:$NoBrowser
        Step "K8s update completed: $Service. Other deployments and persistent volumes untouched."
        exit 0
    }
    Step "Kubernetes context: $ctx"
    & kubectl wait --for=condition=Ready node --all --timeout=240s
    Assert-Exit 'Wait for node'
    & kubectl apply -f (Join-Path $root 'k8s/00-namespace.yaml')
    Assert-Exit 'Create fcg namespace'
    # Remove only stale one-shot importer resources from older deployments.
    # This does NOT delete RabbitMQ queues, exchanges, bindings or PVCs.
    & kubectl delete -n $ns job/fcg-rabbitmq-topology-import configmap/fcg-rabbitmq-topology --ignore-not-found=true
    Assert-Exit 'Remove legacy RabbitMQ importer resources'
    $v=Get-K8sSecrets $root
    # apply secrets from local, untracked env files; no plaintext secrets in git-tracked YAML.
    $common=@{
        'postgres-admin-password'=$v.POSTGRES_ADMIN_PASSWORD
        'rabbitmq-username'=$v.RABBITMQ_USER
        'rabbitmq-password'=$v.RABBITMQ_PASSWORD
        'identity-admin-password'=$v.IDENTITY_ADMIN_PASSWORD
        'web-bff-secret'=$v.WEB_BFF_SECRET
    }
    foreach($s in @('identity','payments','library')){$common["$s-connection-string"]=Get-Connection $s $v['PG_'+$s.ToUpperInvariant()+'_PASSWORD']}
    $domain=@{'orders-client-secret'=$v.ORDERS_CLIENT_SECRET}
    foreach($s in @('catalog','promotions','orders','notifications')){$domain["$s-connection-string"]=Get-Connection $s $v['PG_'+$s.ToUpperInvariant()+'_PASSWORD']}
    foreach($entry in @(@('fcg-dev-secrets',$common),@('fcg-domain-dev-secrets',$domain))) {
        $name=[string]$entry[0]
        $file=Join-Path $root "runtime/$name.env"
        Write-Env $file ([hashtable]$entry[1])
        & kubectl create secret generic $name -n $ns "--from-env-file=$file" --dry-run=client -o yaml | & kubectl apply -f -
        Assert-Exit "Ensure Secret $name"
    }
    Step 'Creating per-service non-secret ConfigMaps'
    foreach($s in @('identity','payments','library','catalog','promotions','orders','notifications')) {
        foreach($kind in @('api','worker','migrations')) {
            $file=Join-Path $root "config/k8s-$s-$kind.env"
            if(-not (Test-Path $file)){continue}
            $name="fcg-$s-$kind-config"
            & kubectl create configmap $name -n $ns "--from-env-file=$file" --dry-run=client -o yaml | & kubectl apply -f -
            Assert-Exit "Ensure ConfigMap $name"
        }
    }
    $composeArgs=Get-BuildComposeArgs $root # Build recipes only; never alters Compose runtime credentials.
    if(-not $NoBuild) {
        Step 'Building all .NET images from local BuildingBlocks and custom RabbitMQ image'
        & docker @composeArgs build
        Assert-Exit 'Docker images build'
        $map=@{
            'identity-api'='identity';'identity-migrations'='identity-migrations';
            'payments-api'='payments-api';'payments-worker'='payments-worker';'payments-migrations'='payments-migrations';
            'library-api'='library-api';'library-worker'='library-worker';'library-migrations'='library-migrations';
            'catalog-api'='catalog-api';'catalog-migrations'='catalog-migrations';
            'promotions-api'='promotions-api';'promotions-migrations'='promotions-migrations';
            'orders-api'='orders-api';'orders-worker'='orders-worker';'orders-migrations'='orders-migrations';
            'notifications-api'='notifications-api';'notifications-worker'='notifications-worker';'notifications-migrations'='notifications-migrations'
        }
        foreach($name in ($map.Keys | Sort-Object)) {
            & docker tag "fcg-orchestration-$($map[$name]):latest" "fcg-${name}:local"
            Assert-Exit "Tag image $name"
        }
        # For a self-managed Kind cluster, explicitly load images into node containerd.
        if(Get-Command kind -ErrorAction SilentlyContinue) {
            $known=@(& kind get clusters 2>$null)
            $cluster=if($ctx -eq 'kind-fcg'){'fcg'}else{'docker-desktop'}
            if($cluster -in $known) {
                $images=@('fcg-rabbitmq:4.3.6-delayed')+ @($map.Keys | ForEach-Object {"fcg-${_}:local"})
                Step "Loading local images into Kind cluster $cluster"
                & kind load docker-image @images --name $cluster
                Assert-Exit 'kind load docker-image'
            } else {
                Write-Host 'Using Docker Desktop Kubernetes local image mirror; kind CLI did not enumerate the desktop cluster.' -ForegroundColor Yellow
            }
        } else {
            Write-Host 'Kind CLI not installed: using Docker Desktop local image mirror (or previously loaded images).' -ForegroundColor Yellow
        }
    }
    Step 'PostgreSQL and RabbitMQ StatefulSets (PVCs preserved)'
    & kubectl apply -f (Join-Path $root 'k8s/postgres/postgres.yaml'); Assert-Exit 'Apply PostgreSQL'
    & kubectl apply -f (Join-Path $root 'k8s/rabbitmq/rabbitmq.yaml'); Assert-Exit 'Apply RabbitMQ'
    foreach($name in @('postgres','rabbitmq')) {
        & kubectl rollout status "statefulset/$name" -n $ns --timeout=300s
        Assert-Exit "$name rollout (check local image availability if ImagePullBackOff)"
    }
    # A RabbitMQ Pod may pass a basic ping before plugins have finished starting.
    # Wait for the ACTUAL running state (E* or e*), not merely enabled (E ).
    Step 'Waiting for RabbitMQ delayed-message plugin to be running'
    $pluginReady = $false
    $activePlugins = ''
    for ($attempt = 1; $attempt -le 30; $attempt++) {
        $pluginLines = @()
        $pluginExit = 1
        try {
            $pluginLines = @(& kubectl exec -n $ns rabbitmq-0 -- rabbitmq-plugins list -e 2>$null)
            $pluginExit = $LASTEXITCODE
        } catch {
            $pluginExit = 1
        }
        $activePlugins = $pluginLines -join "`n"
        if ($pluginExit -eq 0 -and $activePlugins -match '(?im)^\s*\[[Ee]\*\]\s+rabbitmq_delayed_message_exchange(?:\s|$)') {
            $pluginReady = $true
            Write-Host 'RabbitMQ delayed-message plugin active:' -ForegroundColor Green
            Write-Host ($Matches[0].Trim()) -ForegroundColor Green
            break
        }
        Write-Host "Plugin not yet running ($attempt/30); retrying in 5 seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
    if (-not $pluginReady) {
        Write-Host "Last RabbitMQ plugin list (exit code $pluginExit):" -ForegroundColor Yellow
        Write-Host $activePlugins
        try {
            $pod = & kubectl get pod rabbitmq-0 -n $ns -o json | ConvertFrom-Json
            Write-Host "Pod configured image: $($pod.spec.containers[0].image)"
            Write-Host "Pod actual image ID: $($pod.status.containerStatuses[0].imageID)"
        } catch {
            Write-Host 'Unable to read the RabbitMQ Pod image details.' -ForegroundColor Yellow
        }
        Write-Host 'RabbitMQ recent logs:' -ForegroundColor Yellow
        & kubectl logs -n $ns rabbitmq-0 --tail=100
        throw 'RabbitMQ delayed-message plugin is still not running. Orders saga will not start. Check the plugin output, image ID, and logs above.'
    }
    Step 'Provisioning 7 PostgreSQL databases and roles (idempotent)'
    foreach($s in @('identity','payments','library','catalog','promotions','orders','notifications')) {
        $role="fcg_${s}_app";$db="fcg_$s";$password=$v['PG_'+$s.ToUpperInvariant()+'_PASSWORD']
        if($password -notmatch '^[A-Za-z0-9_@!#$%+.-]+$'){throw "Password for $s has unsafe SQL characters; aborting."}
        $roleFound=(& kubectl exec -n $ns postgres-0 -- psql -X -At -v ON_ERROR_STOP=1 -U fcg_admin -d postgres -c "SELECT rolname FROM pg_roles WHERE rolname='$role';" | Out-String).Trim()
        Assert-Exit "Check role $role"
        if(-not $roleFound) {
            & kubectl exec -n $ns postgres-0 -- psql -X -q -v ON_ERROR_STOP=1 -U fcg_admin -d postgres -c "CREATE ROLE $role LOGIN PASSWORD '$password';"
            Assert-Exit "Create role $role"
        }
        $dbFound=(& kubectl exec -n $ns postgres-0 -- psql -X -At -v ON_ERROR_STOP=1 -U fcg_admin -d postgres -c "SELECT datname FROM pg_database WHERE datname='$db';" | Out-String).Trim()
        Assert-Exit "Check database $db"
        if(-not $dbFound) {
            & kubectl exec -n $ns postgres-0 -- psql -X -q -v ON_ERROR_STOP=1 -U fcg_admin -d postgres -c "CREATE DATABASE $db OWNER $role;"
            Assert-Exit "Create database $db"
        }
    }
    $names=@('identity','payments','library','catalog','promotions','orders','notifications')
    foreach($s in $names) {
        Step "Migrations: $s"
        $folder=Join-Path $parent "fcg-$s-service/k8s"
        $jobName=if($s -eq 'library'){'library-migrations-job.yaml'}else{'migrations-job.yaml'}
        $file=Join-Path $folder $jobName
        Assert-File $file
        $job="$s-migrations"
        # Run the migration executable at every invocation; it should be migration-idempotent.
        & kubectl delete job $job -n $ns --ignore-not-found=true --wait=true
        Assert-Exit "Remove old completed Job $job"
        & kubectl apply -f $file;Assert-Exit "Apply Job $job"
        & kubectl wait -n $ns --for=condition=complete "job/$job" --timeout=300s
        if($LASTEXITCODE -ne 0) {
            & kubectl logs -n $ns "job/$job" --tail=100
            throw "Migration $job FAILED. Stopping before APIs."
        }
        if($s -eq 'identity'){Ensure-OrdersClient 'K8s' $v}
    }
    Step 'Deploying 7 APIs and 4 Workers'
    foreach($s in $names) {
        $dir=Join-Path $parent "fcg-$s-service/k8s"
        $api=if($s -eq 'library'){'library-api.yaml'}else{'api.yaml'}
        & kubectl apply -f (Join-Path $dir $api);Assert-Exit "Apply $s API"
        if($s -in @('payments','library','orders','notifications')){
            $worker=if($s -eq 'library'){'library-worker.yaml'}else{'worker.yaml'}
            & kubectl apply -f (Join-Path $dir $worker);Assert-Exit "Apply $s Worker"
        }
    }
    $deployments=@('identity-api','payments-api','payments-worker','library-api','library-worker','catalog-api','promotions-api','orders-api','orders-worker','notifications-api','notifications-worker')
    if(-not $NoBuild) {
        # Same tag points to new image after build. Rollout restart forces running Pods to pick it up.
        foreach($d in $deployments){ & kubectl rollout restart "deployment/$d" -n $ns;Assert-Exit "Restart $d" }
    }
    foreach($d in $deployments){ & kubectl rollout status "deployment/$d" -n $ns --timeout=300s;Assert-Exit "Rollout $d" }
    Step 'All 11 Deployments ready; exposing local access'
    Start-Access $root -NoBrowser:$NoBrowser
    Write-Host 'K8s: http://127.0.0.1:5181-5187/swagger | RabbitMQ :15673 | pgAdmin 127.0.0.1:55432' -ForegroundColor Green
} finally {Pop-Location}

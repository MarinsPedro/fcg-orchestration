# Windows local-only access. Every port-forward is a separate background kubectl process,
# surviving the caller terminal (not Windows restart). Only owned PIDs can be stopped.
$accesses = @(
    @{Name='identity'; Resource='svc/identity-api'; LocalPort=5181; RemotePort=8080; Url='http://127.0.0.1:5181/swagger'},
    @{Name='payments'; Resource='svc/payments-api'; LocalPort=5182; RemotePort=8080; Url='http://127.0.0.1:5182/swagger'},
    @{Name='library'; Resource='svc/library-api'; LocalPort=5183; RemotePort=8080; Url='http://127.0.0.1:5183/swagger'},
    @{Name='catalog'; Resource='svc/catalog-api'; LocalPort=5184; RemotePort=8080; Url='http://127.0.0.1:5184/swagger'},
    @{Name='promotions'; Resource='svc/promotions-api'; LocalPort=5185; RemotePort=8080; Url='http://127.0.0.1:5185/swagger'},
    @{Name='orders'; Resource='svc/orders-api'; LocalPort=5186; RemotePort=8080; Url='http://127.0.0.1:5186/swagger'},
    @{Name='notifications'; Resource='svc/notifications-api'; LocalPort=5187; RemotePort=8080; Url='http://127.0.0.1:5187/swagger'},
    @{Name='rabbitmq'; Resource='svc/rabbitmq'; LocalPort=15673; RemotePort=15672; Url='http://127.0.0.1:15673'},
    @{Name='postgres'; Resource='svc/postgres'; LocalPort=55432; RemotePort=5432; Url='127.0.0.1:55432'}
)
function Test-Port([int]$Port) {
    $tcp=New-Object Net.Sockets.TcpClient
    try {
        $ar=$tcp.BeginConnect('127.0.0.1',$Port,$null,$null)
        try {
            if (-not $ar.AsyncWaitHandle.WaitOne(500)) {return $false}
            $tcp.EndConnect($ar);return $true
        }catch{return $false}finally{$ar.AsyncWaitHandle.Close()}
    }catch{return $false}finally{$tcp.Close()}
}
function Stop-Access([string]$Root) {
    $pidfile=Join-Path $Root 'runtime/port-forwards.json'
    if (-not (Test-Path $pidfile)) {return}
    try {$state=@(Get-Content $pidfile -Raw | ConvertFrom-Json)}catch{Write-Warning 'Old port-forward state file invalid';return}
    foreach($x in $state) {
        try {
            $p=Get-Process -Id ([int]$x.Pid) -ErrorAction Stop
            # PID reuse protection: verify process name and creation time.
            if ($p.ProcessName -eq 'kubectl' -and [string]$p.StartTime.ToUniversalTime().Ticks -eq [string]$x.StartTicks) {
                Stop-Process -Id $p.Id -Force
            }
        }catch{}
    }
    Remove-Item $pidfile -Force -ErrorAction SilentlyContinue
}
function Start-Access([string]$Root,[switch]$NoBrowser) {
    Step 'Publishing localhost URLs (without extra PowerShell windows)'
    Stop-Access $Root
    $kubectlBin=(Get-Command kubectl).Source
    $runs=@()
    $fail=@()
    foreach($a in $accesses) {
        $port=[int]$a.LocalPort
        if (Test-Port $port) {
            Write-Warning "Local port $port already in use; keeping the unrelated process untouched."
            $fail+= $a.Name
            continue
        }
        $logBase=Join-Path $Root "runtime/tunnel-$($a.Name)"
        $arguments=@('-n','fcg','port-forward','--address=127.0.0.1',$a.Resource,"${port}:$($a.RemotePort)")
        $p=Start-Process -FilePath $kubectlBin -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput "$logBase.out.log" -RedirectStandardError "$logBase.err.log"
        $runs+=@{Pid=$p.Id;StartTicks=[string]$p.StartTime.ToUniversalTime().Ticks;Port=$port;Name=$a.Name}
        $ready=$false
        for($i=0;$i -lt 24;$i++) {
            Start-Sleep -Milliseconds 250
            if(Test-Port $port){$ready=$true;break}
            $p.Refresh()
            if($p.HasExited){break}
        }
        if($ready) {Write-Host ("  {0,-12} {1}" -f $a.Name,$a.Url) -ForegroundColor Green}
        else { $fail+=$a.Name;Write-Warning "Tunnel $($a.Name) not ready; read $logBase.err.log" }
    }
    $pidfile=Join-Path $Root 'runtime/port-forwards.json'
    ConvertTo-Json -InputObject @($runs) -Depth 4 | Set-Content $pidfile -Encoding UTF8
    $cards= foreach($a in $accesses) {
        if($a.Name -eq 'postgres'){continue}
        '<a href="{0}" target="_blank" rel="noopener noreferrer"><strong>{1}</strong><small>{0}</small></a>' -f $a.Url,$a.Name.ToUpperInvariant()
    }
    $doc=@'
<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>FCG Kubernetes</title>
<style>body{background:#101827;color:#f2f5fc;font:16px Segoe UI,Arial,sans-serif;max-width:940px;margin:48px auto;padding:0 22px}h1{font-size:30px}p{color:#aab8d1}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:15px;margin:28px 0}a{display:flex;flex-direction:column;gap:10px;background:#1d2a43;color:white;text-decoration:none;border:1px solid #425575;padding:24px;border-radius:14px}a:hover{background:#273a60}small{color:#b6c9f0}footer{color:#aab8d1}</style></head>
<body><h1>FCG | Kubernetes</h1><p>Ambiente K8s local · 7 microsserviços · 4 Workers · PostgreSQL · RabbitMQ</p><main>
'@
    $doc+= ($cards -join "`n")
    $doc+=@'
</main><footer><p>pgAdmin: <code>127.0.0.1:55432</code> · banco <code>postgres</code> · usuário <code>fcg_admin</code>. Credenciais DEV em <code>runtime/k8s.env</code>.</p>
<p>Os serviços ficam ativos mesmo com o terminal fechado. Para recriar os túneis após reiniciar o Windows, execute FCG-K8S.cmd novamente.</p></footer></body></html>
'@
    $dashboard=Join-Path $Root 'runtime/FCG-K8S-URLs.html'
    [IO.File]::WriteAllText($dashboard,$doc,(New-Object Text.UTF8Encoding($false)))
    if(-not $NoBrowser){Start-Process $dashboard}
    if($fail.Count -gt 0){Write-Warning "Some URLs unavailable: $($fail -join ', '). Kubernetes deployments are unaffected."}
}

# Targeted update: reconnect ONLY the selected API tunnel. Restarting a Deployment
# terminates kubectl port-forward's connection to its previous Pod, even when the
# local Service has the same name. Unrelated tunnel processes are left running.
function Restart-ServiceAccess([string]$Root,[string]$Service,[switch]$NoBrowser) {
    $items=@($accesses | Where-Object { $_.Name -eq $Service })
    if($items.Count -ne 1){throw "No port-forward registered for service '$Service'."}
    $a=$items[0]
    $pidfile=Join-Path $Root 'runtime/port-forwards.json'
    $old=@()
    if(Test-Path $pidfile) {
        try {$old=@(Get-Content $pidfile -Raw | ConvertFrom-Json)}
        catch {Write-Warning 'Existing port-forward state is invalid; will not terminate untracked processes.'}
    }
    $keep=@()
    foreach($x in $old) {
        if([string]$x.Name -ne $Service){$keep+= $x;continue}
        try {
            $p=Get-Process -Id ([int]$x.Pid) -ErrorAction Stop
            if($p.ProcessName -eq 'kubectl' -and [string]$p.StartTime.ToUniversalTime().Ticks -eq [string]$x.StartTicks) {
                Stop-Process -Id $p.Id -Force
            }
        } catch { }
    }
    $port=[int]$a.LocalPort
    if(Test-Port $port) {
        Write-Warning "Port $port remains busy. Not touching an unrelated process; restart this tunnel manually if needed."
    } else {
        $bin=(Get-Command kubectl).Source
        $logBase=Join-Path $Root "runtime/tunnel-$Service"
        New-Item -ItemType Directory -Path (Split-Path $logBase -Parent) -Force | Out-Null
        $arguments=@('-n','fcg','port-forward','--address=127.0.0.1',$a.Resource,"${port}:$($a.RemotePort)")
        $p=Start-Process -FilePath $bin -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput "$logBase.out.log" -RedirectStandardError "$logBase.err.log"
        $ready=$false
        for($i=0;$i -lt 24;$i++) {
            Start-Sleep -Milliseconds 250
            if(Test-Port $port){$ready=$true;break}
            $p.Refresh()
            if($p.HasExited){break}
        }
        if($ready) {
            $keep+=@{Pid=$p.Id;StartTicks=[string]$p.StartTime.ToUniversalTime().Ticks;Port=$port;Name=$Service}
            Write-Host "  Port-forward restored: $($a.Url)" -ForegroundColor Green
        } else {
            Write-Warning "Tunnel $Service unavailable; check $logBase.err.log"
            try {if(-not $p.HasExited){Stop-Process -Id $p.Id -Force}}catch{}
        }
    }
    ConvertTo-Json -InputObject @($keep) -Depth 4 | Set-Content $pidfile -Encoding UTF8
    if(-not $NoBrowser -and (Test-Port $port)){Start-Process $a.Url}
}

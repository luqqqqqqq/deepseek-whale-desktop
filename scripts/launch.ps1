# V2 启动器：起本地 Node 服务 → 起透明鲸鱼 host.exe → 退出时停服务
param([switch]$Stop)
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $PSScriptRoot
$hostDir = Join-Path $dir 'releases\v2.0.0'
$port = 9876
$url = "http://127.0.0.1:$port/"

function Find-Node {
  $n = (Get-Command node -ErrorAction SilentlyContinue).Source
  if (-not $n) { $n = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe' }
  if ($n -and (Test-Path -LiteralPath $n)) { return $n }
  return $null
}

if ($Stop) {
  Get-Process node -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Get-Process host -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Write-Host '[OK] V2 已停止'
  exit 0
}

$node = Find-Node
if (-not $node) { '[错误] 找不到 node.exe，请先装 Node.js' | Out-File (Join-Path $dir 'launch.err.log'); exit 1 }
if (-not (Test-Path (Join-Path $hostDir 'host.exe'))) { '[错误] 找不到 releases\v2.0.0\host.exe，请按开发文档恢复或重新构建宿主' | Out-File (Join-Path $dir 'launch.err.log'); exit 1 }

# 先释放可能被残留进程占用的端口
try {
  $c = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
  foreach ($x in @($c | Select-Object -ExpandProperty OwningProcess -Unique)) {
    if ($x -and $x -ne $PID) { Stop-Process -Id $x -Force -ErrorAction SilentlyContinue }
  }
} catch {}
Start-Sleep -Milliseconds 500

Write-Host '[1/3] 启动本地服务…'
$log = Join-Path $dir 'server.log'
$errlog = Join-Path $dir 'server.err.log'
$serverScript = Join-Path $dir 'src\start.mjs'
$server = Start-Process $node -ArgumentList ('"' + $serverScript + '"') -WorkingDirectory $dir -PassThru -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError $errlog

$ok = $false
for ($i = 0; $i -lt 20; $i++) {
  Start-Sleep -Milliseconds 500
  try { $null = Invoke-RestMethod -Uri $url -TimeoutSec 2; $ok = $true; break } catch {}
}
if (-not $ok) {
  Write-Host '[错误] 本地服务没起来，看 server.log / server.err.log'
  Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
  exit 1
}

Write-Host '[2/3] 启动透明鲸鱼窗口…'
$hostProc = Start-Process (Join-Path $hostDir 'host.exe') -WorkingDirectory $hostDir -PassThru
Write-Host '[3/3] 已启动。鲸鱼窗口获得焦点后按 Esc 关闭，随后自动停服务。'
$hostProc.WaitForExit()
Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue

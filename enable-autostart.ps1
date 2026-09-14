$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$vbs = Join-Path $dir 'start-widget.vbs'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if (-not (Test-Path $runKey)) { New-Item -Path $runKey -Force | Out-Null }
$val = 'wscript.exe "' + $vbs + '"'
Set-ItemProperty -Path $runKey -Name 'DSHWhaleWidget' -Value $val -Force
Write-Host '[OK] Auto-start enabled:'
Write-Host ('  ' + $val)

param([switch]$Enable, [switch]$Disable)
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$name = 'DSHWhaleV2'
$cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $PSScriptRoot 'launch.ps1') + '"'
if ($Enable) { Set-ItemProperty -Path $runKey -Name $name -Value $cmd -Force; Write-Host '[OK] 开机自启已开启' }
elseif ($Disable) { Remove-ItemProperty -Path $runKey -Name $name -ErrorAction SilentlyContinue; Write-Host '[OK] 开机自启已关闭' }
else { Write-Host '用法：-Enable 开启 / -Disable 关闭' }

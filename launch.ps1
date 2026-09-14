$dir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$whale = Join-Path $dir 'whale.ps1'
Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $whale) -WindowStyle Hidden

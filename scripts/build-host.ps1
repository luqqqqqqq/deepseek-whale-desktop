# 编译 host.cs 为 host.exe（WPF 透明窗口 + WebView2）
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $PSScriptRoot

$fw = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$csc = Join-Path $fw 'csc.exe'
if (-not (Test-Path -LiteralPath $csc)) {
  $fw = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319'
  $csc = Join-Path $fw 'csc.exe'
}
if (-not (Test-Path -LiteralPath $csc)) { Write-Host '找不到 csc.exe'; exit 1 }

$wpfDir = Join-Path $fw 'WPF'
$systemXaml = Join-Path $env:WINDIR 'Microsoft.NET\assembly\GAC_MSIL\System.Xaml\v4.0_4.0.0.0__b77a5c561934e089\System.Xaml.dll'
$wvDir = Join-Path $dir 'tools\webview2'

$refs = @(
  (Join-Path $fw 'System.dll'),
  (Join-Path $fw 'System.Core.dll'),
  (Join-Path $fw 'System.Drawing.dll'),
  (Join-Path $wpfDir 'WindowsBase.dll'),
  (Join-Path $wpfDir 'PresentationCore.dll'),
  (Join-Path $wpfDir 'PresentationFramework.dll'),
  $systemXaml,
  (Join-Path $wvDir 'Microsoft.Web.WebView2.Core.dll'),
  (Join-Path $wvDir 'Microsoft.Web.WebView2.Wpf.dll')
)

foreach ($r in $refs) {
  if (-not (Test-Path -LiteralPath $r)) { Write-Host ('缺少引用: ' + $r); exit 1 }
}

$outputDir = Join-Path $dir 'build\desktop-host'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$out = Join-Path $outputDir 'host.exe'
& $csc /nologo /target:winexe /out:$out (Join-Path $dir 'src\host.cs') ('/reference:' + ($refs -join ','))
if ($LASTEXITCODE -ne 0) { Write-Host '[失败] 编译出错'; exit 1 }

Copy-Item (Join-Path $wvDir 'Microsoft.Web.WebView2.Core.dll') $outputDir -Force
Copy-Item (Join-Path $wvDir 'Microsoft.Web.WebView2.Wpf.dll') $outputDir -Force
Copy-Item (Join-Path $wvDir 'WebView2Loader.dll') $outputDir -Force
Write-Host '[OK] 已在 build\desktop-host 生成宿主与运行所需 DLL；更新默认启动文件请参阅 docs\development.md'

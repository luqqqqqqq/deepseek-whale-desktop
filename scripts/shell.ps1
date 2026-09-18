# 透明无边框 WebView2 外壳：只浮着一只鲸鱼
param([string]$Url = 'http://127.0.0.1:9876/')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

$dir = Split-Path -Parent $PSScriptRoot
$wvDir = Join-Path $dir 'tools\webview2'
$env:PATH = $wvDir + ';' + $env:PATH
Add-Type -Path (Join-Path $wvDir 'Microsoft.Web.WebView2.Core.dll')
Add-Type -Path (Join-Path $wvDir 'Microsoft.Web.WebView2.WinForms.dll')
Add-Type -Path (Join-Path $wvDir 'Microsoft.Web.WebView2.Wpf.dll')

$win = New-Object System.Windows.Window
$win.WindowStyle = [System.Windows.WindowStyle]::None
$win.ResizeMode = [System.Windows.ResizeMode]::NoResize
$win.AllowsTransparency = $true
$win.Background = [System.Windows.Media.Brushes]::Transparent
$win.Topmost = $true
$win.ShowInTaskbar = $false
$win.Width = 360
$win.Height = 360
$wa = [System.Windows.SystemParameters]::WorkArea
$win.Left = $wa.Right - $win.Width - 16
$win.Top = $wa.Bottom - $win.Height - 16

$wv = New-Object Microsoft.Web.WebView2.Wpf.WebView2
$wv.DefaultBackgroundColor = [System.Drawing.Color]::Transparent
$win.Content = $wv
$win.Add_Loaded({ $wv.Source = [Uri]$Url })

$win.Add_MouseLeftButtonDown({ if ($win.WindowState -eq 'Normal') { $win.DragMove() } })

$win.ShowDialog() | Out-Null

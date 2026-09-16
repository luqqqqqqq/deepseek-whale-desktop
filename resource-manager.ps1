# 资源管理：统一查看 / 预览 / 试听 / 删除自定义角色、音效片段、泡泡图
param([string]$AppDir = '', [switch]$Test)

$ErrorActionPreference = 'Stop'
if (-not $AppDir) { $AppDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

$RolesDir = Join-Path $AppDir 'whale-roles'
$AudioDir = Join-Path $AppDir 'whale-audio'
$ImgsDir  = Join-Path $AppDir 'whale-bubble-imgs'
foreach ($d in @($RolesDir, $AudioDir, $ImgsDir)) { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }

function To-Uri([string]$p) { return [System.Uri]::new('file:///' + ($p -replace '\\', '/')) }

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="资源管理" Width="620" Height="520" WindowStartupLocation="CenterScreen" Background="#F6F8FC">
  <Grid Margin="14">
    <Grid.RowDefinitions>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TabControl Grid.Row="0">
      <TabItem Header="角色图片">
        <Grid Margin="8">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="120"/></Grid.ColumnDefinitions>
          <ListBox x:Name="RoleList" SelectionMode="Single"/>
          <StackPanel Grid.Column="1" Margin="8,0,0,0">
            <Button x:Name="RoleImport" Content="导入图片…" Margin="0,0,0,8" Padding="4"/>
            <Button x:Name="RolePreview" Content="预览" Margin="0,0,0,8" Padding="4"/>
            <Button x:Name="RoleDelete" Content="删除" Padding="4"/>
          </StackPanel>
        </Grid>
      </TabItem>
      <TabItem Header="音效片段">
        <Grid Margin="8">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="120"/></Grid.ColumnDefinitions>
          <ListBox x:Name="AudioList" SelectionMode="Single"/>
          <StackPanel Grid.Column="1" Margin="8,0,0,0">
            <Button x:Name="AudioImport" Content="导入音频…" Margin="0,0,0,8" Padding="4"/>
            <Button x:Name="AudioPlay" Content="试听" Margin="0,0,0,8" Padding="4"/>
            <Button x:Name="AudioDelete" Content="删除" Padding="4"/>
          </StackPanel>
        </Grid>
      </TabItem>
      <TabItem Header="泡泡图">
        <Grid Margin="8">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="120"/></Grid.ColumnDefinitions>
          <ListBox x:Name="ImgList" SelectionMode="Single"/>
          <StackPanel Grid.Column="1" Margin="8,0,0,0">
            <Button x:Name="ImgImport" Content="导入图片…" Margin="0,0,0,8" Padding="4"/>
            <Button x:Name="ImgPreview" Content="预览" Margin="0,0,0,8" Padding="4"/>
            <Button x:Name="ImgDelete" Content="删除" Padding="4"/>
          </StackPanel>
        </Grid>
      </TabItem>
    </TabControl>
    <Grid Grid.Row="1" Margin="0,12,0,0">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <Image x:Name="PreviewImg" MaxHeight="120" Stretch="Uniform"/>
      <TextBlock Grid.Column="1" x:Name="PreviewHint" Text="" VerticalAlignment="Center" Foreground="#536ba9" FontSize="12"/>
    </Grid>
  </Grid>
</Window>
'@

$win = [System.Windows.Markup.XamlReader]::Parse($xaml)
$roleList = $win.FindName('RoleList'); $audioList = $win.FindName('AudioList'); $imgList = $win.FindName('ImgList')
$previewImg = $win.FindName('PreviewImg'); $previewHint = $win.FindName('PreviewHint')

function Refresh-List([System.Windows.Controls.ListBox]$box, [string]$dir, [string[]]$exts) {
  $box.Items.Clear()
  try {
    $files = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object { $exts -contains $_.Extension.ToLower() } | Sort-Object Name)
    foreach ($f in $files) { $box.Items.Add((New-Object System.Windows.Controls.ListBoxItem -Property @{ Content = $f.Name; Tag = $f.FullName })) | Out-Null }
  } catch {}
}

function Get-SelPath($box) {
  $it = $box.SelectedItem
  if ($it -and $it.Tag) { return [string]$it.Tag }
  return ''
}

function Import-File([string]$dir, [string]$filter) {
  $dlg = New-Object Microsoft.Win32.OpenFileDialog
  $dlg.Filter = $filter
  if ($dlg.ShowDialog() -ne $true) { return }
  $src = [string]$dlg.FileName
  $name = [System.IO.Path]::GetFileName($src)
  $dst = Join-Path $dir $name
  $n = 1
  while (Test-Path -LiteralPath $dst) {
    $dst = Join-Path $dir (([System.IO.Path]::GetFileNameWithoutExtension($name)) + '_' + $n + [System.IO.Path]::GetExtension($name))
    $n++
  }
  [System.IO.File]::Copy($src, $dst)
  return $dst
}

function Show-Preview([string]$path) {
  try {
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $fs = [System.IO.File]::OpenRead($path)
    $bi.BeginInit(); $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad; $bi.StreamSource = $fs; $bi.EndInit(); $fs.Close()
    $previewImg.Source = $bi
    $previewHint.Text = [System.IO.Path]::GetFileName($path)
  } catch { $previewHint.Text = '无法预览此文件' }
}

$script:player = New-Object System.Windows.Media.MediaPlayer
$script:player.Add_MediaEnded({ $previewHint.Text = '试听结束' })

$roleList.Add_SelectionChanged({ $p = Get-SelPath $roleList; if ($p) { Show-Preview $p } })
$imgList.Add_SelectionChanged({ $p = Get-SelPath $imgList; if ($p) { Show-Preview $p } })

$roleImport = $win.FindName('RoleImport'); $rolePreview = $win.FindName('RolePreview'); $roleDelete = $win.FindName('RoleDelete')
$audioImport = $win.FindName('AudioImport'); $audioPlay = $win.FindName('AudioPlay'); $audioDelete = $win.FindName('AudioDelete')
$imgImport = $win.FindName('ImgImport'); $imgPreview = $win.FindName('ImgPreview'); $imgDelete = $win.FindName('ImgDelete')

$roleImport.Add_Click({ $r = Import-File $RolesDir '图片|*.png;*.jpg;*.jpeg;*.gif'; if ($r) { Refresh-List $roleList $RolesDir @('.png','.jpg','.jpeg','.gif') } })
$rolePreview.Add_Click({ $p = Get-SelPath $roleList; if ($p) { Show-Preview $p } })
$roleDelete.Add_Click({ $p = Get-SelPath $roleList; if ($p) { [System.IO.File]::Delete($p); Refresh-List $roleList $RolesDir @('.png','.jpg','.jpeg','.gif') } })

$audioImport.Add_Click({ $r = Import-File $AudioDir '音频|*.mp3;*.wav'; if ($r) { Refresh-List $audioList $AudioDir @('.mp3','.wav') } })
$audioPlay.Add_Click({ $p = Get-SelPath $audioList; if ($p) { $previewHint.Text = '正在试听 ' + [System.IO.Path]::GetFileName($p); $script:player.Open((To-Uri $p)); $script:player.Play() } })
$audioDelete.Add_Click({ $p = Get-SelPath $audioList; if ($p) { [System.IO.File]::Delete($p); Refresh-List $audioList $AudioDir @('.mp3','.wav') } })

$imgImport.Add_Click({ $r = Import-File $ImgsDir '图片|*.png;*.jpg;*.jpeg;*.gif'; if ($r) { Refresh-List $imgList $ImgsDir @('.png','.jpg','.jpeg','.gif') } })
$imgPreview.Add_Click({ $p = Get-SelPath $imgList; if ($p) { Show-Preview $p } })
$imgDelete.Add_Click({ $p = Get-SelPath $imgList; if ($p) { [System.IO.File]::Delete($p); Refresh-List $imgList $ImgsDir @('.png','.jpg','.jpeg','.gif') } })

Refresh-List $roleList $RolesDir @('.png','.jpg','.jpeg','.gif')
Refresh-List $audioList $AudioDir @('.mp3','.wav')
Refresh-List $imgList $ImgsDir @('.png','.jpg','.jpeg','.gif')

if ($Test) {
  $t = New-Object System.Windows.Threading.DispatcherTimer
  $t.Interval = [TimeSpan]::FromSeconds(2)
  $t.Add_Tick({ $t.Stop(); $win.Close() })
  $t.Start()
}

$win.ShowDialog() | Out-Null

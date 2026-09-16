# 模块化泡泡编辑器：点击序列 + 模块行 + 样式 + 模块库
param([string]$AppDir = '', [switch]$Test)
$ErrorActionPreference = 'Stop'
if (-not $AppDir) { $AppDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

$BubbleFile = Join-Path $AppDir '.dshw-bubble.json'
$script:data = $null
if (Test-Path -LiteralPath $BubbleFile) { try { $script:data = Get-Content -LiteralPath $BubbleFile -Raw | ConvertFrom-Json } catch {} }
if (-not $script:data) { $script:data = [pscustomobject]@{ version = 1; clickAdvance = $false; bubbles = @(); library = @() } }
if (-not $script:data.bubbles) { $script:data.bubbles = @() }
if (-not $script:data.library) { $script:data.library = @() }

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="自定义泡泡" Width="820" Height="600" WindowStartupLocation="CenterScreen" Background="#F6F8FC">
  <Grid Margin="12">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <CheckBox x:Name="ClickAdvance" Content="点按角色推进队列（点一下往后一项）" VerticalAlignment="Center" Margin="0,0,0,8"/>
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions><ColumnDefinition Width="180"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <DockPanel Grid.Column="0">
        <StackPanel DockPanel.Dock="Bottom">
          <Button x:Name="AddBubble" Content="＋ 添加泡泡" Margin="0,6,0,2" Padding="4"/>
          <Button x:Name="DelBubble" Content="－ 删除泡泡" Margin="0,0,0,2" Padding="4"/>
          <Button x:Name="UpBubble" Content="↑ 上移" Padding="4"/>
          <Button x:Name="DownBubble" Content="↓ 下移" Margin="0,0,0,2" Padding="4"/>
        </StackPanel>
        <ListBox x:Name="BubbleList"/>
      </DockPanel>
      <DockPanel Grid.Column="1" Margin="8,0">
        <StackPanel DockPanel.Dock="Top" Margin="0,0,0,6">
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="名称" VerticalAlignment="Center" Foreground="#203170" FontSize="12"/>
            <TextBox x:Name="BubbleName" Width="150" Margin="6,0,12,0"/>
            <TextBlock Text="权重" VerticalAlignment="Center" Foreground="#203170" FontSize="12"/>
            <TextBox x:Name="BubbleWeight" Width="50" Margin="6,0,0,0"/>
          </StackPanel>
        </StackPanel>
        <StackPanel DockPanel.Dock="Bottom">
          <Button x:Name="AddRow" Content="＋ 加行" Margin="0,0,0,2" Padding="4"/>
          <Button x:Name="DelRow" Content="－ 删行" Margin="0,0,0,2" Padding="4"/>
          <Button x:Name="UpRow" Content="↑ 上移" Padding="4"/>
          <Button x:Name="DownRow" Content="↓ 下移" Margin="0,0,0,2" Padding="4"/>
        </StackPanel>
        <ListBox x:Name="RowList"/>
      </DockPanel>
      <DockPanel Grid.Column="2">
        <StackPanel DockPanel.Dock="Bottom">
          <Button x:Name="AddModule" Content="＋ 加模块" Margin="0,0,0,2" Padding="4"/>
          <Button x:Name="EditModule" Content="✎ 编辑模块" Margin="0,0,0,2" Padding="4"/>
          <Button x:Name="DelModule" Content="－ 删模块" Margin="0,0,0,2" Padding="4"/>
          <Button x:Name="SaveLib" Content="▣ 存到库" Margin="0,6,0,2" Padding="4"/>
          <Button x:Name="FromLib" Content="▤ 从库插入" Margin="0,0,0,2" Padding="4"/>
        </StackPanel>
        <ListBox x:Name="ModuleList"/>
      </DockPanel>
    </Grid>
    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="SaveBtn" Content="保存" Width="90" Padding="6,4" Margin="0,0,8,0"/>
      <Button x:Name="CancelBtn" Content="取消" Width="90" Padding="6,4"/>
    </StackPanel>
  </Grid>
</Window>
'@

$win = [System.Windows.Markup.XamlReader]::Parse($xaml)
$bubbleList = $win.FindName('BubbleList'); $rowList = $win.FindName('RowList'); $moduleList = $win.FindName('ModuleList')
$bubbleName = $win.FindName('BubbleName'); $bubbleWeight = $win.FindName('BubbleWeight')
$clickAdvance = $win.FindName('ClickAdvance')

function Save-Data { try { [System.IO.File]::WriteAllText($BubbleFile, (($script:data | ConvertTo-Json -Depth 12) + "`r`n"), (New-Object System.Text.UTF8Encoding($false))) } catch {} }
function New-Module { return [pscustomobject]@{ type = 'text'; text = ''; style = [pscustomobject]@{ size = 12; bold = $false; italic = $false; underline = $false; color = '#536ba9'; bg = '' } } }
function Mod-Label($m) {
  switch ([string]$m.type) {
    'text' { return '文本：' + [string]$m.text }
    'link' { return '链接：' + [string]$m.text }
    'random' { return '随机语句（' + @($m.items).Count + ' 条）' }
    'image' { return '图片：' + [string]$m.file }
    'randomImage' { return '随机图片（' + @($m.items).Count + ' 张）' }
    'balance' { return '余额数值' }
    'today' { return '今日已用' }
    'peak' { return '峰谷时段' }
  }
  return [string]$m.type
}
function Row-Label($r) { return ((@($r.modules) | ForEach-Object { Mod-Label $_ }) -join '  |  ') }

function Refresh-BubbleList {
  $bubbleList.Items.Clear()
  foreach ($b in @($script:data.bubbles)) { $bubbleList.Items.Add((New-Object System.Windows.Controls.ListBoxItem -Property @{ Content = ('[' + $b.weight + '] ' + $b.name); Tag = $b })) | Out-Null }
}
function Refresh-Rows {
  $rowList.Items.Clear(); $b = $bubbleList.SelectedItem; if (-not $b) { return }
  foreach ($r in @($b.Tag.rows)) { $rowList.Items.Add((New-Object System.Windows.Controls.ListBoxItem -Property @{ Content = (Row-Label $r); Tag = $r })) | Out-Null }
}
function Refresh-Modules {
  $moduleList.Items.Clear(); $r = $rowList.SelectedItem; if (-not $r) { return }
  foreach ($m in @($r.Tag.modules)) { $moduleList.Items.Add((New-Object System.Windows.Controls.ListBoxItem -Property @{ Content = (Mod-Label $m); Tag = $m })) | Out-Null }
}
function Sync-NameWeight {
  $b = $bubbleList.SelectedItem; if (-not $b) { $bubbleName.Text = ''; $bubbleWeight.Text = ''; return }
  $bubbleName.Text = [string]$b.Tag.name; $bubbleWeight.Text = [string]$b.Tag.weight
}

function Edit-Module([System.Object]$m) {
  $dlgXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="编辑模块" Width="430" Height="470" WindowStartupLocation="CenterOwner" Background="#F6F8FC">
  <StackPanel Margin="14">
    <TextBlock Text="类型" Foreground="#203170" FontSize="12"/>
    <ComboBox x:Name="TypeCombo" Margin="0,4,0,8">
      <ComboBoxItem Content="文本" Tag="text"/><ComboBoxItem Content="链接" Tag="link"/>
      <ComboBoxItem Content="随机语句" Tag="random"/><ComboBoxItem Content="图片" Tag="image"/>
      <ComboBoxItem Content="随机图片" Tag="randomImage"/><ComboBoxItem Content="余额数值" Tag="balance"/>
      <ComboBoxItem Content="今日已用" Tag="today"/><ComboBoxItem Content="峰谷时段" Tag="peak"/>
    </ComboBox>
    <TextBlock Text="内容" Foreground="#203170" FontSize="12"/>
    <TextBox x:Name="ContentBox" AcceptsReturn="True" TextWrapping="Wrap" Height="90" Margin="0,4,0,4"/>
    <TextBlock x:Name="ContentHint" Text="" Foreground="#9fb0d9" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,8"/>
    <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
      <TextBlock Text="字号" VerticalAlignment="Center" Foreground="#203170" FontSize="12"/><TextBox x:Name="SizeBox" Width="40" Margin="6,0,12,0"/>
      <CheckBox x:Name="BoldBox" Content="粗" VerticalAlignment="Center" Margin="0,0,8,0"/>
      <CheckBox x:Name="ItalicBox" Content="斜" VerticalAlignment="Center" Margin="0,0,8,0"/>
      <CheckBox x:Name="UnderBox" Content="下划线" VerticalAlignment="Center"/>
    </StackPanel>
    <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
      <TextBlock Text="文字色" VerticalAlignment="Center" Foreground="#203170" FontSize="12"/><TextBox x:Name="ColorBox" Width="80" Margin="6,0,12,0"/>
      <TextBlock Text="背景色" VerticalAlignment="Center" Foreground="#203170" FontSize="12"/><TextBox x:Name="BgBox" Width="80" Margin="6,0,0,0"/>
    </StackPanel>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="OkBtn" Content="确定" Width="80" Padding="5,3" Margin="0,0,8,0"/><Button x:Name="CancelDlg" Content="取消" Width="80" Padding="5,3"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
  $dlg = [System.Windows.Markup.XamlReader]::Parse($dlgXaml)
  $typeCombo = $dlg.FindName('TypeCombo'); $contentBox = $dlg.FindName('ContentBox'); $contentHint = $dlg.FindName('ContentHint')
  $sizeBox = $dlg.FindName('SizeBox'); $boldBox = $dlg.FindName('BoldBox'); $italicBox = $dlg.FindName('ItalicBox'); $underBox = $dlg.FindName('UnderBox')
  $colorBox = $dlg.FindName('ColorBox'); $bgBox = $dlg.FindName('BgBox')
  $SetHint = { switch ([string]$typeCombo.SelectedItem.Tag) {
    'text' { $contentHint.Text = '文本内容' }
    'link' { $contentHint.Text = '一行：显示文字 | 网址' }
    'random' { $contentHint.Text = '每行一句，可带权重：句子 | 权重' }
    'image' { $contentHint.Text = '图片文件名（whale-bubble-imgs 里），一行一个' }
    'randomImage' { $contentHint.Text = '每行一张：文件名 | 权重' }
    default { $contentHint.Text = '（此类型无需内容）' }
  } }
  $typeCombo.Add_SelectionChanged({ & $SetHint })
  foreach ($it in $typeCombo.Items) { if ([string]$it.Tag -eq [string]$m.type) { $typeCombo.SelectedItem = $it } }
  switch ([string]$m.type) {
    'text' { $contentBox.Text = [string]$m.text }
    'link' { $contentBox.Text = ([string]$m.text) + ' | ' + ([string]$m.url) }
    'random' { $contentBox.Text = (@($m.items) | ForEach-Object { $_.text + ' | ' + $_.weight }) -join "`r`n" }
    'image' { $contentBox.Text = [string]$m.file }
    'randomImage' { $contentBox.Text = (@($m.items) | ForEach-Object { $_.file + ' | ' + $_.weight }) -join "`r`n" }
    default { $contentBox.Text = '' }
  }
  $sizeBox.Text = [string]$m.style.size; $boldBox.IsChecked = [bool]$m.style.bold; $italicBox.IsChecked = [bool]$m.style.italic; $underBox.IsChecked = [bool]$m.style.underline
  $colorBox.Text = [string]$m.style.color; $bgBox.Text = [string]$m.style.bg
  & $SetHint
  $ok = $false
  $dlg.FindName('OkBtn').Add_Click({
    $script:m = $null
    try {
      $t = [string]$typeCombo.SelectedItem.Tag; $nm = New-Module; $nm.type = $t
      $nm.style.size = [double]$sizeBox.Text; $nm.style.bold = [bool]$boldBox.IsChecked; $nm.style.italic = [bool]$italicBox.IsChecked; $nm.style.underline = [bool]$underBox.IsChecked
      $nm.style.color = [string]$colorBox.Text; $nm.style.bg = [string]$bgBox.Text
      $lines = @($contentBox.Text -split "`r?`n" | Where-Object { $_.Trim() })
      switch ($t) {
        'text' { $nm.text = [string]$contentBox.Text }
        'link' { $p = [string]$contentBox.Text -split '\|'; $nm.text = $p[0].Trim(); if ($p.Count -gt 1) { $nm.url = $p[1].Trim() } else { $nm.url = '' } }
        'random' { $nm.items = @(); foreach ($l in $lines) { $p2 = $l -split '\|'; $w = 1; if ($p2.Count -gt 1) { $w = [int]$p2[1] }; $nm.items += [pscustomobject]@{ text = $p2[0].Trim(); weight = $w } } }
        'image' { $nm.file = if ($lines.Count) { $lines[0].Trim() } else { '' } }
        'randomImage' { $nm.items = @(); foreach ($l in $lines) { $p2 = $l -split '\|'; $w = 1; if ($p2.Count -gt 1) { $w = [int]$p2[1] }; $nm.items += [pscustomobject]@{ file = $p2[0].Trim(); weight = $w } } }
      }
      $script:m = $nm; $ok = $true
    } catch {}
    $dlg.Close()
  })
  $dlg.FindName('CancelDlg').Add_Click({ $dlg.Close() })
  $dlg.ShowDialog() | Out-Null
  return $ok
}

$bubbleList.Add_SelectionChanged({ Sync-NameWeight; Refresh-Rows; Refresh-Modules })
$rowList.Add_SelectionChanged({ Refresh-Modules })
$clickAdvance.IsChecked = [bool]$script:data.clickAdvance

$win.FindName('AddBubble').Add_Click({ $b = [pscustomobject]@{ name = '新泡泡'; weight = 1; rows = @(@{ modules = @((New-Module)) }) }; $script:data.bubbles = @($script:data.bubbles) + $b; Refresh-BubbleList })
$win.FindName('DelBubble').Add_Click({ $b = $bubbleList.SelectedItem; if (-not $b) { return }; $script:data.bubbles = @($script:data.bubbles | Where-Object { $_ -ne $b.Tag }); Refresh-BubbleList; Refresh-Rows; Refresh-Modules })
function Move-Bubble([int]$d) { $idx = $bubbleList.SelectedIndex; if ($idx -lt 0) { return }; $arr = [System.Collections.ArrayList]@($script:data.bubbles); $ni = $idx + $d; if ($ni -lt 0 -or $ni -ge $arr.Count) { return }; $tmp = $arr[$idx]; $arr[$idx] = $arr[$ni]; $arr[$ni] = $tmp; $script:data.bubbles = @($arr); Refresh-BubbleList; $bubbleList.SelectedIndex = $ni }
$win.FindName('UpBubble').Add_Click({ Move-Bubble -1 }); $win.FindName('DownBubble').Add_Click({ Move-Bubble 1 })
$win.FindName('AddRow').Add_Click({ $b = $bubbleList.SelectedItem; if (-not $b) { return }; $b.Tag.rows = @($b.Tag.rows) + [pscustomobject]@{ modules = @((New-Module)) }; Refresh-Rows })
$win.FindName('DelRow').Add_Click({ $r = $rowList.SelectedItem; if (-not $r) { return }; $b = $bubbleList.SelectedItem; $b.Tag.rows = @($b.Tag.rows | Where-Object { $_ -ne $r.Tag }); Refresh-Rows; Refresh-Modules })
function Move-Row([int]$d) { $idx = $rowList.SelectedIndex; if ($idx -lt 0) { return }; $b = $bubbleList.SelectedItem; $arr = [System.Collections.ArrayList]@($b.Tag.rows); $ni = $idx + $d; if ($ni -lt 0 -or $ni -ge $arr.Count) { return }; $tmp = $arr[$idx]; $arr[$idx] = $arr[$ni]; $arr[$ni] = $tmp; $b.Tag.rows = @($arr); Refresh-Rows; $rowList.SelectedIndex = $ni }
$win.FindName('UpRow').Add_Click({ Move-Row -1 }); $win.FindName('DownRow').Add_Click({ Move-Row 1 })
$win.FindName('AddModule').Add_Click({ $r = $rowList.SelectedItem; if (-not $r) { return }; $m = New-Module; if (Edit-Module $m) { $r.Tag.modules = @($r.Tag.modules) + $script:m; Refresh-Modules } })
$win.FindName('EditModule').Add_Click({ $mi = $moduleList.SelectedItem; if (-not $mi) { return }; if (Edit-Module $mi.Tag) { $mi.Tag.type = $script:m.type; $mi.Tag.text = $script:m.text; $mi.Tag.url = $script:m.url; $mi.Tag.file = $script:m.file; $mi.Tag.items = $script:m.items; $mi.Tag.style = $script:m.style; Refresh-Modules } })
$win.FindName('DelModule').Add_Click({ $mi = $moduleList.SelectedItem; if (-not $mi) { return }; $r = $rowList.SelectedItem; $r.Tag.modules = @($r.Tag.modules | Where-Object { $_ -ne $mi.Tag }); Refresh-Modules })
$win.FindName('SaveLib').Add_Click({ $mi = $moduleList.SelectedItem; if (-not $mi) { return }; $script:data.library = @($script:data.library) + $mi.Tag })
$win.FindName('FromLib').Add_Click({ $r = $rowList.SelectedItem; if (-not $r) { return }; $lw = New-Object System.Windows.Window; $lw.Title = '从库插入'; $lw.Width = 340; $lw.Height = 360; $lw.WindowStartupLocation = 'CenterOwner'; $lw.Background = '#F6F8FC'; $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = New-Object System.Windows.Thickness 12; $libList = New-Object System.Windows.Controls.ListBox; $libList.Height = 280; foreach ($m in @($script:data.library)) { $libList.Items.Add((New-Object System.Windows.Controls.ListBoxItem -Property @{ Content = (Mod-Label $m); Tag = $m })) | Out-Null }; $okbtn = New-Object System.Windows.Controls.Button; $okbtn.Content = '插入'; $okbtn.Margin = New-Object System.Windows.Thickness 0,8,0,0; $okbtn.Add_Click({ $sel = $libList.SelectedItem; if ($sel) { $r.Tag.modules = @($r.Tag.modules) + $sel.Tag; Refresh-Modules }; $lw.Close() }); $sp.Children.Add($libList) | Out-Null; $sp.Children.Add($okbtn) | Out-Null; $lw.Content = $sp; $lw.Owner = $win; $lw.ShowDialog() | Out-Null })
$bubbleName.Add_LostFocus({ $b = $bubbleList.SelectedItem; if ($b) { $b.Tag.name = $bubbleName.Text; Refresh-BubbleList } })
$bubbleWeight.Add_LostFocus({ $b = $bubbleList.SelectedItem; if ($b) { $b.Tag.weight = [int]$bubbleWeight.Text; Refresh-BubbleList } })
$win.FindName('SaveBtn').Add_Click({ $script:data.clickAdvance = [bool]$clickAdvance.IsChecked; Save-Data; $win.Close() })
$win.FindName('CancelBtn').Add_Click({ $win.Close() })

function Enable-DragReorder($list, [scriptblock]$GetArr, [scriptblock]$SetArr, [scriptblock]$Refresh) {
  $list.AllowDrop = $true
  $script:srcIdx = -1
  $list.Add_PreviewMouseLeftButtonDown({ param($s, $e) $script:srcIdx = $list.SelectedIndex })
  $list.Add_MouseMove({
    if ($script:srcIdx -lt 0) { return }
    if ([System.Windows.Input.Mouse]::LeftButton -ne [System.Windows.Input.MouseButtonState]::Pressed) { return }
    try { [System.Windows.DragDrop]::DoDragDrop($list, ([string]$script:srcIdx), [System.Windows.DragDropEffects]::Move) | Out-Null } catch {}
    $script:srcIdx = -1
  })
  $list.Add_DragOver({ param($s, $e) $e.Effects = [System.Windows.DragDropEffects]::Move; $e.Handled = $true })
  $list.Add_Drop({
    param($s, $e)
    try {
      $from = [int]$e.Data.GetData([string])
      $pt = $e.GetPosition($list)
      $hit = $list.InputHitTest($pt)
      $target = -1
      if ($hit -is [System.Windows.Controls.ListBoxItem]) { $target = $list.Items.IndexOf($hit) }
      if ($target -lt 0) { $target = $list.Items.Count - 1 }
      $arr = @(& $GetArr)
      if ($from -lt 0 -or $from -ge $arr.Count -or $target -lt 0 -or $target -ge $arr.Count -or $from -eq $target) { return }
      $tmp = $arr[$from]
      $new = New-Object System.Collections.ArrayList
      $new.AddRange($arr) | Out-Null
      $new.RemoveAt($from)
      if ($target -gt $from) { $target-- }
      $new.Insert($target, $tmp)
      & $SetArr @($new)
      & $Refresh
    } catch {}
  })
}

Enable-DragReorder $bubbleList { $script:data.bubbles } { param($v) $script:data.bubbles = $v } { Refresh-BubbleList }
Enable-DragReorder $rowList { $bubbleList.SelectedItem.Tag.rows } { param($v) $bubbleList.SelectedItem.Tag.rows = $v } { Refresh-Rows }
Enable-DragReorder $moduleList { $rowList.SelectedItem.Tag.modules } { param($v) $rowList.SelectedItem.Tag.modules = $v } { Refresh-Modules }

Refresh-BubbleList
if (@($script:data.bubbles).Count) { $bubbleList.SelectedIndex = 0 }
if ($Test) { $t = New-Object System.Windows.Threading.DispatcherTimer; $t.Interval = [TimeSpan]::FromSeconds(2); $t.Add_Tick({ $t.Stop(); $win.Close() }); $t.Start() }
$win.ShowDialog() | Out-Null

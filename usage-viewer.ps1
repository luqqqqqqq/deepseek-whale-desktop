# 用量记录窗口：今日模型消费 / 近7天 / 全部明细（按日期分组）/ 模型占比条 / 搜索
param([string]$AppDir = '', [switch]$Test)
$ErrorActionPreference = 'Stop'
if (-not $AppDir) { $AppDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

$TurnsFile = Join-Path $AppDir '.dshw-turns.json'
$script:records = @()
if (Test-Path -LiteralPath $TurnsFile) { try { $script:records = @(Get-Content -LiteralPath $TurnsFile -Raw | ConvertFrom-Json) } catch {} }

function Friendly-Model([string]$m) {
  $t = [string]$m
  $map = @{
    'deepseek-flash' = 'DeepSeek-V4.1-Flash'
    'deepseek-v4-flash-vision-exp' = 'DeepSeek-V4.1-Flash（旧名）'
    'deepseek-v4-flash' = 'DeepSeek-V4.1-Flash（旧名）'
    'deepseek-v4-pro' = 'DeepSeek-V4-Pro'
    'deepseek-chat' = 'DeepSeek-V3'
    'deepseek-reasoner' = 'DeepSeek-R1'
    'codex' = 'Codex（本地）'
  }
  if ($map.ContainsKey($t)) { return $map[$t] }
  return $t
}
function DayOf([string]$s) { if ($s -and $s.Length -ge 10) { return $s.Substring(0, 10) } return '' }

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="用量记录" Width="760" Height="620" WindowStartupLocation="CenterScreen" Background="#F6F8FC">
  <Grid Margin="12">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <TextBlock x:Name="Summary" Text="..." Foreground="#203170" FontSize="13" TextWrapping="Wrap" Margin="0,0,0,6"/>
    <ScrollViewer Grid.Row="1" MaxHeight="150" VerticalScrollBarVisibility="Auto" Margin="0,0,0,6">
      <StackPanel x:Name="Bars"/>
    </ScrollViewer>
    <TextBox x:Name="Search" Grid.Row="2" Height="28" Margin="0,0,0,8" FontSize="13" ToolTip="按模型名或日期搜索"/>
    <ListBox x:Name="List" Grid.Row="3" FontFamily="Consolas" FontSize="12"/>
  </Grid>
</Window>
'@

$win = [System.Windows.Markup.XamlReader]::Parse($xaml)
$summary = $win.FindName('Summary'); $search = $win.FindName('Search'); $list = $win.FindName('List'); $bars = $win.FindName('Bars')

function Refresh-View {
  $bars.Children.Clear()
  $list.Items.Clear()
  $today = (Get-Date).ToString('yyyy-MM-dd')
  $week0 = (Get-Date).AddDays(-6).ToString('yyyy-MM-dd')
  $todayRec = @(); $weekRec = @(); $totTok = 0.0; $totCost = 0.0
  $byModel = @{}
  foreach ($r in @($script:records)) {
    $tok = [double]$r.tokens; $cost = [double]$r.cost
    $totTok += $tok; $totCost += $cost
    if ((DayOf ([string]$r.date)) -eq $today) { $todayRec += $r }
    if ((DayOf ([string]$r.date)) -ge $week0) { $weekRec += $r }
    $fm = Friendly-Model ([string]$r.model)
    if (-not $byModel.ContainsKey($fm)) { $byModel[$fm] = @{ tokens = 0.0; cost = 0.0; turns = 0; today = 0.0; todayCost = 0.0 } }
    $byModel[$fm].tokens += $tok; $byModel[$fm].cost += $cost; $byModel[$fm].turns += 1
    if ((DayOf ([string]$r.date)) -eq $today) { $byModel[$fm].today += $tok; $byModel[$fm].todayCost += $cost }
  }
  $tTok = ($todayRec | Measure-Object -Property tokens -Sum).Sum
  $tCost = ($todayRec | Measure-Object -Property cost -Sum).Sum
  $wTok = ($weekRec | Measure-Object -Property tokens -Sum).Sum
  $wCost = ($weekRec | Measure-Object -Property cost -Sum).Sum
  $summary.Text = ('今日 {0} 轮 · {1} tokens · ¥{2}   |   近7天 {3} tokens · ¥{4}   |   累计 {5} 轮 · {6} tokens · ¥{7}' -f `
    @($todayRec).Count, ([long]$tTok).ToString('N0'), ([double]$tCost).ToString('0.00'), `
    ([long]$wTok).ToString('N0'), ([double]$wCost).ToString('0.00'), `
    @($script:records).Count, ([long]$totTok).ToString('N0'), ([double]$totCost).ToString('0.00'))

  # 模型占比条 + 今日消费
  foreach ($k in ($byModel.Keys | Sort-Object { -$byModel[$_].tokens })) {
    $m = $byModel[$k]
    $pct = if ($totTok -gt 0) { [math]::Round($m.tokens / $totTok * 100, 1) } else { 0 }
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    $row.Margin = New-Object System.Windows.Thickness 0,0,0,2
    $lab = New-Object System.Windows.Controls.TextBlock
    $lab.Text = ('{0}  今日 {1} tok · ¥{2}  累计 {3} tok · ¥{4}' -f $k, ([long]$m.today).ToString('N0'), ([double]$m.todayCost).ToString('0.00'), ([long]$m.tokens).ToString('N0'), ([double]$m.cost).ToString('0.00'))
    $lab.Foreground = '#203170'; $lab.FontSize = 12; $lab.Width = 400
    $bar = New-Object System.Windows.Controls.ProgressBar
    $bar.Width = 200; $bar.Height = 12; $bar.Maximum = 100; $bar.Value = $pct
    $bar.Margin = New-Object System.Windows.Thickness 8,0,4,0
    $pctLab = New-Object System.Windows.Controls.TextBlock
    $pctLab.Text = ($pct.ToString() + '%'); $pctLab.Foreground = '#536ba9'; $pctLab.FontSize = 11; $pctLab.Width = 44
    $row.Children.Add($lab) | Out-Null; $row.Children.Add($bar) | Out-Null; $row.Children.Add($pctLab) | Out-Null
    $bars.Children.Add($row) | Out-Null
  }

  # 明细：按日期分组，新的在上
  $q = $search.Text.Trim()
  $byDate = $script:records | Group-Object { DayOf ([string]$_.date) } | Sort-Object Name -Descending
  foreach ($g in $byDate) {
    $items = @($g.Group | Sort-Object { [long]$_.ts } -Descending | Where-Object { -not $q -or ([string]$_.model) -match [regex]::Escape($q) -or ([string]$_.date) -match [regex]::Escape($q) })
    if (-not $items.Count) { continue }
    $hdr = New-Object System.Windows.Controls.ListBoxItem
    $hdr.Content = ('—— ' + $g.Name + ' ——'); $hdr.FontWeight = 'Bold'; $hdr.Foreground = '#203170'; $hdr.FontSize = 13
    $list.Items.Add($hdr) | Out-Null
    foreach ($r in $items) {
      $line = ('  {0}  {1,-26} {2,12} tok  ¥{3}' -f [string]$r.date, (Friendly-Model ([string]$r.model)), ([long]$r.tokens).ToString('N0'), ([double]$r.cost).ToString('0.00'))
      $list.Items.Add($line) | Out-Null
    }
  }
}

$search.Add_TextChanged({ Refresh-View })
Refresh-View

if ($Test) {
  $t = New-Object System.Windows.Threading.DispatcherTimer; $t.Interval = [TimeSpan]::FromSeconds(2)
  $t.Add_Tick({ $t.Stop(); $win.Close() }); $t.Start()
}
$win.ShowDialog() | Out-Null

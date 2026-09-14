# DSH whale balance desktop widget - native WPF, standalone (no DSH, no Chromium)
param([switch]$Test, [switch]$Render, [string]$Out)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try { [System.Windows.Media.RenderOptions]::ProcessRenderMode = [System.Windows.Interop.RenderMode]::SoftwareOnly } catch {}

$ErrorActionPreference = 'Stop'
$AppDir     = Split-Path -Parent $MyInvocation.MyCommand.Definition
$AssetsDir  = Join-Path $AppDir 'assets'
$ConfigPath = Join-Path $AppDir 'config.json'
$SizePath   = Join-Path $AppDir '.dshw-size.json'
$UsagePath  = Join-Path $AppDir '.dshw-usage.json'
$PosPath    = Join-Path $AppDir '.dshw-pos.json'
$LogPath    = Join-Path $AppDir 'run.log'

function Write-Log([string]$m) {
  try { Add-Content -Path $LogPath -Value ((Get-Date).ToString('s') + ' ' + $m) -Encoding UTF8 } catch {}
}

$script:ApiKey = ''
$script:PlatformToken = ''
try {
  $cfgJson = Get-Content $ConfigPath -Raw | ConvertFrom-Json
  $script:ApiKey = $cfgJson.DEEPSEEK_API_KEY
  $script:PlatformToken = $cfgJson.DEEPSEEK_PLATFORM_TOKEN
} catch {}

$script:State = [ordered]@{
  totalBalance = $null
  currency     = 'CNY'
  todayUsage   = $null
  isPeak       = $false
  error        = $null
  scale        = 1.6
  sound        = $true
  vol          = 0.9
  soundSet     = 'duck'
  bubbleOn     = $true
  peakMode     = 'default'
  usageMode    = 'ledger'
  locked       = $false
}

function Read-SizeConfig {
  try {
    $p = Get-Content $SizePath -Raw | ConvertFrom-Json
    if ($null -ne $p.scale) {
      $script:State.scale = [double]$p.scale
      $script:State.sound = ($p.sound -ne $false)
      if ($null -ne $p.vol) { $script:State.vol = [double]$p.vol }
      if ($p.soundSet) { $script:State.soundSet = [string]$p.soundSet }
      if ($null -ne $p.bubbleOn) { $script:State.bubbleOn = ($p.bubbleOn -ne $false) }
      if ($p.peakMode) { $script:State.peakMode = [string]$p.peakMode }
      if ($p.usageMode) { $script:State.usageMode = [string]$p.usageMode }
      if ($null -ne $p.locked) { $script:State.locked = ($p.locked -eq $true) }
    }
  } catch {}
}

function Write-SizeConfig {
  $body = [ordered]@{
    scale     = [double]$script:State.scale
    sound     = [bool]$script:State.sound
    vol       = [double]$script:State.vol
    soundSet  = [string]$script:State.soundSet
    usageMode = [string]$script:State.usageMode
    peakMode  = [string]$script:State.peakMode
    bubbleOn  = [bool]$script:State.bubbleOn
    locked    = [bool]$script:State.locked
    updatedAt = (Get-Date).ToUniversalTime().ToString('o')
  }
  try { $body | ConvertTo-Json | Set-Content -Path $SizePath -Encoding UTF8 } catch {}
}

function Today-Key { return (Get-Date).ToString('yyyy-MM-dd') }

function Read-Ledger {
  try {
    $l = Get-Content $UsagePath -Raw | ConvertFrom-Json
    if ($l.date) { return $l }
  } catch {}
  return [pscustomobject]@{ date = (Today-Key); lastBalance = $null; lastCurrency = ''; todayUsage = 0; history = @{} }
}

function Write-Ledger($l) {
  try { $l | ConvertTo-Json -Depth 8 | Set-Content -Path $UsagePath -Encoding UTF8 } catch {}
}

function Record-Ledger([double]$bal, [string]$cur) {
  $t = Today-Key
  $l = Read-Ledger
  $prevCur = [string]$l.lastCurrency
  $curChanged = ($prevCur -ne '' -and $cur -ne '' -and $prevCur -ne $cur)
  if ($l.date -ne $t) {
    $h = @{}
    if ($l.history) { foreach ($pr in $l.history.PSObject.Properties) { $h[$pr.Name] = $pr.Value } }
    if ($l.date -and $null -ne $l.todayUsage) { $h[[string]$l.date] = [double]$l.todayUsage }
    $l.history = $h
    $l.date = $t; $l.lastBalance = $bal; $l.lastCurrency = $cur; $l.todayUsage = 0
  } elseif ($curChanged) {
    $l.lastBalance = $bal; $l.lastCurrency = $cur
  } else {
    $prev = $l.lastBalance
    if ($null -ne $prev -and $bal -lt [double]$prev) {
      $l.todayUsage = [double]$l.todayUsage + ([double]$prev - $bal)
    }
    $l.lastBalance = $bal; $l.lastCurrency = $cur
  }
  Write-Ledger $l
  return $l
}

function Is-PeakTime([datetime]$t) {
  if ($t.DayOfWeek -eq [System.DayOfWeek]::Saturday -or $t.DayOfWeek -eq [System.DayOfWeek]::Sunday) { return $false }
  $h = $t.Hour
  return (($h -ge 9 -and $h -lt 12) -or ($h -ge 14 -and $h -lt 18))
}

# ---- 「实时·令牌」模式：平台用量接口 + 峰谷定价换算 ----
# DeepSeek CNY 价格（元/百万 token）：[空闲价, 高峰价]。官方调价时改这里。
$script:Pricing = @{
  'deepseek-v4-flash-vision-exp' = @{ hit = @(0.05, 0.1);  miss = @(1.5, 3.0);  out = @(4.5, 9.0) }
  'deepseek-v4-flash'            = @{ hit = @(0.05, 0.1);  miss = @(1.5, 3.0);  out = @(4.5, 9.0) }
  'deepseek-v4-pro'              = @{ hit = @(0.15, 0.3);  miss = @(4.5, 9.0);  out = @(13.5, 27.0) }
  'deepseek-chat'                = @{ hit = @(0.05, 0.1);  miss = @(1.5, 3.0);  out = @(4.5, 9.0) }
  'deepseek-reasoner'            = @{ hit = @(0.05, 0.1);  miss = @(1.5, 3.0);  out = @(4.5, 9.0) }
}
function Get-Price([string]$model) {
  $m = ([string]$model).ToLower()
  foreach ($k in $script:Pricing.Keys) { if ($m.IndexOf($k) -ge 0) { return $script:Pricing[$k] } }
  return $script:Pricing['deepseek-chat']
}
# 北京时间 2026-08-23 00:00 之后，周末全天按谷价
$script:WeekendValleyFromSec = [long]((([datetime]::new(2026, 8, 22, 16, 0, 0, [DateTimeKind]::Utc)) - ([datetime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc))).TotalSeconds)
function Test-PeakSec([long]$sec) {
  if ($sec -le 0) { return $false }
  $bj = [datetime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc).AddSeconds($sec + 8 * 3600)
  if ($sec -ge $script:WeekendValleyFromSec) {
    if ($bj.DayOfWeek -eq [System.DayOfWeek]::Saturday -or $bj.DayOfWeek -eq [System.DayOfWeek]::Sunday) { return $false }
  }
  $h = $bj.Hour
  return (($h -ge 9 -and $h -lt 12) -or ($h -ge 14 -and $h -lt 18))
}
function Convert-Usage([string]$text) {
  # 平台接口结构：data.biz_data.series[] = { model, buckets[{ time, usage{ PROMPT_CACHE_HIT_TOKEN / PROMPT_CACHE_MISS_TOKEN / RESPONSE_TOKEN } }] }
  try { $j = $text | ConvertFrom-Json } catch { return $null }
  $d = $j
  if ($j.data -and $j.data.biz_data -and $j.data.biz_data.series) { $d = $j.data.biz_data }
  elseif ($j.data -and $j.data.series) { $d = $j.data }
  $series = @($d.series)
  if ($series.Count -eq 0) { return $null }
  $cost = 0.0; $tokens = 0.0; $found = $false
  foreach ($s in $series) {
    if (-not $s) { continue }
    $p = Get-Price $s.model
    foreach ($b in @($s.buckets)) {
      $u = $b.usage
      if (-not $u) { continue }
      $hit = [double]$u.PROMPT_CACHE_HIT_TOKEN
      $miss = [double]$u.PROMPT_CACHE_MISS_TOKEN
      $out = [double]$u.RESPONSE_TOKEN
      if (($hit + $miss + $out) -eq 0) { continue }
      $found = $true
      $tokens += $hit + $miss + $out
      $pi = if (Test-PeakSec ([long]$b.time)) { 1 } else { 0 }
      $cost += ($hit / 1e6) * $p.hit[$pi] + ($miss / 1e6) * $p.miss[$pi] + ($out / 1e6) * $p.out[$pi]
    }
  }
  if (-not $found) { return $null }
  return @{ amount = $cost; tokens = $tokens }
}

function Parse-Balance([string]$text) {
  try { $j = $text | ConvertFrom-Json } catch { return @{ ok = $false; error = '余额接口返回不是合法 JSON' } }
  $infos = @($j.balance_infos)
  if ($infos.Count -eq 0) { return @{ ok = $false; error = '余额接口返回结构异常' } }
  $pick = $infos | Where-Object { $_.currency -eq 'CNY' -and [double]$_.total_balance -gt 0 } | Select-Object -First 1
  if (-not $pick) { $pick = $infos | Where-Object { [double]$_.total_balance -gt 0 } | Select-Object -First 1 }
  if (-not $pick) { $pick = $infos | Where-Object { $_.currency -eq 'CNY' } | Select-Object -First 1 }
  if (-not $pick) { $pick = $infos[0] }
  return @{ ok = $true; totalBalance = [double]$pick.total_balance; currency = [string]$pick.currency }
}

function Invoke-BalanceRaw {
  try {
    $r = Invoke-WebRequest -Uri 'https://api.deepseek.com/user/balance' -Headers @{ Authorization = ('Bearer ' + $script:ApiKey) } -TimeoutSec 20 -UseBasicParsing
    if ($r.Content) { return [string]$r.Content }
  } catch {}
  try {
    $t = & curl.exe -s -H ('Authorization: Bearer ' + $script:ApiKey) 'https://api.deepseek.com/user/balance' 2>$null
    if ($t) { return ($t -join '') }
  } catch {}
  try {
    $node = (Get-Command node -ErrorAction SilentlyContinue).Source
    if (-not $node) { $node = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe' }
    if (Test-Path $node) {
      $helper = Join-Path $AppDir 'getbalance.js'
      if (Test-Path $helper) {
        $t = & $node $helper $ConfigPath 2>$null
        if ($t) { return ($t -join '') }
      }
    }
  } catch {}
  return $null
}

function Fetch-Balance {
  if (-not $script:ApiKey) { return @{ ok = $false; error = '未配置 DEEPSEEK_API_KEY' } }
  $raw = Invoke-BalanceRaw
  if (-not $raw) { return @{ ok = $false; error = '余额接口请求失败（网络不可达）' } }
  return (Parse-Balance $raw)
}

function Find-Node {
  $n = (Get-Command node -ErrorAction SilentlyContinue).Source
  if (-not $n) { $n = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe' }
  if ($n -and (Test-Path $n)) { return $n }
  return $null
}

# ---- async balance fetch: never block the UI thread ----
$script:fetchRs = $null
$script:fetchPS = $null
$script:fetchHandle = $null
$script:fetchBusy = $false
$script:bubbleAfterFetch = $false

function Start-BalanceFetch([bool]$showBubble) {
  if ($script:fetchBusy) { return }
  if (-not $script:fetchRs) {
    try {
      $script:fetchRs = [runspacefactory]::CreateRunspace()
      $script:fetchRs.ApartmentState = [System.Threading.ApartmentState]::MTA
      $script:fetchRs.Open()
    } catch { Write-Log ('runspace-error: ' + $_.Exception.Message); $script:fetchRs = $null; return }
  }
  $script:fetchBusy = $true
  $script:bubbleAfterFetch = $showBubble
  $sb = {
    param($key, $node, $helper, $cfg, $ptoken, $wantUsage, $uhelper)
    $raw = ''
    try {
      $r = Invoke-WebRequest -Uri 'https://api.deepseek.com/user/balance' -Headers @{ Authorization = ('Bearer ' + $key) } -TimeoutSec 20 -UseBasicParsing
      if ($r.Content) { $raw = [string]$r.Content }
    } catch {}
    if (-not $raw) {
      try { $t = & curl.exe -s -H ('Authorization: Bearer ' + $key) 'https://api.deepseek.com/user/balance' 2>$null; if ($t) { $raw = ($t -join '') } } catch {}
    }
    if (-not $raw -and $node -and (Test-Path $node) -and (Test-Path $helper)) {
      try { $t = & $node $helper $cfg 2>$null; if ($t) { $raw = ($t -join '') } } catch {}
    }
    $usage = ''
    if ($wantUsage -and $ptoken) {
      $now = Get-Date
      $tz = [int]([System.TimeZoneInfo]::Local.GetUtcOffset($now).TotalSeconds)
      $start = [long]((([datetime]::new($now.Year, $now.Month, $now.Day, 0, 0, 0, [DateTimeKind]::Local)).ToUniversalTime() - ([datetime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc))).TotalSeconds)
      $end = $start + 86400
      $url = 'https://platform.deepseek.com/api/v0/usage/by_api_key/amount?start=' + $start + '&end=' + $end + '&tz=' + $tz
      try {
        $r2 = Invoke-WebRequest -Uri $url -Headers @{ Authorization = ('Bearer ' + $ptoken) } -TimeoutSec 15 -UseBasicParsing
        if ($r2.Content) { $usage = [string]$r2.Content }
      } catch {}
      if (-not $usage) {
        try { $t = & curl.exe -s -H ('Authorization: Bearer ' + $ptoken) $url 2>$null; if ($t) { $usage = ($t -join '') } } catch {}
      }
      if (-not $usage -and $node -and $uhelper -and (Test-Path $node) -and (Test-Path $uhelper)) {
        try { $t = & $node $uhelper $cfg 2>$null; if ($t) { $usage = ($t -join '') } } catch {}
      }
    }
    return (@{ balance = $raw; usage = $usage } | ConvertTo-Json -Compress)
  }
  try {
    $script:fetchPS = [powershell]::Create()
    $script:fetchPS.Runspace = $script:fetchRs
    $wantUsage = ([string]$script:State.usageMode -eq 'token') -and (-not [string]::IsNullOrWhiteSpace([string]$script:PlatformToken))
    [void]$script:fetchPS.AddScript($sb).AddArgument($script:ApiKey).AddArgument((Find-Node)).AddArgument((Join-Path $AppDir 'getbalance.js')).AddArgument($ConfigPath).AddArgument([string]$script:PlatformToken).AddArgument($wantUsage).AddArgument((Join-Path $AppDir 'getusage.js'))
    $script:fetchHandle = $script:fetchPS.BeginInvoke()
    Write-Log 'fetch-started'
  } catch {
    $script:fetchBusy = $false
    Write-Log ('fetch-start-error: ' + $_.Exception.Message)
  }
}

function Refresh-Balance {
  $r = Fetch-Balance
  if (-not $r.ok) { $script:State.error = $r.error; return $false }
  $led = Record-Ledger ([double]$r.totalBalance) ([string]$r.currency)
  $script:State.totalBalance = [double]$r.totalBalance
  $script:State.currency = [string]$r.currency
  $script:State.todayUsage = [double]$led.todayUsage
  $script:State.isPeak = Is-PeakTime (Get-Date)
  $script:State.error = $null
  return $true
}

Read-SizeConfig
Write-Log 'script-started'

$mutexName = if ($Test -or $Render) { 'DSHWhaleWidget_SingleInstance_Test' } else { 'DSHWhaleWidget_SingleInstance' }
$script:mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $script:mutex.WaitOne(0)) { Write-Log 'already-running'; exit }

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        Width="360" Height="360" WindowStartupLocation="Manual">
  <Grid>
  <Grid.Resources>
    <Style TargetType="Slider">
      <Setter Property="Height" Value="20"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Slider">
            <Grid>
              <Border Height="4" CornerRadius="2" Background="#33203170" VerticalAlignment="Center"/>
              <Track x:Name="PART_Track" Orientation="Horizontal">
                <Track.Thumb>
                  <Thumb Width="12" Height="12">
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Ellipse Width="12" Height="12" Fill="#203170"/>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Border x:Name="Box" Width="16" Height="16" CornerRadius="4" BorderBrush="#66203170" BorderThickness="1" Background="White">
              <Path x:Name="Mark" Data="M3,7 L6,10 L12,3" Stroke="#203170" StrokeThickness="2" Visibility="Collapsed"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Mark" Property="Visibility" Value="Visible"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#203170"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="#14203170" BorderBrush="#66203170" BorderThickness="1" CornerRadius="6" Padding="8,4">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#28203170"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#203170"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Padding" Value="6,4"/>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Foreground" Value="#203170"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Height" Value="24"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton x:Name="Toggle" Focusable="False" ClickMode="Press"
                            IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border Background="#14203170" BorderBrush="#66203170" BorderThickness="1" CornerRadius="6"/>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter Margin="8,2,20,2" HorizontalAlignment="Left" VerticalAlignment="Center" IsHitTestVisible="False"
                                Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                TextBlock.Foreground="#203170"/>
              <Path HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,8,0" Data="M0,0 L4,4 L8,0" Stroke="#203170" StrokeThickness="1.5" IsHitTestVisible="False"/>
              <Popup x:Name="PART_Popup" AllowsTransparency="True" Focusable="False" IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" StaysOpen="False">
                <Border Background="White" BorderBrush="#66203170" BorderThickness="1" CornerRadius="6"
                        MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}">
                  <ItemsPresenter/>
                </Border>
              </Popup>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Grid.Resources>
  <Canvas x:Name="Stage" Width="360" Height="360" Background="Transparent">
    <Viewbox x:Name="BubbleHost" Canvas.Left="0" Canvas.Top="0" Width="248" Height="169" Visibility="Hidden" RenderTransformOrigin="0.5,0.5">
      <Viewbox.RenderTransform><ScaleTransform x:Name="BubbleHostScale" ScaleX="1" ScaleY="1"/></Viewbox.RenderTransform>
      <Canvas Width="1026" Height="700">
        <Path Fill="White" Stroke="#203170" StrokeThickness="16" StrokeLineJoin="Round"
              StrokeStartLineCap="Round" StrokeEndLineCap="Round"
              Data="M827,248 A373,232,0,1,0,81,246 A373,232,0,0,0,301,465 A57,32,10,0,0,413,484 A373,232,0,0,0,827,248 Z"/>
        <Ellipse Canvas.Left="314" Canvas.Top="535" Width="76" Height="52" Fill="White" Stroke="#203170" StrokeThickness="16"/>
        <Ellipse Canvas.Left="418" Canvas.Top="628" Width="50" Height="36" Fill="White" Stroke="#203170" StrokeThickness="16"/>
      </Canvas>
    </Viewbox>
    <Grid x:Name="BubbleText" Canvas.Left="22" Canvas.Top="4" Width="176" Height="112" Visibility="Hidden" RenderTransformOrigin="0.5,0.5">
      <Grid.RenderTransform><ScaleTransform x:Name="BubbleTextScale" ScaleX="1" ScaleY="1"/></Grid.RenderTransform>
      <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center" Width="168">
        <TextBlock x:Name="LabelText" Foreground="#536ba9" FontSize="14" FontWeight="SemiBold" HorizontalAlignment="Center" Text="DeepSeek 余额"/>
        <TextBlock x:Name="AmountText" Foreground="#536ba9" FontSize="30" FontWeight="Bold" HorizontalAlignment="Center" Margin="0,1,0,1" Text="--"/>
        <TextBlock x:Name="HintText" Foreground="#9fb0d9" FontSize="12" HorizontalAlignment="Center" TextWrapping="Wrap" TextAlignment="Center" MaxWidth="168" Text=""/>
      </StackPanel>
    </Grid>
    <Image x:Name="WhaleImg" Canvas.Left="210" Canvas.Top="210" Width="150" Height="150" Cursor="Hand" RenderTransformOrigin="0.5,1">
      <Image.RenderTransform><ScaleTransform x:Name="WhaleScale" ScaleX="1" ScaleY="1"/></Image.RenderTransform>
    </Image>
    <Button x:Name="MenuBtn" Canvas.Left="330" Canvas.Top="210" Width="26" Height="26" Opacity="0"
            FontSize="13" Content="≡" Background="#203170" Foreground="White" BorderThickness="0" Cursor="Hand"/>
    <TextBlock x:Name="LockBadge" Canvas.Left="332" Canvas.Top="240" FontSize="13" Text="🔒" Visibility="Collapsed"/>
  </Canvas>
  <Popup x:Name="MenuPopup" Placement="Left" StaysOpen="False" AllowsTransparency="True" PopupAnimation="Fade" VerticalOffset="0">
    <Border Background="#F2FFFFFF" BorderBrush="#59203170" BorderThickness="1" CornerRadius="10" Padding="12">
      <StackPanel Width="250">
        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
          <TextBlock Text="大小" Foreground="#203170" FontSize="12" Width="40" VerticalAlignment="Center"/>
          <Slider x:Name="ScaleSlider" Minimum="0.6" Maximum="2.5" TickFrequency="0.1" IsSnapToTickEnabled="True" Width="130" VerticalAlignment="Center"/>
          <TextBlock x:Name="ScaleValue" Text="1.4" Foreground="#203170" FontSize="12" Width="50" TextAlignment="Right" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
          <TextBlock Text="音效" Foreground="#203170" FontSize="12" Width="40" VerticalAlignment="Center"/>
          <ComboBox x:Name="SoundCombo" Width="170" FontSize="12">
            <ComboBoxItem Content="小黄鸭" Tag="duck"/>
            <ComboBoxItem Content="音效1" Tag="fx1"/>
          </ComboBox>
        </StackPanel>
        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
          <TextBlock Text="音量" Foreground="#203170" FontSize="12" Width="40" VerticalAlignment="Center"/>
          <Slider x:Name="VolSlider" Minimum="0" Maximum="1" TickFrequency="0.05" IsSnapToTickEnabled="True" Width="130" VerticalAlignment="Center"/>
          <TextBlock x:Name="VolValue" Text="90%" Foreground="#203170" FontSize="12" Width="50" TextAlignment="Right" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
          <TextBlock Text="用量" Foreground="#203170" FontSize="12" Width="40" VerticalAlignment="Center"/>
          <ComboBox x:Name="UsageCombo" Width="180" FontSize="12">
            <ComboBoxItem Content="小鲸鱼记账 (推荐)" Tag="ledger"/>
            <ComboBoxItem Content="实时·令牌" Tag="token"/>
          </ComboBox>
        </StackPanel>
        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
          <TextBlock Text="峰谷" Foreground="#203170" FontSize="12" Width="40" VerticalAlignment="Center"/>
          <ComboBox x:Name="PeakCombo" Width="150" FontSize="12">
            <ComboBoxItem Content="默认" Tag="default"/>
            <ComboBoxItem Content="梁文峰谷" Tag="liangwen"/>
            <ComboBoxItem Content="!?强强?!" Tag="qiangqiang"/>
          </ComboBox>
        </StackPanel>
        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
          <TextBlock Text="气泡" Foreground="#203170" FontSize="12" Width="40" VerticalAlignment="Center"/>
          <CheckBox x:Name="BubbleCheck" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
          <TextBlock Text="锁定" Foreground="#203170" FontSize="12" Width="40" VerticalAlignment="Center"/>
          <CheckBox x:Name="LockCheck" VerticalAlignment="Center"/>
        </StackPanel>
        <Button x:Name="ExitBtn" Content="退出挂件" Margin="0,4,0,0" Padding="6,4" FontSize="12"/>
      </StackPanel>
    </Border>
  </Popup>
  </Grid>
</Window>
'@

$win = [System.Windows.Markup.XamlReader]::Parse($xaml)
$whale = $win.FindName('WhaleImg')
$bubbleHost = $win.FindName('BubbleHost')
$bubbleText = $win.FindName('BubbleText')
$labelText = $win.FindName('LabelText')
$amountText = $win.FindName('AmountText')
$hintText = $win.FindName('HintText')
$menuBtn = $win.FindName('MenuBtn')
$bubbleHostScale = $win.FindName('BubbleHostScale')
$bubbleTextScale = $win.FindName('BubbleTextScale')
$whaleScale = $win.FindName('WhaleScale')
$menuPopup = $win.FindName('MenuPopup')
$scaleSlider = $win.FindName('ScaleSlider')
$scaleValue = $win.FindName('ScaleValue')
$soundCombo = $win.FindName('SoundCombo')
$volSlider = $win.FindName('VolSlider')
$volValue = $win.FindName('VolValue')
$usageCombo = $win.FindName('UsageCombo')
$peakCombo = $win.FindName('PeakCombo')
$bubbleCheck = $win.FindName('BubbleCheck')
$lockCheck = $win.FindName('LockCheck')
$lockBadge = $win.FindName('LockBadge')
$exitBtn = $win.FindName('ExitBtn')

try {
  $imgPath = Join-Path $AssetsDir 'DSniang1.png'
  $bi = New-Object System.Windows.Media.Imaging.BitmapImage
  $fs = [System.IO.File]::OpenRead($imgPath)
  $bi.BeginInit()
  $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
  $bi.StreamSource = $fs
  $bi.EndInit()
  $fs.Close()
  $whale.Source = $bi
  Write-Log ('image ' + $bi.PixelWidth + 'x' + $bi.PixelHeight)
} catch { Write-Log ('image-error: ' + $_.Exception.Message) }

function To-FileUri([string]$p) { return [System.Uri]::new('file:///' + ($p -replace '\\', '/')) }

$script:pressPlayer = New-Object System.Windows.Media.MediaPlayer
$script:releasePlayer = New-Object System.Windows.Media.MediaPlayer
$script:pressPlayer.Add_MediaOpened({ Write-Log 'press-media-opened' })
$script:releasePlayer.Add_MediaOpened({ Write-Log 'release-media-opened' })
$script:pressPlayer.Add_MediaFailed({ param($s, $e) Write-Log ('press-media-failed: ' + $e.ErrorException.Message) })
$script:releasePlayer.Add_MediaFailed({ param($s, $e) Write-Log ('release-media-failed: ' + $e.ErrorException.Message) })
function Set-SoundSet([string]$set) {
  try {
    if ($set -eq 'fx1') {
      $script:pressPlayer.Open((To-FileUri (Join-Path $AssetsDir 'D1.mp3')))
      $script:releasePlayer.Open((To-FileUri (Join-Path $AssetsDir 'D2.mp3')))
    } else {
      $script:pressPlayer.Open((To-FileUri (Join-Path $AssetsDir 'Ya1.mp3')))
      $script:releasePlayer.Open((To-FileUri (Join-Path $AssetsDir 'Ya2.mp3')))
    }
  } catch { Write-Log ('sound-open-error: ' + $_.Exception.Message) }
}
$script:pressing = $false
$script:pressEnded = $false
$script:releasePlayed = $false

$script:pressPlayer.Add_MediaEnded({
  $script:pressEnded = $true
  if (-not $script:pressing -and -not $script:releasePlayed) { Play-Release }
})

function Play-Press {
  if (-not $script:State.sound) { return }
  try {
    $script:pressing = $true
    $script:pressEnded = $false
    $script:releasePlayed = $false
    try { $script:releasePlayer.Stop() } catch {}
    try { $script:releaseFallback.Stop() } catch {}
    $script:pressPlayer.Volume = [double]$script:State.vol
    $script:pressPlayer.Position = [TimeSpan]::Zero
    $script:pressPlayer.Play()
  } catch {}
}

function Play-Release {
  if (-not $script:State.sound) { return }
  if ($script:releasePlayed) { return }
  $script:releasePlayed = $true
  try {
    $script:releasePlayer.Volume = [double]$script:State.vol
    $script:releasePlayer.Position = [TimeSpan]::Zero
    $script:releasePlayer.Play()
  } catch {}
}

function Press-Up {
  $script:pressing = $false
  if ($script:pressEnded) { Play-Release }
  else { try { $script:releaseFallback.Stop(); $script:releaseFallback.Start() } catch {} }
}

$script:releaseFallback = New-Object System.Windows.Threading.DispatcherTimer
$script:releaseFallback.Interval = [TimeSpan]::FromMilliseconds(1300)
$script:releaseFallback.Add_Tick({ $script:releaseFallback.Stop(); Play-Release })
Set-SoundSet ([string]$script:State.soundSet)

$script:lines = @(
  '摸鱼中，别催~',
  'DeepSeek 余额在线营业中',
  '今天的 token 花得还好吗？',
  '努力赚钱，鲸鱼也很累',
  '余额充足，冲鸭！',
  '记得给挂件点个赞',
  '数据都是真的，放心看',
  '休息一下，喝口水吧',
  '哦鲸鲸'
)

function Fmt-Money($v) {
  if ($null -eq $v) { return '--' }
  return ('¥' + ([double]$v).ToString('0.00'))
}

function Update-BubbleText {
  if ($script:State.error) {
    $labelText.Text = 'DeepSeek 余额'
    $amountText.Text = '--'
    $hintText.Text = $script:State.error
    return
  }
  $offText = '空闲时段'
  $peakText = '高峰时段'
  if ($script:State.peakMode -eq 'liangwen') { $offText = '梁文谷'; $peakText = '梁文峰' }
  elseif ($script:State.peakMode -eq 'qiangqiang') { $offText = '!?谷谷?!'; $peakText = '!?峰峰?!' }
  $labelText.Text = 'DeepSeek 余额'
  $amountText.Text = (Fmt-Money $script:State.totalBalance)
  $parts = @()
  $parts += ('今日已用 ' + (Fmt-Money $script:State.todayUsage))
  if ($script:State.isPeak) { $parts += $peakText } else { $parts += $offText }
  $hintText.Text = ($parts -join '  ·  ')
}

function Anim-Pop($el, $st) {
  try {
    $fade = New-Object System.Windows.Media.Animation.DoubleAnimation -ArgumentList 0.0, 1.0, ([TimeSpan]::FromMilliseconds(200))
    $sx = New-Object System.Windows.Media.Animation.DoubleAnimation -ArgumentList 0.7, 1.0, ([TimeSpan]::FromMilliseconds(240))
    $sy = New-Object System.Windows.Media.Animation.DoubleAnimation -ArgumentList 0.7, 1.0, ([TimeSpan]::FromMilliseconds(240))
    $ease = New-Object System.Windows.Media.Animation.BackEase
    $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    $sx.EasingFunction = $ease
    $sy.EasingFunction = $ease
    $el.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
    $st.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $sx)
    $st.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $sy)
  } catch {}
}

function Whale-Press {
  try {
    $sx = New-Object System.Windows.Media.Animation.DoubleAnimation -ArgumentList 1.0, 0.9, ([TimeSpan]::FromMilliseconds(120))
    $sy = New-Object System.Windows.Media.Animation.DoubleAnimation -ArgumentList 1.0, 0.9, ([TimeSpan]::FromMilliseconds(120))
    $sx.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::HoldEnd
    $sy.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::HoldEnd
    $whaleScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $sx)
    $whaleScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $sy)
  } catch {}
}

function Whale-Release {
  try {
    $ease = New-Object System.Windows.Media.Animation.BackEase
    $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    $sx = New-Object System.Windows.Media.Animation.DoubleAnimation -ArgumentList 0.9, 1.0, ([TimeSpan]::FromMilliseconds(280))
    $sy = New-Object System.Windows.Media.Animation.DoubleAnimation -ArgumentList 0.9, 1.0, ([TimeSpan]::FromMilliseconds(280))
    $sx.EasingFunction = $ease
    $sy.EasingFunction = $ease
    $sx.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::Stop
    $sy.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::Stop
    $whaleScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $sx)
    $whaleScale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $sy)
  } catch {}
}

function Show-Bubble([string]$mode) {
  Update-BubbleText
  if ($mode -eq 'line') {
    $line = $script:lines | Get-Random
    $labelText.Text = $line
    $amountText.Text = (Fmt-Money $script:State.totalBalance)
    $hintText.Text = ''
  }
  $script:bubbleMode = $mode
  $bubbleHost.Visibility = 'Visible'
  $bubbleText.Visibility = 'Visible'
  $script:bubbleUntil = (Get-Date).AddSeconds(5)
  Anim-Pop $bubbleHost $bubbleHostScale
  Anim-Pop $bubbleText $bubbleTextScale
}

function Hide-Bubble {
  if ($bubbleHost.Visibility -ne 'Visible') { return }
  try {
    $f1 = New-Object System.Windows.Media.Animation.DoubleAnimation -ArgumentList 1.0, 0.0, ([TimeSpan]::FromMilliseconds(160))
    $f1.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::Stop
    $f1.Add_Completed({ $bubbleHost.Visibility = 'Hidden'; $bubbleText.Visibility = 'Hidden' })
    $f2 = New-Object System.Windows.Media.Animation.DoubleAnimation -ArgumentList 1.0, 0.0, ([TimeSpan]::FromMilliseconds(160))
    $f2.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::Stop
    $bubbleHost.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $f1)
    $bubbleText.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $f2)
  } catch {
    $bubbleHost.Visibility = 'Hidden'
    $bubbleText.Visibility = 'Hidden'
  }
}

function Apply-Scale {
  $s = [double]$script:State.scale
  $size = [math]::Round(150 * $s)
  $whale.Width = $size
  $whale.Height = $size
  [System.Windows.Controls.Canvas]::SetLeft($whale, 360 - $size)
  [System.Windows.Controls.Canvas]::SetTop($whale, 360 - $size)
  [System.Windows.Controls.Canvas]::SetLeft($menuBtn, 360 - 30)
  [System.Windows.Controls.Canvas]::SetTop($menuBtn, 360 - $size + 10)
  [System.Windows.Controls.Canvas]::SetLeft($lockBadge, 360 - 30)
  [System.Windows.Controls.Canvas]::SetTop($lockBadge, 360 - $size + 40)
  if ($script:State.locked) { $lockBadge.Visibility = 'Visible' } else { $lockBadge.Visibility = 'Collapsed' }
  if ($script:State.locked) { $whale.Cursor = [System.Windows.Input.Cursors]::Arrow } else { $whale.Cursor = [System.Windows.Input.Cursors]::Hand }
}

Apply-Scale

function Save-Position {
  try { ([ordered]@{ left = [double]$win.Left; top = [double]$win.Top }) | ConvertTo-Json | Set-Content -Path $PosPath -Encoding UTF8 } catch {}
}

function Restore-Position {
  $wa = [System.Windows.SystemParameters]::WorkArea
  $left = $wa.Right - $win.Width - 8
  $top = $wa.Bottom - $win.Height - 8
  try {
    $p = Get-Content $PosPath -Raw | ConvertFrom-Json
    if ($null -ne $p.left -and $null -ne $p.top) { $left = [double]$p.left; $top = [double]$p.top }
  } catch {}
  if ($left -lt $wa.Left) { $left = $wa.Left }
  if ($top -lt $wa.Top) { $top = $wa.Top }
  if ($left + $win.Width -gt $wa.Right) { $left = $wa.Right - $win.Width }
  if ($top + $win.Height -gt $wa.Bottom) { $top = $wa.Bottom - $win.Height }
  $win.Left = $left
  $win.Top = $top
}

$script:dragging = $false
$script:moved = $false
$script:lastCursor = [System.Drawing.Point]::new(0, 0)

function Get-DpiScale {
  try {
    $d = [System.Windows.Media.VisualTreeHelper]::GetDpi($win)
    return @([double]$d.DpiScaleX, [double]$d.DpiScaleY)
  } catch { return @(1.0, 1.0) }
}

$whale.Add_MouseLeftButtonDown({
  $script:dragging = $true
  $script:moved = $false
  $script:lastCursor = [System.Windows.Forms.Cursor]::Position
  $whale.CaptureMouse()
  Play-Press
  Whale-Press
})

$whale.Add_MouseMove({
  if ($script:dragging -and -not $script:State.locked) {
    $cp = [System.Windows.Forms.Cursor]::Position
    $ds = Get-DpiScale
    $dx = ($cp.X - $script:lastCursor.X) * 96.0 / $ds[0]
    $dy = ($cp.Y - $script:lastCursor.Y) * 96.0 / $ds[1]
    if (-not $ds[0] -or [double]::IsNaN($dx) -or [double]::IsInfinity($dx)) { $dx = 0 }
    if (-not $ds[1] -or [double]::IsNaN($dy) -or [double]::IsInfinity($dy)) { $dy = 0 }
    if ([math]::Abs($dx) -gt 3 -or [math]::Abs($dy) -gt 3) { $script:moved = $true }
    $wa = [System.Windows.SystemParameters]::WorkArea
    $nl = [math]::Max($wa.Left, [math]::Min($win.Left + $dx, $wa.Right - $win.Width))
    $nt = [math]::Max($wa.Top, [math]::Min($win.Top + $dy, $wa.Bottom - $win.Height))
    $win.Left = $nl
    $win.Top = $nt
    $script:lastCursor = $cp
  }
})

$whale.Add_MouseLeftButtonUp({
  if ($script:dragging) {
    $script:dragging = $false
    $whale.ReleaseMouseCapture()
    Press-Up
    Whale-Release
    if ($script:moved -and -not $script:State.locked) { Save-Position } else { Show-Bubble 'balance'; Start-BalanceFetch $true }
  }
})

$bubbleText.Cursor = 'Hand'
$bubbleText.Add_MouseLeftButtonDown({ Show-Bubble 'line' })

$whale.Add_MouseEnter({ $menuBtn.Opacity = 1 })
$menuBtn.Add_MouseEnter({ $menuBtn.Opacity = 1 })

$script:menuHideAt = $null
$script:menuHoverTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:menuHoverTimer.Interval = [TimeSpan]::FromMilliseconds(180)
$script:menuHoverTimer.Add_Tick({
  $over = $whale.IsMouseOver -or $menuBtn.IsMouseOver -or $menuPopup.IsOpen
  if ($over) { $script:menuHideAt = $null; $menuBtn.Opacity = 1; return }
  if (-not $script:menuHideAt) { $script:menuHideAt = (Get-Date).AddMilliseconds(450) }
  if ((Get-Date) -gt $script:menuHideAt) { $menuBtn.Opacity = 0 }
})
$script:menuHoverTimer.Start()

$script:suppress = $false

function Sync-MenuControls {
  $script:suppress = $true
  try {
    $scaleSlider.Value = [double]$script:State.scale
    $scaleValue.Text = ([double]$script:State.scale).ToString('0.0')
    $volSlider.Value = [double]$script:State.vol
    $volValue.Text = ([int]([double]$script:State.vol * 100)).ToString() + '%'
    $bubbleCheck.IsChecked = [bool]$script:State.bubbleOn
    $lockCheck.IsChecked = [bool]$script:State.locked
    foreach ($it in $soundCombo.Items) { if ([string]$it.Tag -eq [string]$script:State.soundSet) { $soundCombo.SelectedItem = $it } }
    foreach ($it in $usageCombo.Items) { if ([string]$it.Tag -eq [string]$script:State.usageMode) { $usageCombo.SelectedItem = $it } }
    foreach ($it in $peakCombo.Items) { if ([string]$it.Tag -eq [string]$script:State.peakMode) { $peakCombo.SelectedItem = $it } }
  } catch { Write-Log ('sync-menu-error: ' + $_.Exception.Message) } finally { $script:suppress = $false }
}

$scaleSlider.Add_ValueChanged({
  if ($script:suppress) { return }
  $script:State.scale = [math]::Round([double]$scaleSlider.Value, 1)
  $scaleValue.Text = ([double]$script:State.scale).ToString('0.0')
  Apply-Scale
  Write-SizeConfig
})
$soundCombo.Add_SelectionChanged({
  if ($script:suppress) { return }
  $tag = [string]$soundCombo.SelectedItem.Tag
  if ($tag) { $script:State.soundSet = $tag; Set-SoundSet $tag; Write-SizeConfig; Play-Press }
})
$volSlider.Add_ValueChanged({
  if ($script:suppress) { return }
  $script:State.vol = [double]$volSlider.Value
  $volValue.Text = ([int]($script:State.vol * 100)).ToString() + '%'
  Write-SizeConfig
})
$usageCombo.Add_SelectionChanged({
  if ($script:suppress) { return }
  $tag = [string]$usageCombo.SelectedItem.Tag
  if ($tag) { $script:State.usageMode = $tag; Write-SizeConfig; Start-BalanceFetch $true }
})
$peakCombo.Add_SelectionChanged({
  if ($script:suppress) { return }
  $tag = [string]$peakCombo.SelectedItem.Tag
  if ($tag) { $script:State.peakMode = $tag; Write-SizeConfig; Show-Bubble 'balance' }
})
$bubbleCheck.Add_Click({
  if ($script:suppress) { return }
  $script:State.bubbleOn = [bool]$bubbleCheck.IsChecked
  Write-SizeConfig
})
$lockCheck.Add_Click({
  if ($script:suppress) { return }
  $script:State.locked = [bool]$lockCheck.IsChecked
  Write-SizeConfig
  Show-Bubble 'balance'
  if ($script:State.locked) { $hintText.Text = '位置已锁定，拖动无效' } else { $hintText.Text = '位置已解锁，可自由拖动' }
  if ($script:State.locked) { $lockBadge.Visibility = 'Visible' } else { $lockBadge.Visibility = 'Collapsed' }
  if ($script:State.locked) { $whale.Cursor = [System.Windows.Input.Cursors]::Arrow } else { $whale.Cursor = [System.Windows.Input.Cursors]::Hand }
})
$exitBtn.Add_Click({ $win.Close() })

function Open-Menu {
  Sync-MenuControls
  $menuPopup.PlacementTarget = $menuBtn
  $menuPopup.IsOpen = $true
}

$menuBtn.Add_Click({ Open-Menu })

$script:bubbleUntil = Get-Date
$script:bubbleMode = ''
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
  if ((Get-Date) -gt $script:bubbleUntil) { Hide-Bubble }
})
$timer.Start()

$refreshTimer = New-Object System.Windows.Threading.DispatcherTimer
$refreshTimer.Interval = [TimeSpan]::FromSeconds(60)
$refreshTimer.Add_Tick({ Start-BalanceFetch $false })
$refreshTimer.Start()

$script:fetchTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:fetchTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$script:fetchTimer.Add_Tick({
  if (-not $script:fetchBusy -or -not $script:fetchHandle) { return }
  if (-not $script:fetchHandle.IsCompleted) { return }
  $raw = ''
  $rawUsage = ''
  try {
    $out = $script:fetchPS.EndInvoke($script:fetchHandle)
    if ($out -and $out.Count -gt 0) {
      $envelope = [string]$out[$out.Count - 1]
      try {
        $pe = $envelope | ConvertFrom-Json
        if ($null -ne $pe.balance) { $raw = [string]$pe.balance; $rawUsage = [string]$pe.usage }
        else { $raw = $envelope }
      } catch { $raw = $envelope }
    }
  } catch { Write-Log ('fetch-end-error: ' + $_.Exception.Message) }
  try { $script:fetchPS.Dispose() } catch {}
  $script:fetchPS = $null
  $script:fetchHandle = $null
  $script:fetchBusy = $false
  if ($script:ApiKey -and $raw) {
    $r = Parse-Balance $raw
    if ($r.ok) {
      $led = Record-Ledger ([double]$r.totalBalance) ([string]$r.currency)
      $script:State.totalBalance = [double]$r.totalBalance
      $script:State.currency = [string]$r.currency
      $script:State.todayUsage = [double]$led.todayUsage
      $script:State.isPeak = Is-PeakTime (Get-Date)
      $script:State.error = $null
      Write-Log ('balance=' + $script:State.totalBalance)
      # 「实时·令牌」模式：用平台用量接口换算（失败则保留记账值）
      if (([string]$script:State.usageMode -eq 'token') -and $rawUsage) {
        $u = Convert-Usage $rawUsage
        if ($u) {
          $script:State.todayUsage = [double]$u.amount
          Write-Log ('usage-token=' + $script:State.todayUsage + ' tokens=' + $u.tokens)
        } else {
          Write-Log 'usage-token-failed(回落记账)'
        }
      }
    } else {
      $script:State.error = $r.error
      Write-Log ('balance-parse-error: ' + $r.error)
    }
  } elseif (-not $script:ApiKey) {
    $script:State.error = '未配置 DEEPSEEK_API_KEY'
  } else {
    $script:State.error = '余额接口请求失败（网络不可达）'
    Write-Log 'balance-fetch-empty'
  }
  if ($script:bubbleAfterFetch) {
    if ($bubbleHost.Visibility -eq 'Visible' -and $script:bubbleMode -eq 'balance') {
      Update-BubbleText
      $script:bubbleUntil = (Get-Date).AddSeconds(5)
    } else {
      Show-Bubble 'balance'
    }
  }
})
$script:fetchTimer.Start()

$win.Add_Loaded({
  Restore-Position
  Apply-Scale
  Write-Log ('window ' + [int]$win.Left + ',' + [int]$win.Top + ' ' + [int]$win.Width + 'x' + [int]$win.Height + ' topmost=' + $win.Topmost + ' scale=' + $script:State.scale)
  Write-Log 'window-loaded'
  Show-Bubble 'balance'
  if ($Render) {
    $script:renderTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:renderTimer.Interval = [TimeSpan]::FromMilliseconds(900)
    $script:renderTimer.Add_Tick({
      $script:renderTimer.Stop()
      try {
        $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(360, 360, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32))
        $rtb.Render($win)
        $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
        $p = if ($Out) { $Out } else { Join-Path $AppDir 'render.png' }
        $fs = [System.IO.File]::Create($p)
        $enc.Save($fs)
        $fs.Close()
        Write-Log ('rendered ' + $p)
        try {
          $b = $menuPopup.Child
          $b.Measure([System.Windows.Size]::new(1000, 1000))
          $wpx = [int][math]::Ceiling($b.DesiredSize.Width)
          $hpx = [int][math]::Ceiling($b.DesiredSize.Height)
          $b.Arrange([System.Windows.Rect]::new(0, 0, $wpx, $hpx))
          $b.UpdateLayout()
          $rtb2 = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($wpx, $hpx, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32))
          $rtb2.Render($b)
          $e2 = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
          $e2.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb2))
          $p2 = Join-Path $AppDir 'menu.png'
          $fs2 = [System.IO.File]::Create($p2)
          $e2.Save($fs2)
          $fs2.Close()
          Write-Log ('rendered menu ' + $wpx + 'x' + $hpx)
        } catch { Write-Log ('menu-render-error: ' + $_.Exception.Message) }
      } catch { Write-Log ('render-error: ' + $_.Exception.Message) }
      $win.Close()
    })
    $script:renderTimer.Start()
  }
})

if ($Test) {
  $kickTimer = New-Object System.Windows.Threading.DispatcherTimer
  $kickTimer.Interval = [TimeSpan]::FromSeconds(2)
  $kickTimer.Add_Tick({ $kickTimer.Stop(); Write-Log 'test-kick-fetch'; Start-BalanceFetch $false })
  $kickTimer.Start()
  $closeTimer = New-Object System.Windows.Threading.DispatcherTimer
  $closeTimer.Interval = [TimeSpan]::FromSeconds(7)
  $closeTimer.Add_Tick({ Write-Log 'test-mode-closing'; $win.Close() })
  $closeTimer.Start()
}

try {
  Refresh-Balance | Out-Null
  Write-Log ('balance=' + [string]$script:State.totalBalance + ' err=' + [string]$script:State.error)
} catch { Write-Log ('refresh-error: ' + $_.Exception.Message) }

Write-Log 'showing-window'
$win.ShowDialog() | Out-Null
Write-Log 'window-closed'

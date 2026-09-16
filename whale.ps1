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
  $script:PlatformToken = [string]$cfgJson.DEEPSEEK_PLATFORM_TOKEN
  # 允许配置里带不带 "Bearer " 前缀（下面拼请求头时会自己加前缀）
  if ($script:PlatformToken) {
    $script:PlatformToken = $script:PlatformToken.Trim()
    if ($script:PlatformToken -imatch '^Bearer\s+(.+)$') { $script:PlatformToken = $Matches[1].Trim() }
  }
} catch {}

$script:State = [ordered]@{
  totalBalance = $null
  currency     = 'CNY'
  todayUsage   = $null
  isPeak       = $false
  error        = $null
  codex        = $null
  scale        = 1.6
  sound        = $true
  vol          = 0.9
  soundSet     = 'duck'
  bubbleOn     = $true
  peakMode     = 'default'
  usageMode    = 'ledger'
  locked       = $false
  rolePath     = ''
  customSoundOn = $false
  customPress  = ''
  customRelease = ''
  endSound     = ''
  snapOn       = $true
  hideMenuBtn  = $false
  balanceAlert = 0.0
  dailyBudget  = 0.0
  perTurnOn    = $false
  perTurnSeconds = 6
  perTurnTemplate = '本轮 {cost} · {tokens} tokens'
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
      if ($null -ne $p.rolePath) { $script:State.rolePath = [string]$p.rolePath }
      if ($null -ne $p.customSoundOn) { $script:State.customSoundOn = ($p.customSoundOn -eq $true) }
      if ($null -ne $p.customPress) { $script:State.customPress = [string]$p.customPress }
      if ($null -ne $p.customRelease) { $script:State.customRelease = [string]$p.customRelease }
      if ($null -ne $p.endSound) { $script:State.endSound = [string]$p.endSound }
      if ($null -ne $p.snapOn) { $script:State.snapOn = ($p.snapOn -ne $false) }
      if ($null -ne $p.hideMenuBtn) { $script:State.hideMenuBtn = ($p.hideMenuBtn -eq $true) }
      if ($null -ne $p.balanceAlert) { $script:State.balanceAlert = [double]$p.balanceAlert }
      if ($null -ne $p.dailyBudget) { $script:State.dailyBudget = [double]$p.dailyBudget }
      if ($null -ne $p.perTurnOn) { $script:State.perTurnOn = ($p.perTurnOn -eq $true) }
      if ($null -ne $p.perTurnSeconds) { $script:State.perTurnSeconds = [int]$p.perTurnSeconds }
      if ($null -ne $p.perTurnTemplate) { $script:State.perTurnTemplate = [string]$p.perTurnTemplate }
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
    rolePath  = [string]$script:State.rolePath
    customSoundOn = [bool]$script:State.customSoundOn
    customPress  = [string]$script:State.customPress
    customRelease = [string]$script:State.customRelease
    endSound  = [string]$script:State.endSound
    snapOn    = [bool]$script:State.snapOn
    hideMenuBtn = [bool]$script:State.hideMenuBtn
    balanceAlert = [double]$script:State.balanceAlert
    dailyBudget  = [double]$script:State.dailyBudget
    perTurnOn    = [bool]$script:State.perTurnOn
    perTurnSeconds = [int]$script:State.perTurnSeconds
    perTurnTemplate = [string]$script:State.perTurnTemplate
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

# 距下一次「峰/谷切换」还有多久（与原版挂件的峰谷倒计时同步）
function Get-PeakCountdown([datetime]$t) {
  $isPeak = Is-PeakTime $t
  $next = $null
  $isWeekend = ($t.DayOfWeek -eq [System.DayOfWeek]::Saturday -or $t.DayOfWeek -eq [System.DayOfWeek]::Sunday)
  if ($isWeekend) {
    $d = $t.Date
    do { $d = $d.AddDays(1) } while ($d.DayOfWeek -eq [System.DayOfWeek]::Saturday -or $d.DayOfWeek -eq [System.DayOfWeek]::Sunday)
    $next = $d.AddHours(9)
  } elseif ($t.Hour -lt 9) {
    $next = $t.Date.AddHours(9)
  } elseif ($t.Hour -lt 12) {
    $next = $t.Date.AddHours(12)
  } elseif ($t.Hour -lt 14) {
    $next = $t.Date.AddHours(14)
  } elseif ($t.Hour -lt 18) {
    $next = $t.Date.AddHours(18)
  } else {
    $d = $t.Date.AddDays(1)
    while ($d.DayOfWeek -eq [System.DayOfWeek]::Saturday -or $d.DayOfWeek -eq [System.DayOfWeek]::Sunday) { $d = $d.AddDays(1) }
    $next = $d.AddHours(9)
  }
  $mins = [int][Math]::Ceiling(($next - $t).TotalMinutes)
  if ($mins -lt 0) { $mins = 0 }
  $to = if ($isPeak) { '空闲' } else { '高峰' }
  return @{ min = $mins; to = $to }
}

# ---- 「实时·令牌」模式：平台用量接口 + 峰谷定价换算 ----
# DeepSeek CNY 价格（元/百万 token）：[空闲价, 高峰价]。官方调价时改这里。
# 2026-09 与官方定价页同步：V4.1-Flash 命中 0.02 / 未命中 1 / 输出 4（空闲价，高峰价翻倍）。
# V4-Pro 是 Flash 的 3 倍价；旧模型名 deepseek-v4-flash、deepseek-v4-flash-vision-exp
# 以及 chat / reasoner 都按 Flash 价计费。
$script:BasePrice = @{ hit = @(0.02, 0.04); miss = @(1.0, 2.0); out = @(4.0, 8.0) }
$script:ProPrice  = @{ hit = @(0.15, 0.30); miss = @(4.5, 9.0); out = @(13.5, 27.0) }
$script:ProKeys   = @('deepseek-v4-pro', 'deepseek-pro')
function Get-Price([string]$model) {
  $m = ([string]$model).ToLower()
  foreach ($k in $script:ProKeys) { if ($m.IndexOf($k) -ge 0) { return $script:ProPrice } }
  return $script:BasePrice
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

function Get-ApiListJson {
  try {
    $models = @()
    $apif = Join-Path $AppDir '.dshw-api.json'
    if (Test-Path -LiteralPath $apif) { $models = @(Get-Content -LiteralPath $apif -Raw | ConvertFrom-Json) }
    $creds = @{}
    $cf = Join-Path $AppDir '.dshw-credentials.json'
    if (Test-Path -LiteralPath $cf) {
      $c = Get-Content -LiteralPath $cf -Raw | ConvertFrom-Json
      foreach ($p in $c.PSObject.Properties) { $creds[$p.Name] = [string]$p.Value }
    }
    $out = @()
    foreach ($m in @($models)) {
      $out += [ordered]@{
        name = [string]$m.name; url = [string]$m.url; keyRef = [string]$m.keyRef
        key = [string]$creds[[string]$m.keyRef]; jsonPath = [string]$m.jsonPath; scale = [string]$m.scale
        auth = [string]$m.auth
        probeUrl = [string]$m.probeUrl; alert = [string]$m.alert; budget = [string]$m.budget
      }
    }
    return ($out | ConvertTo-Json -Compress)
  } catch { return '[]' }
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
    param($key, $node, $helper, $cfg, $ptoken, $wantUsage, $uhelper, $codexHelper, $apiList)
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
    # Codex 本地会话统计（读本机 ~/.codex，走 node 很快）
    $codex = ''
    if ($node -and (Test-Path $node) -and $codexHelper -and (Test-Path $codexHelper)) {
      try { $t = & $node $codexHelper 2>$null; if ($t) { $codex = ($t -join '') } } catch {}
    }
    $apis = @()
    if ($apiList) {
      try {
        foreach ($m in @($apiList | ConvertFrom-Json)) {
          $u = [string]$m.url; if (-not $u) { $u = [string]$m.probeUrl }
          $val = ''
          try {
            if ($u -and $m.key) {
              $authTpl = [string]$m.auth
              if (-not $authTpl) { $authTpl = 'Bearer {key}' }
              $authVal = $authTpl.Replace('{key}', [string]$m.key)
              $h = @{}
              if ($authVal.Trim() -ne '') { $h['Authorization'] = $authVal }
              $r = Invoke-WebRequest -Uri $u -Headers $h -TimeoutSec 15 -UseBasicParsing
              if ($r.Content) {
                $j = $r.Content | ConvertFrom-Json
                $v = $j
                $path = [string]$m.jsonPath
                if ($path) {
                  foreach ($seg in (($path -replace '\[(\d+)\]', '.$1') -split '\.')) {
                    if (-not $seg) { continue }
                    if ($seg -match '^\d+$') { $v = @($v)[[int]$seg] }
                    else { $pr = $v.PSObject.Properties[$seg]; if (-not $pr) { $v = $null; break }; $v = $pr.Value }
                  }
                }
                if ($null -ne $v) {
                  if ($m.scale) { $v = [double]$v * [double]$m.scale }
                  $val = [string]$v
                }
              }
            }
          } catch { $val = '' }
          $apis += @{ name = [string]$m.name; value = $val; alert = [string]$m.alert; budget = [string]$m.budget }
        }
      } catch {}
    }
    return (@{ balance = $raw; usage = $usage; codex = $codex; apis = ($apis | ConvertTo-Json -Compress) } | ConvertTo-Json -Compress)
  }
  try {
    $script:fetchPS = [powershell]::Create()
    $script:fetchPS.Runspace = $script:fetchRs
    $wantUsage = ([string]$script:State.usageMode -eq 'token') -and (-not [string]::IsNullOrWhiteSpace([string]$script:PlatformToken))
    [void]$script:fetchPS.AddScript($sb).AddArgument($script:ApiKey).AddArgument((Find-Node)).AddArgument((Join-Path $AppDir 'getbalance.js')).AddArgument($ConfigPath).AddArgument([string]$script:PlatformToken).AddArgument($wantUsage).AddArgument((Join-Path $AppDir 'getusage.js')).AddArgument((Join-Path $AppDir 'codexstats.js'))
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
      <StackPanel x:Name="DefaultBubblePanel" HorizontalAlignment="Center" VerticalAlignment="Center" Width="168">
        <TextBlock x:Name="LabelText" Foreground="#536ba9" FontSize="14" FontWeight="SemiBold" HorizontalAlignment="Center" Text="DeepSeek 余额"/>
        <TextBlock x:Name="AmountText" Foreground="#536ba9" FontSize="30" FontWeight="Bold" HorizontalAlignment="Center" Margin="0,1,0,1" Text="--" TextWrapping="Wrap" TextAlignment="Center" MaxWidth="170"/>
        <TextBlock x:Name="HintText" Foreground="#9fb0d9" FontSize="12" HorizontalAlignment="Center" TextWrapping="Wrap" TextAlignment="Center" MaxWidth="168" Text=""/>
      </StackPanel>
      <ScrollViewer x:Name="CustomBubblePanel" VerticalScrollBarVisibility="Auto" Visibility="Collapsed" VerticalAlignment="Center">
        <StackPanel x:Name="CustomBubbleStack"/>
      </ScrollViewer>
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
      <ScrollViewer MaxHeight="540" VerticalScrollBarVisibility="Auto">
        <StackPanel Width="250">
          <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
            <TextBlock Text="Codex" Foreground="#203170" FontSize="12" Width="40" VerticalAlignment="Center"/>
            <TextBlock x:Name="CodexValue" Text="统计中…" Foreground="#536ba9" FontSize="12" Width="190" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
            <TextBlock Text="大小" Foreground="#203170" FontSize="12" Width="40" VerticalAlignment="Center"/>
            <Slider x:Name="ScaleSlider" Minimum="0.6" Maximum="2.5" TickFrequency="0.1" IsSnapToTickEnabled="True" Width="130" VerticalAlignment="Center"/>
            <TextBlock x:Name="ScaleValue" Text="1.4" Foreground="#203170" FontSize="12" Width="50" TextAlignment="Right" VerticalAlignment="Center"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
            <TextBlock Text="音效" Foreground="#203170" FontSize="12" Width="40" VerticalAlignment="Center"/>
            <ComboBox x:Name="SoundCombo" Width="120" FontSize="12">
              <ComboBoxItem Content="小黄鸭" Tag="duck"/>
              <ComboBoxItem Content="音效1" Tag="fx1"/>
              <ComboBoxItem Content="自定义" Tag="custom"/>
            </ComboBox>
            <Button x:Name="CustomSoundBtn" Content="选音效…" Width="50" FontSize="11" Padding="3,2" Margin="4,0,0,0"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
            <CheckBox x:Name="SoundCheck" Content="音效开关" Width="90" VerticalAlignment="Center"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
            <TextBlock Text="音量" Foreground="#203170" FontSize="12" Width="40" VerticalAlignment="Center"/>
            <Slider x:Name="VolSlider" Minimum="0" Maximum="1" TickFrequency="0.05" IsSnapToTickEnabled="True" Width="130" VerticalAlignment="Center"/>
            <TextBlock x:Name="VolValue" Text="90%" Foreground="#203170" FontSize="12" Width="50" TextAlignment="Right" VerticalAlignment="Center"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
            <TextBlock Text="任务结束音" Foreground="#203170" FontSize="12" Width="60" VerticalAlignment="Center"/>
            <ComboBox x:Name="EndSoundCombo" Width="170" FontSize="12">
              <ComboBoxItem Content="关闭" Tag=""/>
              <ComboBoxItem Content="Minecraft·经验球" Tag="orb"/>
              <ComboBoxItem Content="A" Tag="a"/>
              <ComboBoxItem Content="自定义…" Tag="file"/>
            </ComboBox>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
            <TextBlock Text="每轮消耗" Foreground="#203170" FontSize="12" Width="60" VerticalAlignment="Center"/>
            <CheckBox x:Name="PerTurnCheck" VerticalAlignment="Center"/>
            <TextBlock Text="自动关(秒)" Foreground="#536ba9" FontSize="11" VerticalAlignment="Center" Margin="8,0,4,0"/>
            <TextBox x:Name="PerTurnSecondsBox" Width="36" FontSize="12"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
            <TextBlock Text="提示模板" Foreground="#203170" FontSize="12" Width="60" VerticalAlignment="Center"/>
            <TextBox x:Name="PerTurnTemplateBox" Width="170" FontSize="12" ToolTip="可用占位符：{cost} {tokens} {model}"/>
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
            <TextBlock Text="吸附" Foreground="#203170" FontSize="12" Width="40" VerticalAlignment="Center"/>
            <CheckBox x:Name="SnapCheck" VerticalAlignment="Center"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
            <TextBlock Text="隐藏按钮" Foreground="#203170" FontSize="12" Width="60" VerticalAlignment="Center"/>
            <CheckBox x:Name="HideMenuCheck" VerticalAlignment="Center"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
            <TextBlock Text="锁定" Foreground="#203170" FontSize="12" Width="40" VerticalAlignment="Center"/>
            <CheckBox x:Name="LockCheck" VerticalAlignment="Center"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
            <TextBlock Text="角色" Foreground="#203170" FontSize="12" Width="40" VerticalAlignment="Center"/>
            <Button x:Name="RoleBtn" Content="选择图片…" Width="140" FontSize="11" Padding="3,2"/>
            <Button x:Name="RoleResetBtn" Content="默认" Width="40" FontSize="11" Padding="3,2" Margin="4,0,0,0"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
            <TextBlock Text="余额预警" Foreground="#203170" FontSize="12" Width="60" VerticalAlignment="Center"/>
            <TextBox x:Name="BalanceAlertBox" Width="170" FontSize="12" ToolTip="余额低于这个值就提醒；0 或留空 = 关闭"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
            <TextBlock Text="今日预算" Foreground="#203170" FontSize="12" Width="60" VerticalAlignment="Center"/>
            <TextBox x:Name="BudgetBox" Width="170" FontSize="12" ToolTip="今日已用达到这个值就提醒；0 或留空 = 关闭"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
            <TextBlock Text="台词" Foreground="#203170" FontSize="12" Width="40" VerticalAlignment="Center"/>
            <Button x:Name="LinesBtn" Content="编辑台词…" Width="120" FontSize="11" Padding="3,2"/>
            <Button x:Name="LinesReloadBtn" Content="重载" Width="40" FontSize="11" Padding="3,2" Margin="4,0,0,0"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
            <TextBlock Text="记录" Foreground="#203170" FontSize="12" Width="40" VerticalAlignment="Center"/>
            <Button x:Name="UsageViewBtn" Content="用量记录…" Width="120" FontSize="11" Padding="3,2"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
            <TextBlock Text="工具" Foreground="#203170" FontSize="12" Width="40" VerticalAlignment="Center"/>
            <Button x:Name="BubbleEditBtn" Content="泡泡编辑器…" Width="120" FontSize="11" Padding="3,2"/>
            <Button x:Name="ResMgrBtn" Content="资源管理…" Width="80" FontSize="11" Padding="3,2" Margin="4,0,0,0"/>
          </StackPanel>
          <Button x:Name="ExitBtn" Content="退出挂件" Margin="0,4,0,0" Padding="6,4" FontSize="12"/>
        </StackPanel>
      </ScrollViewer>
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
$codexValue = $win.FindName('CodexValue')
$soundCombo = $win.FindName('SoundCombo')
$soundCheck = $win.FindName('SoundCheck')
$volSlider = $win.FindName('VolSlider')
$volValue = $win.FindName('VolValue')
$usageCombo = $win.FindName('UsageCombo')
$peakCombo = $win.FindName('PeakCombo')
$bubbleCheck = $win.FindName('BubbleCheck')
$lockCheck = $win.FindName('LockCheck')
$lockBadge = $win.FindName('LockBadge')
$exitBtn = $win.FindName('ExitBtn')
$customSoundBtn = $win.FindName('CustomSoundBtn')
$endSoundCombo = $win.FindName('EndSoundCombo')
$snapCheck = $win.FindName('SnapCheck')
$hideMenuCheck = $win.FindName('HideMenuCheck')
$roleBtn = $win.FindName('RoleBtn')
$roleResetBtn = $win.FindName('RoleResetBtn')
$balanceAlertBox = $win.FindName('BalanceAlertBox')
$budgetBox = $win.FindName('BudgetBox')
$perTurnCheck = $win.FindName('PerTurnCheck')
$perTurnSecondsBox = $win.FindName('PerTurnSecondsBox')
$perTurnTemplateBox = $win.FindName('PerTurnTemplateBox')
$linesBtn = $win.FindName('LinesBtn')
$linesReloadBtn = $win.FindName('LinesReloadBtn')
$defaultBubblePanel = $win.FindName('DefaultBubblePanel')
$customBubblePanel = $win.FindName('CustomBubblePanel')
$customBubbleStack = $win.FindName('CustomBubbleStack')
$bubbleEditBtn = $win.FindName('BubbleEditBtn')
$resMgrBtn = $win.FindName('ResMgrBtn')
$usageViewBtn = $win.FindName('UsageViewBtn')

function Set-Role([string]$path) {
  try {
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { $path = Join-Path $AssetsDir 'DSniang1.png' }
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $fs = [System.IO.File]::OpenRead($path)
    $bi.BeginInit()
    $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bi.StreamSource = $fs
    $bi.EndInit()
    $fs.Close()
    $whale.Source = $bi
    Write-Log ('image ' + $bi.PixelWidth + 'x' + $bi.PixelHeight)
  } catch { Write-Log ('image-error: ' + $_.Exception.Message) }
}
Set-Role ([string]$script:State.rolePath)

function To-FileUri([string]$p) { return [System.Uri]::new('file:///' + ($p -replace '\\', '/')) }

$script:pressPlayer = New-Object System.Windows.Media.MediaPlayer
$script:releasePlayer = New-Object System.Windows.Media.MediaPlayer
$script:pressPlayer.Add_MediaOpened({ Write-Log 'press-media-opened' })
$script:releasePlayer.Add_MediaOpened({ Write-Log 'release-media-opened' })
$script:pressPlayer.Add_MediaFailed({ param($s, $e) Write-Log ('press-media-failed: ' + $e.ErrorException.Message) })
$script:releasePlayer.Add_MediaFailed({ param($s, $e) Write-Log ('release-media-failed: ' + $e.ErrorException.Message) })
function Set-SoundSet([string]$set) {
  try {
    if ($set -eq 'custom') {
      $p = [string]$script:State.customPress
      $r = [string]$script:State.customRelease
      if ($p -and (Test-Path -LiteralPath $p) -and $r -and (Test-Path -LiteralPath $r)) {
        $script:pressPlayer.Open((To-FileUri $p))
        $script:releasePlayer.Open((To-FileUri $r))
        return
      }
      # 自定义文件缺失 → 回落到小黄鸭
      $script:pressPlayer.Open((To-FileUri (Join-Path $AssetsDir 'Ya1.mp3')))
      $script:releasePlayer.Open((To-FileUri (Join-Path $AssetsDir 'Ya2.mp3')))
    } elseif ($set -eq 'fx1') {
      $script:pressPlayer.Open((To-FileUri (Join-Path $AssetsDir 'D1.mp3')))
      $script:releasePlayer.Open((To-FileUri (Join-Path $AssetsDir 'D2.mp3')))
    } else {
      $script:pressPlayer.Open((To-FileUri (Join-Path $AssetsDir 'Ya1.mp3')))
      $script:releasePlayer.Open((To-FileUri (Join-Path $AssetsDir 'Ya2.mp3')))
    }
  } catch { Write-Log ('sound-open-error: ' + $_.Exception.Message) }
}

# 任务结束音（一轮 Codex 会话结束 / 新增 token 时播放）
$script:endPlayer = New-Object System.Windows.Media.MediaPlayer
$script:endPlayer.Add_MediaOpened({ Write-Log 'end-media-opened' })
$script:endPlayer.Add_MediaFailed({ param($s, $e) Write-Log ('end-media-failed: ' + $e.ErrorException.Message) })
function Get-EndSoundPath {
  $s = [string]$script:State.endSound
  if ($s -eq 'orb') { return (Join-Path $AssetsDir 'minecraft-exp-orb.wav') }
  if ($s -eq 'a') { return (Join-Path $AssetsDir 'task-end-a.wav') }
  if ($s -and (Test-Path -LiteralPath $s)) { return $s }
  return ''
}
function Play-EndSound {
  try {
    if (-not $script:State.sound) { return }
    $p = Get-EndSoundPath
    if (-not $p) { return }
    $script:endPlayer.Volume = [double]$script:State.vol
    $script:endPlayer.Open((To-FileUri $p))
    $script:endPlayer.Play()
    Write-Log ('end-sound: ' + (Split-Path -Leaf $p))
  } catch { Write-Log ('end-sound-error: ' + $_.Exception.Message) }
}

# 吸附到屏幕边缘；贴左时把角色水平镜像（原版「贴左翻转」的简化版）
function Apply-Mirror([bool]$on) {
  try {
    if ($on) {
      if ($null -eq $whale.LayoutTransform) { $whale.LayoutTransform = New-Object System.Windows.Media.ScaleTransform -ArgumentList (-1.0), 1.0 }
    } else { $whale.LayoutTransform = $null }
  } catch {}
}
function Snap-Position {
  if (-not $script:State.snapOn) { return }
  try {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $m = 14.0
    if (($win.Left - $wa.Left) -le $m) { $win.Left = $wa.Left; Apply-Mirror $true }
    elseif ((($wa.Right - $win.Width) - $win.Left) -le $m) { $win.Left = $wa.Right - $win.Width; Apply-Mirror $false }
    if (($win.Top - $wa.Top) -le $m) { $win.Top = $wa.Top }
    elseif ((($wa.Bottom - $win.Height) - $win.Top) -le $m) { $win.Top = $wa.Bottom - $win.Height }
  } catch {}
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
$script:linesFile = Join-Path $AppDir 'custom-lines.txt'
function Reload-Lines {
  try {
    if (Test-Path -LiteralPath $script:linesFile) {
      $arr = @(Get-Content -LiteralPath $script:linesFile -Encoding UTF8 | Where-Object { $_.Trim() })
      if ($arr.Count) { $script:lines = $arr }
    }
  } catch {}
}
Reload-Lines

# 余额预警 / 今日预算（达到阈值时弹一次气泡提醒）
$script:balanceAlertOn = $false
$script:budgetAlertOn = $false
$script:apiAlertShown = @{}
function Show-Alert([string]$msg) {
  Write-Log ('alert: ' + $msg)
  $defaultBubblePanel.Visibility = 'Visible'
  $customBubblePanel.Visibility = 'Collapsed'
  $amountText.FontSize = 17
  $labelText.Text = '小鲸鱼提醒'
  $amountText.Text = $msg
  $hintText.Text = ''
  $script:bubbleMode = 'alert'
  $bubbleHost.Visibility = 'Visible'
  $bubbleText.Visibility = 'Visible'
  $script:bubbleUntil = (Get-Date).AddSeconds(6)
  Anim-Pop $bubbleHost $bubbleHostScale
  Anim-Pop $bubbleText $bubbleTextScale
}
function Check-Alerts {
  try {
    if ([double]$script:State.balanceAlert -gt 0 -and $null -ne $script:State.totalBalance) {
      if ([double]$script:State.totalBalance -le [double]$script:State.balanceAlert) {
        if (-not $script:balanceAlertOn) { $script:balanceAlertOn = $true; Show-Alert ('余额预警：仅剩 ' + (Fmt-Money $script:State.totalBalance)) }
      } else { $script:balanceAlertOn = $false }
    }
    if ([double]$script:State.dailyBudget -gt 0) {
      if ([double]$script:State.todayUsage -ge [double]$script:State.dailyBudget) {
        if (-not $script:budgetAlertOn) { $script:budgetAlertOn = $true; Show-Alert ('今日预算已达 ' + (Fmt-Money $script:State.todayUsage)) }
      } else { $script:budgetAlertOn = $false }
    }
  } catch {}
}
$script:lastCodexTurns = $null
$script:lastTurnTs = 0
$script:lastTurnSeeded = $false
$script:codexWinTip = ''

function Get-TurnCost($lt) {
  try {
    if ([string]$lt.model -notmatch 'deepseek') { return $null }
    $p = Get-Price ([string]$lt.model)
    $peak = if (Is-PeakTime (Get-Date)) { 1 } else { 0 }
    $hit = [double]$lt.cached
    $miss = [double]$lt.in - [double]$lt.cached + [double]$lt.cwrite
    if ($miss -lt 0) { $miss = 0 }
    $out = [double]$lt.out
    return (($hit / 1e6) * $p.hit[$peak] + ($miss / 1e6) * $p.miss[$peak] + ($out / 1e6) * $p.out[$peak])
  } catch { return $null }
}
function Show-PerTurnBubble($lt) {
  try {
    if (-not $script:State.bubbleOn) { return }
    $cost = Get-TurnCost $lt
    $costStr = if ($null -eq $cost) { '—' } else { (Fmt-Money $cost) }
    $tpl = [string]$script:State.perTurnTemplate
    if (-not $tpl) { $tpl = '本轮 {cost} · {tokens} tokens' }
    $msg = $tpl.Replace('{cost}', $costStr).Replace('{tokens}', ([long]$lt.total).ToString('N0')).Replace('{model}', [string]$lt.model)
  $defaultBubblePanel.Visibility = 'Visible'
  $customBubblePanel.Visibility = 'Collapsed'
  $amountText.FontSize = 16
  $labelText.Text = '本轮消耗'
    $amountText.Text = $msg
    $hintText.Text = [string]$lt.model
    $script:bubbleMode = 'perTurn'
    $bubbleHost.Visibility = 'Visible'; $bubbleText.Visibility = 'Visible'
    $sec = [int]$script:State.perTurnSeconds
    $script:bubbleUntil = if ($sec -gt 0) { (Get-Date).AddSeconds($sec) } else { (Get-Date).AddYears(10) }
    Anim-Pop $bubbleHost $bubbleHostScale; Anim-Pop $bubbleText $bubbleTextScale
  } catch { Write-Log ('per-turn-error: ' + $_.Exception.Message) }
}
function Format-Window($w) {
  if (-not $w) { return '' }
  $parts = @()
  if ($null -ne $w.usedPct) { $parts += ([math]::Round([double]$w.usedPct, 1).ToString() + '%') }
  if ($w.resetAt) {
    try {
      $dt = [datetime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc).AddMilliseconds([double]$w.resetAt).ToLocalTime()
      $h = [int]($dt - (Get-Date)).TotalHours
      if ($h -gt 0) { $parts += ($h.ToString() + '小时后重置') }
    } catch {}
  }
  return ($parts -join ' · ')
}
function Record-Turn($lt) {
  try {
    $tf = Join-Path $AppDir '.dshw-turns.json'
    $arr = @()
    if (Test-Path -LiteralPath $tf) { try { $arr = @(Get-Content -LiteralPath $tf -Raw | ConvertFrom-Json) } catch {} }
    $cost = Get-TurnCost $lt
    $dt = [datetime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc).AddMilliseconds([double]$lt.ts).ToLocalTime()
    $rec = [ordered]@{
      ts = [long]$lt.ts
      date = $dt.ToString('yyyy-MM-dd HH:mm')
      model = [string]$lt.model
      tokens = [long]$lt.total
      cost = if ($null -eq $cost) { 0 } else { [double]$cost }
    }
    $arr = @($arr) + $rec
    if ($arr.Count -gt 3000) { $arr = @($arr | Select-Object -Last 3000) }
    [System.IO.File]::WriteAllText($tf, (($arr | ConvertTo-Json -Depth 5) + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
  } catch { Write-Log ('record-turn-error: ' + $_.Exception.Message) }
}

function Apply-Codex([string]$rawCodex) {
  if (-not $rawCodex) { return }
  try {
    $script:State.codex = $rawCodex | ConvertFrom-Json
    Update-CodexText
    if (-not $script:State.codex.ok) { Write-Log ('codex=' + $script:State.codex.error); return }
    Write-Log ('codex=今日 ' + $script:State.codex.todayText + ' · 本月 ' + $script:State.codex.monthText + ' · 累计 ' + $script:State.codex.totalText)
    $script:codexWinTip = ''
    if ($script:State.codex.windows) {
      $w5 = Format-Window $script:State.codex.windows.primary
      $w7 = Format-Window $script:State.codex.windows.secondary
      $wt = @()
      if ($w5) { $wt += ('5h ' + $w5) }
      if ($w7) { $wt += ('周 ' + $w7) }
      if ($wt.Count) { $script:codexWinTip = ($wt -join ' | ') }
    }
    Update-CodexText
    $lt = $script:State.codex.lastTurn
    if ($lt -and [long]$lt.ts -gt 0) {
      if (-not $script:lastTurnSeeded) {
        $script:lastTurnTs = [long]$lt.ts
        $script:lastTurnSeeded = $true
      } elseif ([long]$lt.ts -gt [long]$script:lastTurnTs) {
        $script:lastTurnTs = [long]$lt.ts
        Play-EndSound
        if ($script:State.perTurnOn) { Show-PerTurnBubble $lt }
        Record-Turn $lt
        Write-Log ('turn-done model=' + $lt.model + ' tokens=' + $lt.total)
      }
    }
  } catch { Write-Log ('codex-parse-error: ' + $_.Exception.Message) }
}

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
  $amountText.FontSize = 30
  $amountText.Text = (Fmt-Money $script:State.totalBalance)
  $parts = @()
  $parts += ('今日已用 ' + (Fmt-Money $script:State.todayUsage))
  $peakLabel = if ($script:State.isPeak) { $peakText } else { $offText }
  try {
    $cd = Get-PeakCountdown (Get-Date)
    $mins = [int]$cd.min
    $when = if ($mins -ge 60) { ('{0}小时{1}分后' -f [int]($mins / 60), ($mins % 60)) } else { ('{0}分钟后' -f $mins) }
    $peakLabel = $peakLabel + '（' + $when + '转' + $cd.to + '）'
  } catch {}
  $parts += $peakLabel
  $hintText.Text = ($parts -join '  ·  ')
}

function Update-CodexText {
  try {
    if (-not $script:State.codex) { $codexValue.Text = '统计中…'; $codexValue.ToolTip = $null; return }
    if (-not $script:State.codex.ok) { $codexValue.Text = [string]$script:State.codex.error; $codexValue.ToolTip = $null; return }
    $c = $script:State.codex
    $codexValue.Text = ('今日 ' + $c.todayText + ' · 本月 ' + $c.monthText + ' · 累计 ' + $c.totalText)
    $sorted = @($c.byModel.PSObject.Properties | Sort-Object { [double]$_.Value.tokens } -Descending)
    $tips = @($sorted | ForEach-Object { $_.Name + '  ' + ([double]$_.Value.tokens).ToString('N0') + ' tokens' })
    if ($script:codexWinTip) { $tips += ('订阅窗口：' + $script:codexWinTip) }
    if ($tips.Count) { $codexValue.ToolTip = ($tips -join "`n") }
  } catch {}
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
  if (-not $script:State.bubbleOn) { return }
  $defaultBubblePanel.Visibility = 'Visible'
  $customBubblePanel.Visibility = 'Collapsed'
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

# ---- 模块化泡泡系统 ----
$ImgsDir = Join-Path $AppDir 'whale-bubble-imgs'
if (-not (Test-Path -LiteralPath $ImgsDir)) { New-Item -ItemType Directory -Path $ImgsDir -Force | Out-Null }
$script:bubbleCfg = $null
$script:bubbleIdx = -1
$script:hasCustomBubbles = $false
$script:clickAdvance = $false
function Reload-BubbleCfg {
  try {
    $bf = Join-Path $AppDir '.dshw-bubble.json'
    $script:bubbleCfg = $null
    if (Test-Path -LiteralPath $bf) { $script:bubbleCfg = Get-Content -LiteralPath $bf -Raw | ConvertFrom-Json }
    $script:hasCustomBubbles = ($null -ne $script:bubbleCfg -and @($script:bubbleCfg.bubbles).Count -gt 0)
    $script:clickAdvance = ($script:bubbleCfg -and $script:bubbleCfg.clickAdvance)
  } catch {}
}
Reload-BubbleCfg

function New-Brush([string]$hex, [string]$defaultHex) {
  try {
    $s = $hex; if (-not $s) { $s = $defaultHex }
    if (-not $s) { return [System.Windows.Media.Brushes]::Transparent }
    return [System.Windows.Media.BrushConverter]::new().ConvertFromString($s)
  } catch { return [System.Windows.Media.Brushes]::Transparent }
}
function New-StyledText([string]$text, $st) {
  $tb = New-Object System.Windows.Controls.TextBlock
  $tb.Text = $text
  $tb.TextWrapping = 'Wrap'
  $tb.MaxWidth = 160
  if ($st) {
    if ($st.size) { try { $tb.FontSize = [double]$st.size } catch {} }
    if ($st.bold) { $tb.FontWeight = 'Bold' }
    if ($st.italic) { $tb.FontStyle = 'Italic' }
    if ($st.underline) { $tb.TextDecorations = [System.Windows.TextDecorations]::Underline }
    $tb.Foreground = New-Brush $st.color '#536ba9'
    if ($st.bg) { $tb.Background = New-Brush $st.bg '' }
  }
  return $tb
}
function Pick-Weighted($items, [string]$prop) {
  $arr = @($items)
  if ($arr.Count -eq 0) { return $null }
  $tot = 0.0
  foreach ($i in $arr) { $tot += [double]$i.weight }
  if ($tot -le 0) { return $arr[0] }
  $r = Get-Random -Minimum 0.0 -Maximum $tot
  $acc = 0.0
  foreach ($i in $arr) { $acc += [double]$i.weight; if ($r -lt $acc) { return $i } }
  return $arr[$arr.Count - 1]
}
function New-BubbleImage([string]$file) {
  $img = New-Object System.Windows.Controls.Image
  $img.MaxWidth = 160
  $img.MaxHeight = 80
  $img.Stretch = 'Uniform'
  $p = [string]$file
  if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $ImgsDir $p }
  if (-not (Test-Path -LiteralPath $p)) {
    $p2 = Join-Path $AssetsDir $file
    if (Test-Path -LiteralPath $p2) { $p = $p2 }
  }
  if (-not (Test-Path -LiteralPath $p)) {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = '[缺图: ' + $file + ']'
    $tb.FontSize = 11
    $tb.Foreground = [System.Windows.Media.Brushes]::Gray
    return $tb
  }
  try {
    if ([System.IO.Path]::GetExtension($p).ToLower() -eq '.gif') {
      $dec = New-Object System.Windows.Media.Imaging.GifBitmapDecoder -ArgumentList ([System.Uri]::new('file:///' + ($p -replace '\\', '/'))), ([System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat), ([System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
      if ($dec.Frames.Count -le 1) { $img.Source = $dec.Frames[0]; return $img }
      $idx = 0
      $timer = New-Object System.Windows.Threading.DispatcherTimer
      $timer.Interval = [TimeSpan]::FromMilliseconds(100)
      $timer.Add_Tick({ $idx = ($idx + 1) % $dec.Frames.Count; $img.Source = $dec.Frames[$idx] })
      $img.Tag = $timer
      $img.Add_Loaded({ $timer.Start() })
      $img.Add_Unloaded({ $timer.Stop() })
      $img.Source = $dec.Frames[0]
      return $img
    }
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $fs = [System.IO.File]::OpenRead($p)
    $bi.BeginInit(); $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad; $bi.StreamSource = $fs; $bi.EndInit(); $fs.Close()
    $img.Source = $bi
    return $img
  } catch {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = '[图片加载失败]'
    $tb.FontSize = 11
    $tb.Foreground = [System.Windows.Media.Brushes]::Gray
    return $tb
  }
}
function Get-PeakLabel {
  $offText = '空闲时段'; $peakText = '高峰时段'
  if ($script:State.peakMode -eq 'liangwen') { $offText = '梁文谷'; $peakText = '梁文峰' }
  elseif ($script:State.peakMode -eq 'qiangqiang') { $offText = '!?谷谷?!'; $peakText = '!?峰峰?!' }
  $l = if ($script:State.isPeak) { $peakText } else { $offText }
  try {
    $cd = Get-PeakCountdown (Get-Date)
    $m = [int]$cd.min
    $w = if ($m -ge 60) { ('{0}小时{1}分后' -f [int]($m / 60), ($m % 60)) } else { ('{0}分钟后' -f $m) }
    $l = $l + '（' + $w + '转' + $cd.to + '）'
  } catch {}
  return $l
}
function New-ModuleEl($m) {
  $st = $m.style
  switch ([string]$m.type) {
    'text' { return (New-StyledText ([string]$m.text) $st) }
    'link' {
      $tb = New-StyledText ([string]$m.text) $st
      $tb.Foreground = New-Brush '#1a5fd0' '#1a5fd0'
      $tb.Cursor = 'Hand'
      $url = [string]$m.url
      $tb.Add_MouseLeftButtonDown({ try { Start-Process $url } catch {} })
      return $tb
    }
    'random' {
      $items = @($m.items)
      if ($items.Count -eq 0) { return (New-StyledText '(空)' $st) }
      $pick = Pick-Weighted $items 'text'
      return (New-StyledText ([string]$pick.text) $st)
    }
    'image' { return (New-BubbleImage ([string]$m.file)) }
    'randomImage' {
      $items = @($m.items)
      if ($items.Count -eq 0) { return (New-StyledText '(空)' $st) }
      $pick = Pick-Weighted $items 'file'
      return (New-BubbleImage ([string]$pick.file))
    }
    'balance' { return (New-StyledText (Fmt-Money $script:State.totalBalance) $st) }
    'today' { return (New-StyledText ('今日已用 ' + (Fmt-Money $script:State.todayUsage)) $st) }
    'peak' { return (New-StyledText (Get-PeakLabel) $st) }
  }
  return (New-StyledText '' $st)
}
function Build-CustomBubble($bubble) {
  $panel = New-Object System.Windows.Controls.StackPanel
  $panel.Orientation = 'Vertical'
  $panel.HorizontalAlignment = 'Center'
  foreach ($row in @($bubble.rows)) {
    $rp = New-Object System.Windows.Controls.WrapPanel
    $rp.HorizontalAlignment = 'Center'
    foreach ($m in @($row.modules)) {
      $el = New-ModuleEl $m
      if ($el) { $rp.Children.Add($el) | Out-Null }
    }
    $panel.Children.Add($rp) | Out-Null
  }
  return $panel
}
function Show-CustomBubble($bubble) {
  try {
    if (-not $script:State.bubbleOn) { return }
    $customBubbleStack.Children.Clear()
    $customBubbleStack.Children.Add((Build-CustomBubble $bubble)) | Out-Null
    $defaultBubblePanel.Visibility = 'Collapsed'
    $customBubblePanel.Visibility = 'Visible'
    $script:bubbleMode = 'custom'
    $bubbleHost.Visibility = 'Visible'
    $bubbleText.Visibility = 'Visible'
    $script:bubbleUntil = (Get-Date).AddSeconds(6)
    Anim-Pop $bubbleHost $bubbleHostScale
    Anim-Pop $bubbleText $bubbleTextScale
  } catch { Write-Log ('custom-bubble-error: ' + $_.Exception.Message) }
}
function Show-FirstBubble {
  Reload-BubbleCfg
  if (-not $script:hasCustomBubbles) { return }
  $script:bubbleIdx = 0
  Show-CustomBubble @($script:bubbleCfg.bubbles)[0]
}
function Advance-Bubble {
  Reload-BubbleCfg
  if (-not $script:hasCustomBubbles) { return }
  $n = @($script:bubbleCfg.bubbles).Count
  if ($script:clickAdvance) {
    $script:bubbleIdx++
    if ($script:bubbleIdx -ge $n) { $script:bubbleIdx = -1; Hide-Bubble; return }
  } else {
    if ($script:bubbleIdx -lt 0) { $script:bubbleIdx = 0 } else { $script:bubbleIdx = ($script:bubbleIdx + 1) % $n }
  }
  Show-CustomBubble @($script:bubbleCfg.bubbles)[$script:bubbleIdx]
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
  if (($win.Left - $wa.Left) -le 1) { Apply-Mirror $true } else { Apply-Mirror $false }
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
    if ($script:moved -and -not $script:State.locked) { Snap-Position; Save-Position }
    else {
      if ($script:hasCustomBubbles) {
        if ($script:clickAdvance) { Advance-Bubble } else { Show-FirstBubble }
        Start-BalanceFetch $false
      } else { Show-Bubble 'balance'; Start-BalanceFetch $true }
    }
  }
})

$bubbleText.Cursor = 'Hand'
$bubbleText.Add_MouseLeftButtonDown({ if ($script:hasCustomBubbles) { Advance-Bubble } else { Show-Bubble 'line' } })

$whale.Add_MouseEnter({ if (-not $script:State.hideMenuBtn) { $menuBtn.Opacity = 1 } })
$menuBtn.Add_MouseEnter({ if (-not $script:State.hideMenuBtn) { $menuBtn.Opacity = 1 } })
$whale.Add_MouseRightButtonDown({ Open-Menu })

$script:menuHideAt = $null
$script:menuHoverTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:menuHoverTimer.Interval = [TimeSpan]::FromMilliseconds(180)
$script:menuHoverTimer.Add_Tick({
  $over = $whale.IsMouseOver -or $menuBtn.IsMouseOver -or $menuPopup.IsOpen
  if ($over) { $script:menuHideAt = $null; if (-not $script:State.hideMenuBtn) { $menuBtn.Opacity = 1 }; return }
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
    $soundCheck.IsChecked = [bool]$script:State.sound
    $lockCheck.IsChecked = [bool]$script:State.locked
    $snapCheck.IsChecked = [bool]$script:State.snapOn
    $hideMenuCheck.IsChecked = [bool]$script:State.hideMenuBtn
    $balanceAlertBox.Text = if ([double]$script:State.balanceAlert -gt 0) { ([double]$script:State.balanceAlert).ToString('0.##') } else { '' }
    $budgetBox.Text = if ([double]$script:State.dailyBudget -gt 0) { ([double]$script:State.dailyBudget).ToString('0.##') } else { '' }
    $perTurnCheck.IsChecked = [bool]$script:State.perTurnOn
    $perTurnSecondsBox.Text = [string]$script:State.perTurnSeconds
    $perTurnTemplateBox.Text = [string]$script:State.perTurnTemplate
    foreach ($it in $soundCombo.Items) { if ([string]$it.Tag -eq [string]$script:State.soundSet) { $soundCombo.SelectedItem = $it } }
    foreach ($it in $usageCombo.Items) { if ([string]$it.Tag -eq [string]$script:State.usageMode) { $usageCombo.SelectedItem = $it } }
    foreach ($it in $peakCombo.Items) { if ([string]$it.Tag -eq [string]$script:State.peakMode) { $peakCombo.SelectedItem = $it } }
    $es = [string]$script:State.endSound
    foreach ($it in $endSoundCombo.Items) {
      if ($es -eq 'orb' -and [string]$it.Tag -eq 'orb') { $endSoundCombo.SelectedItem = $it }
      elseif ($es -eq 'a' -and [string]$it.Tag -eq 'a') { $endSoundCombo.SelectedItem = $it }
      elseif ($es -eq '' -and [string]$it.Tag -eq '') { $endSoundCombo.SelectedItem = $it }
      elseif ($es -notin @('', 'orb', 'a') -and [string]$it.Tag -eq 'file') { $endSoundCombo.SelectedItem = $it }
    }
    Reload-Lines
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
$soundCheck.Add_Click({
  if ($script:suppress) { return }
  $script:State.sound = [bool]$soundCheck.IsChecked
  Write-SizeConfig
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

$roleBtn.Add_Click({
  try {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = '选择角色图片'
    $dlg.Filter = '图片|*.png;*.jpg;*.jpeg;*.gif'
    if ($dlg.ShowDialog() -eq $true) {
      $script:State.rolePath = [string]$dlg.FileName
      Set-Role $script:State.rolePath
      Write-SizeConfig
    }
  } catch { Write-Log ('role-error: ' + $_.Exception.Message) }
})
$roleResetBtn.Add_Click({
  $script:State.rolePath = ''
  Set-Role ''
  Write-SizeConfig
})

$customSoundBtn.Add_Click({
  try {
    $d1 = New-Object Microsoft.Win32.OpenFileDialog
    $d1.Title = '选择「按下」音效'
    $d1.Filter = '音频|*.mp3;*.wav'
    if ($d1.ShowDialog() -ne $true) { return }
    $d2 = New-Object Microsoft.Win32.OpenFileDialog
    $d2.Title = '选择「松开」音效'
    $d2.Filter = '音频|*.mp3;*.wav'
    if ($d2.ShowDialog() -ne $true) { return }
    $script:State.customPress = [string]$d1.FileName
    $script:State.customRelease = [string]$d2.FileName
    $script:State.customSoundOn = $true
    $script:State.soundSet = 'custom'
    Set-SoundSet 'custom'
    Write-SizeConfig
    Play-Press
  } catch { Write-Log ('custom-sound-error: ' + $_.Exception.Message) }
})

$endSoundCombo.Add_SelectionChanged({
  if ($script:suppress) { return }
  $tag = [string]$endSoundCombo.SelectedItem.Tag
  if ($tag -eq 'file') {
    try {
      $dlg = New-Object Microsoft.Win32.OpenFileDialog
      $dlg.Title = '选择任务结束音效'
      $dlg.Filter = '音频|*.mp3;*.wav'
      if ($dlg.ShowDialog() -eq $true) { $script:State.endSound = [string]$dlg.FileName } else { $script:State.endSound = '' }
    } catch { $script:State.endSound = '' }
  } elseif ($tag -eq 'orb' -or $tag -eq 'a') {
    $script:State.endSound = $tag
  } else {
    $script:State.endSound = ''
  }
  Write-SizeConfig
  Play-EndSound
})

$snapCheck.Add_Click({
  if ($script:suppress) { return }
  $script:State.snapOn = [bool]$snapCheck.IsChecked
  Write-SizeConfig
})
$hideMenuCheck.Add_Click({
  if ($script:suppress) { return }
  $script:State.hideMenuBtn = [bool]$hideMenuCheck.IsChecked
  Write-SizeConfig
  if ($script:State.hideMenuBtn) { $menuBtn.Opacity = 0 } else { $menuBtn.Opacity = 1 }
})

function Set-NumericSetting($box, [string]$key) {
  $v = $box.Text.Trim()
  $d = 0.0
  if ($v -ne '') { try { $d = [double]$v } catch { $d = 0.0 } }
  if ($d -lt 0) { $d = 0.0 }
  if ($key -eq 'balanceAlert') { $script:State.balanceAlert = $d } else { $script:State.dailyBudget = $d }
  Write-SizeConfig
}
$balanceAlertBox.Add_LostFocus({ if ($script:suppress) { return }; Set-NumericSetting $balanceAlertBox 'balanceAlert' })
$budgetBox.Add_LostFocus({ if ($script:suppress) { return }; Set-NumericSetting $budgetBox 'dailyBudget' })
$balanceAlertBox.Add_KeyDown({ param($s, $e) if ($e.Key -eq [System.Windows.Input.Key]::Enter) { Set-NumericSetting $balanceAlertBox 'balanceAlert' } })
$budgetBox.Add_KeyDown({ param($s, $e) if ($e.Key -eq [System.Windows.Input.Key]::Enter) { Set-NumericSetting $budgetBox 'dailyBudget' } })
$perTurnCheck.Add_Click({ if ($script:suppress) { return }; $script:State.perTurnOn = [bool]$perTurnCheck.IsChecked; Write-SizeConfig })
$perTurnSecondsBox.Add_LostFocus({ if ($script:suppress) { return }; $v = $perTurnSecondsBox.Text.Trim(); if ($v -eq '') { $v = '0' }; try { $script:State.perTurnSeconds = [int]$v } catch { $script:State.perTurnSeconds = 0 }; Write-SizeConfig })
$perTurnTemplateBox.Add_LostFocus({ if ($script:suppress) { return }; $script:State.perTurnTemplate = $perTurnTemplateBox.Text; Write-SizeConfig })

$linesBtn.Add_Click({
  try {
    if (-not (Test-Path -LiteralPath $script:linesFile)) {
      [System.IO.File]::WriteAllLines($script:linesFile, $script:lines, (New-Object System.Text.UTF8Encoding($true)))
    }
    Start-Process notepad.exe -ArgumentList $script:linesFile
  } catch { Write-Log ('lines-open-error: ' + $_.Exception.Message) }
})
$linesReloadBtn.Add_Click({ Reload-Lines; Show-Bubble 'line'; Write-Log 'lines-reloaded' })

$bubbleEditBtn.Add_Click({
  try {
    $menuPopup.IsOpen = $false
    Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $AppDir 'bubble-editor.ps1'), '-AppDir', ("`"$AppDir`"") -WorkingDirectory $AppDir
  } catch { Write-Log ('bubble-editor-error: ' + $_.Exception.Message) }
})

$resMgrBtn.Add_Click({
  try {
    $menuPopup.IsOpen = $false
    Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $AppDir 'resource-manager.ps1'), '-AppDir', ("`"$AppDir`"") -WorkingDirectory $AppDir
  } catch { Write-Log ('resource-manager-error: ' + $_.Exception.Message) }
})
$usageViewBtn.Add_Click({
  try {
    $menuPopup.IsOpen = $false
    Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $AppDir 'usage-viewer.ps1'), '-AppDir', ("`"$AppDir`"") -WorkingDirectory $AppDir
  } catch { Write-Log ('usage-viewer-error: ' + $_.Exception.Message) }
})

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
$refreshTimer.Interval = [TimeSpan]::FromSeconds(20)
$refreshTimer.Add_Tick({ Start-BalanceFetch $false })
$refreshTimer.Start()

$script:fetchTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:fetchTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$script:fetchTimer.Add_Tick({
  if (-not $script:fetchBusy -or -not $script:fetchHandle) { return }
  if (-not $script:fetchHandle.IsCompleted) { return }
  $raw = ''
  $rawUsage = ''
  $rawCodex = ''
  try {
    $out = $script:fetchPS.EndInvoke($script:fetchHandle)
    if ($out -and $out.Count -gt 0) {
      $envelope = [string]$out[$out.Count - 1]
      try {
        $pe = $envelope | ConvertFrom-Json
        if ($null -ne $pe.balance) { $raw = [string]$pe.balance; $rawUsage = [string]$pe.usage; $rawCodex = [string]$pe.codex }
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
  # Codex 本地会话统计（与余额无关，即使没配 API Key 也照常更新）
  Apply-Codex $rawCodex
  if ($script:bubbleAfterFetch) {
    if ($bubbleHost.Visibility -eq 'Visible' -and $script:bubbleMode -eq 'balance') {
      Update-BubbleText
      $script:bubbleUntil = (Get-Date).AddSeconds(5)
    } else {
      Show-Bubble 'balance'
    }
  }
  Check-Alerts
})
$script:fetchTimer.Start()

# 快速 Codex 轮询（每 3 秒一次，及时报消耗；余额仍走上面的 20 秒定时）
$script:codexRs = $null; $script:codexPS = $null; $script:codexHandle = $null; $script:codexBusy = $false
$script:codexHelperPath = Join-Path $AppDir 'codexstats.js'
function Start-CodexCheck {
  if ($script:codexBusy) { return }
  $n = Find-Node
  if (-not $n -or -not (Test-Path -LiteralPath $script:codexHelperPath)) { return }
  if (-not $script:codexRs) {
    try { $script:codexRs = [runspacefactory]::CreateRunspace(); $script:codexRs.ApartmentState = [System.Threading.ApartmentState]::MTA; $script:codexRs.Open() } catch { $script:codexRs = $null; return }
  }
  $script:codexBusy = $true
  $csb = { param($node, $helper) $o = ''; try { $t = & $node $helper 2>$null; if ($t) { $o = ($t -join '') } } catch {}; $o }
  $script:codexPS = [powershell]::Create(); $script:codexPS.Runspace = $script:codexRs
  [void]$script:codexPS.AddScript($csb).AddArgument($n).AddArgument($script:codexHelperPath)
  $script:codexHandle = $script:codexPS.BeginInvoke()
}
$codexTimer = New-Object System.Windows.Threading.DispatcherTimer
$codexTimer.Interval = [TimeSpan]::FromSeconds(3)
$codexTimer.Add_Tick({ Start-CodexCheck })
$codexTimer.Start()
$script:codexPollTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:codexPollTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$script:codexPollTimer.Add_Tick({
  if (-not $script:codexBusy -or -not $script:codexHandle) { return }
  if (-not $script:codexHandle.IsCompleted) { return }
  $rawC = ''
  try { $outC = $script:codexPS.EndInvoke($script:codexHandle); if ($outC -and $outC.Count -gt 0) { $rawC = [string]$outC[$outC.Count - 1] } } catch { Write-Log ('codex-fast-error: ' + $_.Exception.Message) }
  try { $script:codexPS.Dispose() } catch {}
  $script:codexPS = $null; $script:codexHandle = $null; $script:codexBusy = $false
  if ($rawC) { Apply-Codex $rawC }
})
$script:codexPollTimer.Start()

$win.Add_Loaded({
  Restore-Position
  Apply-Scale
  Write-Log ('window ' + [int]$win.Left + ',' + [int]$win.Top + ' ' + [int]$win.Width + 'x' + [int]$win.Height + ' topmost=' + $win.Topmost + ' scale=' + $script:State.scale)
  Write-Log 'window-loaded'
  Show-Bubble 'balance'
  Start-BalanceFetch $false
  if ($Test -and $script:hasCustomBubbles) { Show-FirstBubble }
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

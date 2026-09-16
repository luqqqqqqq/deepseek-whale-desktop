// ============================================================
// 自动获取 DeepSeek 平台会话令牌（DEEPSEEK_PLATFORM_TOKEN）
//
// 原理：
//   用一个专用浏览器配置（不动你日常的 Edge）打开
//   https://platform.deepseek.com/usage ，
//   一边监听页面自己发出的 API 请求，一边扫描 localStorage，
//   拿到候选令牌后立刻调一次用量接口验证，
//   只有「真的能读到用量」的令牌才会被写进 config.json。
//
// 第一次运行：会弹出一个浏览器窗口，你在里面登录一次即可（之后就不用再登）。
// 以后运行：后台静默完成，不弹窗。
//
// 用法：双击同目录的  自动获取令牌.bat
//      或手动：node 自动获取令牌.js [config.json 的路径]
//
// 可选参数 / 环境变量：
//   --no-visible            不弹窗（只做后台尝试，调试用）
//   --profile <目录>        指定浏览器配置目录
//   WHALE_PROFILE=<目录>    同上
//   WHALE_LOGIN_WAIT=<秒>   弹窗等待登录的时间，默认 300
// ============================================================

'use strict'

const fs = require('fs')
const os = require('os')
const path = require('path')

// ---------- 找到 playwright（优先 Codex 自带运行时，其次系统安装） ----------
function findPlaywright() {
  const cands = []
  try {
    const root = path.join(os.homedir(), '.cache', 'codex-runtimes')
    for (const d of fs.readdirSync(root)) {
      cands.push(path.join(root, d, 'dependencies', 'node', 'node_modules', 'playwright'))
    }
  } catch (e) { /* 没有也没关系 */ }
  cands.push(path.join(os.homedir(), '.cache', 'codex-runtimes', 'codex-primary-runtime',
    'dependencies', 'node', 'node_modules', 'playwright'))
  cands.push('playwright')
  for (const c of cands) {
    try { return require(c) } catch (e) { /* 继续找 */ }
  }
  throw new Error('找不到 playwright。请用 自动获取令牌.bat 运行；' +
    '若仍报错，先执行一次： npm i -g playwright（需要 Node.js）')
}

const { chromium } = findPlaywright()

// ---------- 参数 ----------
const argv = process.argv.slice(2)
const noVisible = argv.includes('--no-visible')
let profileArg = ''
{
  const i = argv.indexOf('--profile')
  if (i >= 0 && argv[i + 1]) profileArg = argv[i + 1]
  if (process.env.WHALE_PROFILE) profileArg = process.env.WHALE_PROFILE
}
const configArg = argv.find((a) => !a.startsWith('--') && a.endsWith('.json'))

const CONFIG = configArg || path.join(__dirname, 'config.json')
const PROFILE_DIR = profileArg || path.join(os.homedir(), 'AppData', 'Local', 'DSHWhale', 'browser-profile')
const LOGIN_WAIT = parseInt(process.env.WHALE_LOGIN_WAIT || '300', 10)
const PLATFORM = 'https://platform.deepseek.com'
const USAGE_PAGE = PLATFORM + '/usage'

function log(s) { console.log(s) }

// 在页面里扫描候选令牌（localStorage / sessionStorage / cookie）
// 注意：DeepSeek 平台的令牌不是 JWT，而是一串 64 位的 base64 随机串，
//       所以不能只认 eyJ 开头；具体是不是真令牌，交给后面的接口验证。
const SCAN = `(() => {
  const out = [];
  const ok = (v) => {
    if (typeof v !== 'string') return false;
    const s = v.trim().replace(/^Bearer\\s+/i, '');
    if (/^eyJ[A-Za-z0-9_-]{10,}/.test(s)) return true;
    return /^[A-Za-z0-9+/=_-]{40,200}$/.test(s);
  };
  const push = (w, k, v) => out.push({ w: w, k: k, v: v.trim().replace(/^Bearer\\s+/i, '') });
  try {
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i), v = localStorage.getItem(k);
      if (ok(v)) push('localStorage', k, v);
    }
  } catch (e) {}
  try {
    for (let i = 0; i < sessionStorage.length; i++) {
      const k = sessionStorage.key(i), v = sessionStorage.getItem(k);
      if (ok(v)) push('sessionStorage', k, v);
    }
  } catch (e) {}
  try {
    document.cookie.split(';').forEach((c) => {
      const i = c.indexOf('=');
      if (i < 0) return;
      const k = c.slice(0, i).trim(), v = c.slice(i + 1);
      if (ok(v)) push('cookie', k, v);
    });
  } catch (e) {}
  return out;
})()`

// 用令牌调一次用量接口，确认真的能读到数据
async function verify(token) {
  const now = new Date()
  const tz = -now.getTimezoneOffset() * 60
  const start = Math.floor(new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime() / 1000)
  const url = PLATFORM + '/api/v0/usage/by_api_key/amount?start=' + start + '&end=' + (start + 86400) + '&tz=' + tz
  try {
    const r = await fetch(url, { headers: { Authorization: 'Bearer ' + token } })
    const txt = await r.text()
    let j = null
    try { j = JSON.parse(txt) } catch (e) {}
    if (!j) return { ok: false, why: 'HTTP ' + r.status + '（响应不是 JSON，可能被网络拦截或需要代理）' }
    if (j.code !== 0) return { ok: false, why: 'code=' + j.code + ' ' + (j.msg || '') }
    const series = j.data && j.data.biz_data && j.data.biz_data.series
    if (!Array.isArray(series)) return { ok: false, why: 'HTTP ' + r.status + '，返回里没有 series 字段' }
    return { ok: true, why: '成功读到用量（' + series.length + ' 个模型分组）' }
  } catch (e) {
    return { ok: false, why: '连接失败：' + e.message }
  }
}

// 开一次浏览器：把候选令牌逐个拿去验证，返回第一个「真能读到用量」的令牌
async function grabVerified(opts) {
  const headless = opts.headless
  const waitMs = opts.waitMs
  const label = opts.label
  const base = {
    headless: headless,
    args: ['--no-first-run', '--no-default-browser-check', '--disable-features=Translate'],
  }
  let ctx
  try {
    ctx = await chromium.launchPersistentContext(PROFILE_DIR, Object.assign({ channel: 'msedge' }, base))
  } catch (e) {
    log('   （没找到 Edge，改用内置浏览器）')
    ctx = await chromium.launchPersistentContext(PROFILE_DIR, base)
  }

  const captured = new Set()
  const tried = new Set()
  try {
    const page = ctx.pages()[0] || (await ctx.newPage())
    ctx.on('request', (r) => {
      try {
        if (!r.url().includes('platform.deepseek.com')) return
        const h = r.headers()['authorization'] || r.headers()['Authorization']
        if (!h) return
        const t = h.replace(/^Bearer\s+/i, '').trim()
        if (t.length >= 20) captured.add(t)
      } catch (e) {}
    })

    const resp = await page.goto(USAGE_PAGE, { waitUntil: 'domcontentloaded', timeout: 60000 })
    log('   ' + label + '：页面 HTTP ' + (resp ? resp.status() : '?') + '，地址 ' + page.url())

    const deadline = Date.now() + waitMs
    let lastLog = 0
    let round = 0
    while (true) {
      round++
      let storage = []
      try { storage = await page.evaluate(SCAN) } catch (e) { storage = [] }
      const list = Array.from(captured).concat(storage.map((s) => s.v))
      for (const t of list) {
        const k = String(t).trim()
        if (!k || tried.has(k)) continue
        tried.add(k)
        const v = await verify(k)
        log('   候选令牌（长度 ' + k.length + '）→ ' + (v.ok ? '✅ ' : '❌ ') + v.why)
        if (v.ok) return { token: k, where: captured.has(k) ? '网络请求' : '页面存储', url: page.url() }
      }
      if (Date.now() >= deadline) break
      if (!headless && Date.now() - lastLog > 15000) {
        lastLog = Date.now()
        log('   等待登录中…（还剩约 ' + Math.round((deadline - Date.now()) / 1000) + ' 秒，登录成功后会自动继续）')
      }
      await page.waitForTimeout(2000)
    }
    log('   这一轮没抓到可用令牌（共检查 ' + tried.size + ' 个候选）')
    return null
  } finally {
    try { await ctx.close() } catch (e) {}
  }
}

// 写入 config.json（保留原有字段；顺手修掉 JSON 语法错误）
function writeConfig(token) {
  let cfg = {}
  let repaired = false
  const raw = fs.existsSync(CONFIG) ? fs.readFileSync(CONFIG, 'utf8') : ''
  try {
    cfg = JSON.parse(raw)
  } catch (e) {
    if (raw.trim()) {
      repaired = true
      const m = raw.match(/"DEEPSEEK_API_KEY"\s*:\s*"([^"]+)"/)
      if (m) cfg.DEEPSEEK_API_KEY = m[1]
    }
  }
  if (!cfg || typeof cfg !== 'object' || Array.isArray(cfg)) cfg = {}
  // 注意：whale.ps1 拼请求头时会自己加 "Bearer "，所以这里存裸令牌
  cfg.DEEPSEEK_PLATFORM_TOKEN = token
  fs.mkdirSync(path.dirname(CONFIG), { recursive: true })
  fs.writeFileSync(CONFIG, JSON.stringify(cfg, null, 2) + '\n', 'utf8')
  return { repaired: repaired }
}

// 稳妥退出：直接 process.exit() 有时会让 node 在退出瞬间报一个断言错误
async function finish(code) {
  await new Promise((r) => setTimeout(r, 400))
  process.exit(code)
}

// ---------- 主流程 ----------
;(async () => {
  log('============================================================')
  log('  自动获取 DeepSeek 平台令牌')
  log('============================================================')
  log('config.json  : ' + CONFIG)
  log('浏览器配置   : ' + PROFILE_DIR)
  log('')

  // 这个专用配置目录还不存在 → 第一次用，直接开窗口让用户登录，省一轮等待
  const firstRun = !fs.existsSync(path.join(PROFILE_DIR, 'Default'))
  let res = null

  if (!firstRun) {
    log('① 后台静默尝试（复用上次的登录状态）')
    try {
      res = await grabVerified({ headless: true, waitMs: 8000, label: '后台' })
    } catch (e) {
      log('   后台打开失败：' + String(e.message).split('\n')[0])
    }
    if (res) {
      log('   ✅ 后台就拿到了可用令牌')
    } else {
      log('   ⚠️ 后台没能拿到可用令牌（多半是登录状态过期了）')
      log('')
    }
  }

  if (!res && !noVisible) {
    log('② 打开浏览器窗口')
    log('   请在弹出来的窗口里登录 https://platform.deepseek.com')
    log('   登录成功后不用做别的，脚本会自动继续（最多等 ' + LOGIN_WAIT + ' 秒）')
    log('')
    try {
      res = await grabVerified({ headless: false, waitMs: LOGIN_WAIT * 1000, label: '窗口' })
    } catch (e) {
      log('   打开窗口失败：' + String(e.message).split('\n')[0])
    }
  }

  if (!res) {
    log('')
    log('❌ 没能拿到可用令牌，config.json 没有被改动。')
    log('   常见原因：窗口里还没登录；或者登录了但页面一直没加载完。')
    log('')
    log('👉 兜底办法：在你自己常用的浏览器里登录 platform.deepseek.com，')
    log('   按 F12 → Console，粘贴同目录「抓取平台令牌.js」的内容，')
    log('   再把结果填进 config.json 的 DEEPSEEK_PLATFORM_TOKEN。')
    await finish(2)
    return
  }

  log('')
  log('③ 写入 config.json')
  const info = writeConfig(res.token)
  log('   ✅ 已写入 DEEPSEEK_PLATFORM_TOKEN（来源：' + res.where + '）' +
    (info.repaired ? '，顺带修好了原文件的 JSON 语法错误' : ''))

  // 顺手检查 API Key（余额靠它）
  try {
    const c = JSON.parse(fs.readFileSync(CONFIG, 'utf8'))
    const k = String(c.DEEPSEEK_API_KEY || '')
    if (!k || k.indexOf('替换') >= 0) {
      log('')
      log('⚠️ 提醒：config.json 里的 DEEPSEEK_API_KEY 还是空的（或还是模板文字）。')
      log('   请到 https://platform.deepseek.com 创建一个密钥填进去，否则读不到余额。')
    }
  } catch (e) {}

  log('')
  log('完成！回到挂件：菜单 → 退出挂件 → 双击 start-widget.bat 重启即可。')
  log('（挂件目录下的 run.log 里出现 usage-token=… 就说明在按真实用量显示了）')
  await finish(0)
})().catch(async (e) => {
  console.error('❌ 出错：' + (e && e.message))
  console.error('   如果提示找不到 playwright，请用 自动获取令牌.bat 运行。')
  await finish(1)
})

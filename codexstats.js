// ============================================================
// Codex 本地会话统计（只读本机 ~/.codex，不联网、不需要密钥）
//
// 数据源：$CODEX_HOME（默认 ~/.codex）
//   sessions/YYYY/MM/DD/rollout-*.jsonl
//   archived_sessions/*.jsonl
//
// 口径：优先用 total_token_usage.total_tokens 的「累计差值」，
//       分量（输入/缓存/输出/推理）按该事件的 last_token_usage 比例缩放；
//       累计缺失时退回 last_token_usage.total_tokens。
// 模型归属：type=turn_context 事件的 payload.model。
//
// 缓存：与脚本同目录的 .dshw-codex.json（只存聚合与 size/mtime，不存凭据）。
// 输出：单行 JSON 摘要。
// ============================================================

'use strict'

const fs = require('fs')
const os = require('os')
const path = require('path')

function dayKeyOf(d) {
  const p = (n) => String(n).padStart(2, '0')
  return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate())
}
function dayKeyFromTs(ts) { return dayKeyOf(new Date(Number(ts))) }
function dayAdd(base, delta) {
  const d = new Date(base + 'T00:00:00')
  d.setDate(d.getDate() + delta)
  return dayKeyOf(d)
}
function fmtNum(v) {
  if (v >= 1e9) return (v / 1e9).toFixed(1) + 'B'
  if (v >= 1e6) return (v / 1e6).toFixed(1) + 'M'
  if (v >= 1e3) return Math.round(v / 1e3) + 'K'
  return String(v)
}

function resolveHome() {
  const env = String(process.env.CODEX_HOME || '').trim()
  for (const c of [env, path.join(os.homedir(), '.codex')]) {
    try { if (c && fs.existsSync(c)) return c } catch (e) {}
  }
  return ''
}

function listFiles(root) {
  const out = []
  const walk = (dir, depth) => {
    if (depth > 8) return
    let ents = []
    try { ents = fs.readdirSync(dir, { withFileTypes: true }) } catch (e) { return }
    for (const e of ents) {
      const p = path.join(dir, e.name)
      if (e.isDirectory()) walk(p, depth + 1)
      else if (/^rollout-.*\.jsonl$/i.test(e.name)) out.push(p)
    }
  }
  walk(path.join(root, 'sessions'), 0)
  walk(path.join(root, 'archived_sessions'), 0)
  return out
}

function parseFile(file) {
  const days = {}
  let model = 'codex'
  let prevTotal = null
  let lastTurn = null
  let pendingTurn = null
  let lastRl = null
  let rlTs = 0
  let text = ''
  try { text = fs.readFileSync(file, 'utf8') } catch (e) { return { days, lastTurn: null, rl: null, rlTs: 0 } } // 被锁住的活跃会话，跳过
  const bump = (day, mk, v) => {
    days[day] = days[day] || {}
    const cur = days[day][mk] || { in: 0, cached: 0, cwrite: 0, out: 0, reason: 0, total: 0, turns: 0 }
    cur.in += v.in; cur.cached += v.cached; cur.cwrite += v.cwrite
    cur.out += v.out; cur.reason += v.reason; cur.total += v.total; cur.turns += v.turns
    days[day][mk] = cur
  }
  for (const line of text.split('\n')) {
    if (!line || line.charCodeAt(0) !== 123) continue
    let o = null
    try { o = JSON.parse(line) } catch (e) { continue }
    const p = o && o.payload
    if (!p) continue
    if (o.type === 'turn_context') {
      if (p.model) model = String(p.model)
      continue
    }
    // token_usage_record 会在一轮里流式出现多次，只暂存最近一次，等 task_complete 定稿
    if (o.type === 'token_usage_record') {
      if (p.turn_token_usage) {
        pendingTurn = { turn_id: String(p.turn_id || ''), model, usage: p.turn_token_usage }
      }
      continue
    }
    // 真正的「一轮结束」：task_complete（每轮只有一次）
    if (o.type === 'event_msg' && p.type === 'task_complete') {
      if (pendingTurn && String(p.turn_id || '') === pendingTurn.turn_id) {
        let ts = Date.parse(String(o.timestamp || '')) || 0
        if (!ts && p.completed_at) ts = Number(p.completed_at) * 1000
        if (ts && (!lastTurn || ts >= lastTurn.ts)) {
          const u = pendingTurn.usage
          lastTurn = {
          ts, model: pendingTurn.model,
          total: Number(u.total_tokens) || 0,
          in: Number(u.input_tokens) || 0,
          cached: Number(u.cached_input_tokens) || 0,
          cwrite: Number(u.cache_write_input_tokens) || 0,
          out: Number(u.output_tokens) || 0,
          reason: Number(u.reasoning_output_tokens) || 0,
        }
        }
      }
      continue
    }
    if (o.type !== 'event_msg' || p.type !== 'token_count') continue
    const info = p.info
    if (!info || typeof info !== 'object') continue
    const last = info.last_token_usage || null
    const tot = info.total_token_usage || null
    const ts = Date.parse(String(o.timestamp || '')) || 0
    if (!ts) continue
    const rl = p.rate_limits
    if (rl && typeof rl === 'object' && (rl.primary || rl.secondary || rl.plan_type || rl.credits)) {
      if (ts >= rlTs) { lastRl = rl; rlTs = ts }
    }
    const day = dayKeyFromTs(ts)
    let delta = null
    const totAll = tot ? Number(tot.total_tokens) || 0 : 0
    if (totAll > 0) {
      if (prevTotal === null || totAll < prevTotal) delta = totAll
      else delta = totAll - prevTotal
      prevTotal = totAll
    }
    if (delta === null || delta <= 0) {
      if (!last) continue
      delta = Number(last.total_tokens) || 0
    }
    if (delta <= 0) continue
    const lTotal = last ? Number(last.total_tokens) || 0 : 0
    const k = (lTotal > 0 && last) ? delta / lTotal : 0
    const v = (last && k > 0) ? {
      in: Math.round((Number(last.input_tokens) || 0) * k),
      cached: Math.round((Number(last.cached_input_tokens) || 0) * k),
      cwrite: Math.round((Number(last.cache_write_input_tokens) || 0) * k),
      out: Math.round((Number(last.output_tokens) || 0) * k),
      reason: Math.round((Number(last.reasoning_output_tokens) || 0) * k),
    } : { in: 0, cached: 0, cwrite: 0, out: 0, reason: 0 }
    bump(day, model, { in: v.in, cached: v.cached, cwrite: v.cwrite, out: v.out, reason: v.reason, total: delta, turns: 1 })
  }
  return { days, lastTurn, rl: lastRl, rlTs }
}

function normalizeWindow(w) {
  if (!w || typeof w !== 'object') return null
  const pick = (keys) => {
    for (const k of keys) {
      const raw = w[k]
      if (raw === null || raw === undefined || raw === '') continue
      const n = Number(raw)
      if (isFinite(n)) return n
    }
    return null
  }
  let usedPct = pick(['used_percent', 'usedPercent', 'percent', 'used_pct', 'usage_percent', 'usagePercent'])
  const remainPct = pick(['remaining_percent', 'remainingPercent', 'left_percent', 'remaining_pct'])
  if (usedPct === null && remainPct !== null) usedPct = Math.max(0, 100 - remainPct)
  let resetAt = null
  const secs = pick(['resets_in_seconds', 'resetsInSeconds', 'reset_after_seconds', 'reset_in_seconds', 'seconds_until_reset'])
  if (secs !== null && secs >= 0) resetAt = Date.now() + secs * 1000
  else {
    const abs = w.resets_at || w.reset_at || w.reset_time || w.next_reset || w.resetAt || w.nextResetTime
    if (typeof abs === 'number' && isFinite(abs)) resetAt = abs < 1e12 ? abs * 1000 : abs
    else if (typeof abs === 'string' && abs) { const t = Date.parse(abs); if (isFinite(t)) resetAt = t }
  }
  if (usedPct === null && resetAt === null) return null
  return { usedPct, resetAt }
}
function normalizeRateLimits(rl) {
  if (!rl || typeof rl !== 'object') return null
  const primary = normalizeWindow(rl.primary)
  const secondary = normalizeWindow(rl.secondary)
  if (!primary && !secondary) return null
  return { primary, secondary, planType: rl.plan_type ? String(rl.plan_type) : '' }
}

function main() {
  const home = process.argv[2] && fs.existsSync(process.argv[2]) ? process.argv[2] : resolveHome()
  if (!home) { console.log(JSON.stringify({ ok: false, error: '未找到 Codex 目录' })); return }

  const cachePath = path.join(__dirname, '.dshw-codex.json')
  let cache = { version: 1, files: {} }
  try {
    const c = JSON.parse(fs.readFileSync(cachePath, 'utf8'))
    if (c && c.files && typeof c.files === 'object') cache = c
  } catch (e) {}

  const files = listFiles(home)
  const keep = {}
  let changed = 0
  let bestTurn = null
  let bestRl = null
  let bestRlTs = -1
  for (const f of files) {
    let st = null
    try { st = fs.statSync(f) } catch (e) { continue }
    const prev = cache.files[f]
    if (prev && prev.size === st.size && prev.mtimeMs === st.mtimeMs && prev.days) {
      keep[f] = prev
      if (prev.lastTurn && (!bestTurn || prev.lastTurn.ts >= bestTurn.ts)) bestTurn = prev.lastTurn
      if (prev.rl && (prev.rlTs || 0) >= bestRlTs) { bestRl = prev.rl; bestRlTs = prev.rlTs || 0 }
      continue
    }
    const parsed = parseFile(f)
    keep[f] = { size: st.size, mtimeMs: st.mtimeMs, days: parsed.days, lastTurn: parsed.lastTurn, rl: parsed.rl, rlTs: parsed.rlTs }
    if (parsed.lastTurn && (!bestTurn || parsed.lastTurn.ts >= bestTurn.ts)) bestTurn = parsed.lastTurn
    if (parsed.rl && (parsed.rlTs || 0) >= bestRlTs) { bestRl = parsed.rl; bestRlTs = parsed.rlTs || 0 }
    changed++
  }
  if (changed > 0 || Object.keys(keep).length !== Object.keys(cache.files).length) {
    try { fs.writeFileSync(cachePath, JSON.stringify({ version: 1, builtAt: Date.now(), files: keep }), 'utf8') } catch (e) {}
  }

  const today = dayKeyFromTs(Date.now())
  const month = today.slice(0, 7)
  const byDay = {}
  const byModel = {}
  let totalTokens = 0, todayTokens = 0, monthTokens = 0, outTokens = 0, reasonTokens = 0, cachedTokens = 0
  for (const f of Object.keys(keep)) {
    const days = keep[f].days || {}
    for (const d of Object.keys(days)) {
      const day0 = byDay[d] || (byDay[d] = { tokens: 0, turns: 0 })
      for (const m of Object.keys(days[d])) {
        const v = days[d][m] || {}
        const tok = Number(v.total) || 0
        day0.tokens += tok
        day0.turns += Number(v.turns) || 0
        const bm = byModel[m] || (byModel[m] = { tokens: 0, out: 0, reason: 0, cached: 0, turns: 0 })
        bm.tokens += tok
        bm.out += Number(v.out) || 0
        bm.reason += Number(v.reason) || 0
        bm.cached += Number(v.cached) || 0
        bm.turns += Number(v.turns) || 0
        totalTokens += tok
        outTokens += Number(v.out) || 0
        reasonTokens += Number(v.reason) || 0
        cachedTokens += Number(v.cached) || 0
        if (d === today) todayTokens += tok
        if (d.slice(0, 7) === month) monthTokens += tok
      }
    }
  }
  const days7 = []
  for (let i = 0; i < 7; i++) {
    const d = dayAdd(today, -i)
    days7.push({ date: d, tokens: (byDay[d] && byDay[d].tokens) || 0, turns: (byDay[d] && byDay[d].turns) || 0 })
  }
  const todayTurns = (byDay[today] && byDay[today].turns) || 0

  console.log(JSON.stringify({
    ok: true,
    sessions: files.length,
    changed,
    todayTokens, monthTokens, totalTokens, outTokens, reasonTokens, cachedTokens,
    todayTurns,
    todayText: fmtNum(todayTokens), monthText: fmtNum(monthTokens), totalText: fmtNum(totalTokens),
    days7, byModel,
    lastTurn: bestTurn,
    windows: normalizeRateLimits(bestRl),
  }))
}

main()

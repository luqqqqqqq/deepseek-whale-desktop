// ============================================================
// 手动抓取 DeepSeek 平台会话令牌（DEEPSEEK_PLATFORM_TOKEN）
//
// 什么时候用它：
//   自动脚本（自动获取令牌.bat）没成功时，用这个兜底。
//
// 用法：
//   1. 用你平时的浏览器登录 https://platform.deepseek.com（保持已登录）
//   2. 按 F12 打开开发者工具，切到「Console / 控制台」
//   3. 把本文件全部内容复制粘贴进去，回车
//   4. 看到「已复制到剪贴板」后，把它粘到 config.json 里
//
// 注意：DeepSeek 平台的会话令牌不是 JWT，通常是 64 位的随机串
//       （可能带 + / = 这些字符），所以这里不能只认 eyJ 开头。
// ============================================================

(() => {
  const looksLikeToken = (v) => {
    if (typeof v !== 'string') return false
    const s = v.trim().replace(/^Bearer\s+/i, '')
    if (/^eyJ[A-Za-z0-9_-]{10,}/.test(s)) return true          // JWT 形式
    return /^[A-Za-z0-9+/=_-]{40,200}$/.test(s)                  // 平台会话令牌形式
  }

  const found = []
  const push = (where, key, value) => found.push({ where, key, value: value.trim().replace(/^Bearer\s+/i, '') })

  try {
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i)
      const v = localStorage.getItem(k)
      if (looksLikeToken(v)) push('localStorage', k, v)
    }
  } catch (e) {}

  try {
    for (let i = 0; i < sessionStorage.length; i++) {
      const k = sessionStorage.key(i)
      const v = sessionStorage.getItem(k)
      if (looksLikeToken(v)) push('sessionStorage', k, v)
    }
  } catch (e) {}

  try {
    document.cookie.split(';').forEach((c) => {
      const idx = c.indexOf('=')
      if (idx < 0) return
      const k = c.slice(0, idx).trim()
      const v = c.slice(idx + 1)
      if (looksLikeToken(v)) push('cookie', k, v)
    })
  } catch (e) {}

  // 键名像令牌的优先
  found.sort((a, b) => (/token|auth|jwt|access/i.test(b.key) ? 1 : 0) - (/token|auth|jwt|access/i.test(a.key) ? 1 : 0))

  if (!found.length) {
    console.warn('❌ 没在 localStorage / sessionStorage / cookie 里找到令牌形态的值。')
    console.log('👉 换个更准的办法：F12 → Network（网络）→ 刷新页面 →')
    console.log('   找一条 platform.deepseek.com/api/... 的请求 → 看它的 Authorization 请求头，')
    console.log('   那段（去掉开头的 Bearer ）就是令牌。')
    return
  }

  console.log('找到 ' + found.length + ' 个候选（第一个最像，但还需要验证）：')
  console.table(found.map((f) => ({ 来源: f.where, 键: f.key, 长度: f.value.length })))

  const best = found[0].value
  try {
    copy(best)
    console.log('%c✅ 已复制到剪贴板：', 'color:#0a0;font-weight:bold', found[0].where, '→', found[0].key)
  } catch (e) {
    console.log('（copy() 不可用，请手动复制下面这一行）')
  }
  console.log(best)
  console.log('\n粘到 config.json 里（注意 JSON 的逗号和引号）：')
  console.log('  "DEEPSEEK_PLATFORM_TOKEN": "' + best + '"')
})()

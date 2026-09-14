// 兜底：当 PowerShell / curl 取不到平台用量时，用 Node 取
const fs = require('fs')
const configPath = process.argv[2]
let token = ''
try { token = JSON.parse(fs.readFileSync(configPath, 'utf8')).DEEPSEEK_PLATFORM_TOKEN || '' } catch (e) {}
if (!token) { process.stderr.write('no token'); process.exit(2) }
token = String(token).replace(/^Bearer\s+/i, '')
const now = new Date()
const tz = -now.getTimezoneOffset() * 60
const start = Math.floor(new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime() / 1000)
const end = start + 86400
const url = 'https://platform.deepseek.com/api/v0/usage/by_api_key/amount?start=' + start + '&end=' + end + '&tz=' + tz
fetch(url, { headers: { Authorization: 'Bearer ' + token } })
  .then((r) => r.text())
  .then((t) => { process.stdout.write(t) })
  .catch((e) => { process.stderr.write(String((e && e.message) || e)); process.exit(1) })

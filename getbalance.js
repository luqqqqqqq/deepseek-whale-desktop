const fs = require('fs')
const configPath = process.argv[2]
let key = ''
try { key = JSON.parse(fs.readFileSync(configPath, 'utf8')).DEEPSEEK_API_KEY || '' } catch (e) {}
if (!key) { process.stderr.write('no key'); process.exit(2) }
fetch('https://api.deepseek.com/user/balance', { headers: { Authorization: 'Bearer ' + key } })
  .then((r) => r.text())
  .then((t) => { process.stdout.write(t) })
  .catch((e) => { process.stderr.write(String((e && e.message) || e)); process.exit(1) })

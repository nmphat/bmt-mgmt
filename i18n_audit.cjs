const fs = require('fs')
const path = require('path')

const root = path.resolve('src')
const msgPath = path.resolve('src/locales/messages.ts')

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name)
    if (e.isDirectory()) walk(p, out)
    else if ((p.endsWith('.ts') || p.endsWith('.vue')) && p !== msgPath) out.push(p)
  }
  return out
}

const files = walk(root)
const used = new Set()
const re = /\bt(?:\.value)?\s*\(\s*['"]([a-zA-Z0-9_.-]+)['"]/g
for (const f of files) {
  const txt = fs.readFileSync(f, 'utf8')
  let m
  while ((m = re.exec(txt))) used.add(m[1])
}

const msg = fs.readFileSync(msgPath, 'utf8')

function extractLocaleBlock(locale) {
  const start = msg.indexOf(locale + ': {')
  if (start < 0) return ''
  let i = start + (locale + ': {').length
  let depth = 1
  for (; i < msg.length; i++) {
    const ch = msg[i]
    if (ch === '{') depth++
    else if (ch === '}') depth--
    if (depth === 0) break
  }
  return msg.slice(start + (locale + ': {').length, i)
}

function extractKeysFromLocale(locale) {
  const block = extractLocaleBlock(locale)
  const keys = new Set()
  const groupRe = /^\s{4}([a-zA-Z0-9_]+):\s*\{/gm
  let g
  while ((g = groupRe.exec(block))) {
    const group = g[1]
    let i = g.index + g[0].length
    let depth = 1
    for (; i < block.length; i++) {
      const ch = block[i]
      if (ch === '{') depth++
      else if (ch === '}') depth--
      if (depth === 0) break
    }
    const grpBody = block.slice(g.index + g[0].length, i)
    const keyRe = /^\s{6}([a-zA-Z0-9_]+):\s*/gm
    let k
    while ((k = keyRe.exec(grpBody))) {
      keys.add(group + '.' + k[1])
    }
  }
  return keys
}

const viKeys = extractKeysFromLocale('vi')
const enKeys = extractKeysFromLocale('en')
const allKeys = new Set([...viKeys, ...enKeys])

const missing = [...used].filter((k) => !allKeys.has(k)).sort()
const unused = [...allKeys].filter((k) => !used.has(k)).sort()
const viOnly = [...viKeys].filter((k) => !enKeys.has(k)).sort()
const enOnly = [...enKeys].filter((k) => !viKeys.has(k)).sort()

console.log('USED_COUNT=' + used.size)
console.log('DEFINED_COUNT=' + allKeys.size)
console.log('MISSING_COUNT=' + missing.length)
console.log('UNUSED_COUNT=' + unused.length)
console.log('VI_ONLY_COUNT=' + viOnly.length)
console.log('EN_ONLY_COUNT=' + enOnly.length)

console.log('\n[MISSING]')
for (const k of missing) console.log(k)
console.log('\n[UNUSED]')
for (const k of unused) console.log(k)
console.log('\n[VI_ONLY]')
for (const k of viOnly) console.log(k)
console.log('\n[EN_ONLY]')
for (const k of enOnly) console.log(k)

// Converter for courses whose source is one hand-written HTML page: sections (h2) become modules,
// sub-sections (h3) become lessons, and the page's QA array becomes the question bank.
// Blocks are built directly (not through md()), because this text is already plain and may hold "<".
import fs from 'node:fs'
import path from 'node:path'
import vm from 'node:vm'

const VOID = new Set(['br', 'img', 'input', 'hr', 'meta', 'link', 'source', 'wbr', 'col', 'area', 'base', 'embed', 'track'])
const SKIP = new Set(['svg', 'button', 'input', 'select', 'canvas', 'nav', 'form', 'textarea', 'template', 'label', 'dialog', 'header', 'footer', 'menu', 'output', 'progress'])
const INLINE = new Set(['a', 'abbr', 'b', 'bdi', 'br', 'cite', 'code', 'dfn', 'em', 'i', 'kbd', 'mark', 'q', 's', 'samp', 'small', 'span', 'strong', 'sub', 'sup', 'time', 'u', 'var', 'wbr', 'del', 'ins'])
const NAMED = { lt: '<', gt: '>', amp: '&', quot: '"', apos: "'", nbsp: ' ', rarr: '→', larr: '←', harr: '↔', uarr: '↑', darr: '↓', mdash: '—', ndash: '–', times: '×', le: '≤', ge: '≥', ne: '≠', hellip: '…', middot: '·', bull: '•', copy: '©', check: '✓', cross: '✗', laquo: '«', raquo: '»', lsquo: '‘', rsquo: '’', ldquo: '“', rdquo: '”', deg: '°', plusmn: '±', sup2: '²', frac12: '½', thinsp: ' ', ensp: ' ', emsp: ' ', zwj: '', shy: '' }
const decode = s => s.replace(/&(#x[0-9a-f]+|#\d+|[a-z0-9]+);/gi, (m, e) => e[0] === '#' ? String.fromCodePoint(e[1].toLowerCase() === 'x' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10)) : (NAMED[e] ?? m))

/** Small tolerant HTML parser: enough for well-formed hand-written pages. */
export function parseHTML(html) {
  html = html.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>|<!--[\s\S]*?-->/gi, '')
  const root = { tag: '#root', attrs: {}, children: [] }, stack = [root]
  const re = /<\/([a-zA-Z][a-zA-Z0-9-]*)\s*>|<([a-zA-Z][a-zA-Z0-9-]*)((?:"[^"]*"|'[^']*'|[^>"'])*)>|([^<]+)|</g
  const CLOSES = { li: ['li'], p: ['p'], td: ['td', 'th'], th: ['td', 'th'], tr: ['tr', 'td', 'th'], dt: ['dt', 'dd'], dd: ['dt', 'dd'], option: ['option'] }
  let m
  while ((m = re.exec(html))) {
    const top = stack[stack.length - 1]
    if (m[1]) {
      const name = m[1].toLowerCase(), i = stack.map(n => n.tag).lastIndexOf(name)
      if (i > 0) stack.length = i
    } else if (m[2]) {
      const tag = m[2].toLowerCase(), attrs = {}
      for (const a of m[3].matchAll(/([a-zA-Z_:][-\w:.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g)) attrs[a[1].toLowerCase()] = decode(a[2] ?? a[3] ?? a[4] ?? '')
      if (CLOSES[tag] && CLOSES[tag].includes(top.tag)) stack.pop()
      if (!INLINE.has(tag) && stack[stack.length - 1].tag === 'p') stack.pop()
      const node = { tag, attrs, children: [] }
      stack[stack.length - 1].children.push(node)
      if (!VOID.has(tag) && !m[3].trimEnd().endsWith('/')) stack.push(node)
    } else top.children.push({ text: m[4] ?? '<' })
  }
  return root
}
const rawText = n => n.text !== undefined ? decode(n.text) : n.tag === 'br' ? '\n' : n.children.map(rawText).join('')
/** Inline content as the app's markup: `code`, **bold**, *italic*. */
function inline(n, inCode = false) {
  if (n.text !== undefined) return decode(n.text).replace(/\s+/g, ' ')
  if (SKIP.has(n.tag)) return ''
  if (n.tag === 'br') return ' '
  const inner = n.children.map(c => inline(c, inCode || ['code', 'kbd', 'samp'].includes(n.tag))).join('')
  if (inCode || !inner.trim()) return inner
  if (['code', 'kbd', 'samp'].includes(n.tag)) return inner.includes('`') ? inner : '`' + inner.trim() + '`'
  if (n.tag === 'b' || n.tag === 'strong') return '**' + inner.trim() + '**'
  if (n.tag === 'em' || n.tag === 'i') return '*' + inner.trim() + '*'
  return inner
}
const clean = s => s.replace(/\s+/g, ' ').trim()
const find = (n, pred, out = []) => { for (const c of n.children || []) { if (c.tag && pred(c)) out.push(c); if (c.tag) find(c, pred, out) } return out }
const hasBlockChild = n => (n.children || []).some(c => c.tag && !INLINE.has(c.tag))

/** Flattens an element into items: {h:3,text} marks a lesson boundary, the rest are content blocks. */
function flatten(n, out) {
  for (const c of n.children || []) {
    if (c.text !== undefined) { const t = clean(decode(c.text)); if (t.split(' ').length >= 6) out.push({ type: 'text', text: t }); continue }
    const t = c.tag
    if (SKIP.has(t) || c.attrs.hidden !== undefined || /\b(sr-only|visually-hidden)\b/.test(c.attrs.class || '')) continue
    if (t === 'h1' || t === 'h2') continue
    if (t === 'h3') { out.push({ h: 3, text: clean(inline(c)) }); continue }
    if (/^h[4-6]$/.test(t)) { const s = clean(inline(c)); if (s) out.push({ type: 'heading', text: s }); continue }
    if (t === 'p' || t === 'blockquote' || t === 'figcaption' || t === 'summary' || t === 'caption') {
      const s = clean(inline(c)); if (s) out.push(t === 'blockquote' ? { type: 'callout', style: 'note', title: 'Note', text: s } : { type: 'text', text: s }); continue }
    if (t === 'pre') {
      const code = rawText(c).replace(/^\n+|\s+$/g, ''), cls = (c.attrs.class || '') + ' ' + (find(c, x => x.tag === 'code')[0]?.attrs.class || '')
      const lang = c.attrs['data-lang'] || (cls.match(/(?:language-|lang-)([\w+-]+)/) || [])[1] || (cls.match(/\b(sql|sh|bash|shell|js|javascript|ts|json|yaml|yml|swift|kotlin|java|groovy|ruby|python|html|css|xml|dart|text)\b/) || [])[1] || 'text'
      if (code) out.push({ type: 'code', code, language: lang }); continue }
    if (t === 'ul' || t === 'ol') { const items = c.children.filter(x => x.tag === 'li').map(li => clean(inline(li))).filter(Boolean); if (items.length) out.push({ type: 'list', ordered: t === 'ol', items }); continue }
    if (t === 'table') {
      const rows = find(c, x => x.tag === 'tr').map(tr => tr.children.filter(x => x.tag === 'td' || x.tag === 'th').map(td => clean(inline(td)))).filter(r => r.length)
      if (rows.length > 1) { const w = Math.max(...rows.map(r => r.length)), pad = r => [...r, ...Array(w - r.length).fill('')]
        const headed = find(c, x => x.tag === 'th').length > 0
        out.push({ type: 'table', headers: headed ? pad(rows[0]) : Array(w).fill(''), rows: (headed ? rows.slice(1) : rows).map(pad) }) }
      continue }
    if (t === 'dl') { const rows = []; let dt = ''
      for (const x of c.children) { if (x.tag === 'dt') dt = clean(inline(x)); else if (x.tag === 'dd') rows.push([dt, clean(inline(x))]) }
      if (rows.length) out.push({ type: 'table', headers: ['', ''], rows }); continue }
    if (t === 'details') {
      const sum = c.children.find(x => x.tag === 'summary'), rest = []
      flatten({ children: c.children.filter(x => x !== sum) }, rest)
      const simple = rest.every(b => b.type === 'text' || b.type === 'list')
      if (sum && simple && rest.length) out.push({ type: 'callout', style: 'question', title: clean(inline(sum)), text: rest.map(b => b.type === 'text' ? b.text : b.items.join('; ')).join(' ') })
      else { if (sum) out.push({ type: 'heading', text: clean(inline(sum)) }); out.push(...rest) }
      continue }
    if (hasBlockChild(c)) flatten(c, out)
    else { const s = clean(inline(c)); if (s.split(' ').length >= 6) out.push({ type: 'text', text: s }) }
  }
}

/** An HTML fragment (or plain text) as content blocks. Loose text and inline tags are grouped into paragraphs. */
export function htmlToBlocks(html) {
  const root = parseHTML(String(html ?? ''))
  if (!hasBlockChild(root)) { const t = clean(inline(root)); return t ? [{ type: 'text', text: t }] : [] }
  const grouped = []; let run = null
  for (const c of root.children) {
    if (c.text !== undefined || INLINE.has(c.tag)) { if (!run) { run = { tag: 'p', attrs: {}, children: [] }; grouped.push(run) } run.children.push(c) }
    else { run = null; grouped.push(c) }
  }
  const out = []; flatten({ children: grouped }, out)
  return out.map(b => b.h ? { type: 'heading', text: b.text } : b)
}
export const htmlText = html => clean(inline(parseHTML(String(html ?? ''))))
export const htmlLinks = html => find(parseHTML(String(html ?? '')), n => n.tag === 'a' && /^https?:/.test(n.attrs.href || '')).map(a => ({ title: clean(inline(a)), kind: 'Link', url: a.attrs.href }))

/** Pulls `const NAME = [...]` or `{...}` out of the page script and evaluates just that literal. */
export function scriptLiteral(html, name) {
  const m = new RegExp(`(?:const\\s|let\\s|var\\s|[,;]\\s*)${name}\\s*=\\s*([\\[{])`).exec(html)
  if (!m) return null
  let i = m.index + m[0].length - 1, depth = 0, quote = null
  const start = i
  for (; i < html.length; i++) {
    const ch = html[i]
    if (quote) { if (ch === '\\') i++; else if (ch === quote) quote = null; continue }
    if (ch === '"' || ch === "'" || ch === '`') quote = ch
    else if (ch === '[' || ch === '{') depth++
    else if (ch === ']' || ch === '}') { depth--; if (depth === 0) break }
  }
  // Helper calls inside the literal (flow(...), svg(...)) are stubbed: each returns { call, args }.
  const sandbox = {}
  for (let tries = 0; tries < 12; tries++) {
    try { return JSON.parse(JSON.stringify(vm.runInNewContext('(' + html.slice(start, i + 1) + ')', sandbox))) }
    catch (e) { const m2 = /^(\w+) is not defined/.exec(e.message || ''); if (!m2) return null; const fn = m2[1]; sandbox[fn] = (...args) => ({ call: fn, args }) }
  }
  return null
}
const stripTags = s => clean(inline(parseHTML(String(s))))

export function makeHtmlBuilders({ slug, TOPICS, HOME, report }) {
  const BB = /bigbasket|bbnow|bb ?daily|bbinstant|\bbb app\b/i
  /** config: { id, file, skipSections?: RegExp, qa?: name of the script array } */
  const build = cfg => () => {
    const html = fs.readFileSync(path.join(TOPICS, cfg.file), 'utf8')
    const root = parseHTML(html)
    const sections = find(root, n => n.tag === 'section' && find(n, x => x.tag === 'h2').length > 0)
      .filter((s, _, all) => !all.some(o => o !== s && find(o, x => x === s).length)) // innermost-outermost: keep top-level ones
    const used = new Set(), modules = []
    let dropped = 0, bb = 0
    const uid = base => { let id = base || 'lesson', k = 2; while (used.has(id)) id = `${base}-${k++}`; used.add(id); return id }
    for (const s of sections) {
      const title = clean(inline(find(s, x => x.tag === 'h2')[0]))
      const sid = slug(s.attrs.id || title).replace(/^p-/, '')
      if (cfg.skipSections?.test(sid + ' ' + title)) continue
      if (cfg.onlySections && !cfg.onlySections.test(sid + ' ' + title)) continue
      const items = []; flatten(s, items)
      const lessons = []; let cur = { title, blocks: [] }
      for (const it of items) { if (it.h) { lessons.push(cur); cur = { title: it.text, blocks: [] } } else cur.blocks.push(it) }
      lessons.push(cur)
      // A sub-section with little under it (a card, a one-line tip) is kept as a heading inside the lesson before it.
      const size = l => ({ blocks: l.blocks.length, words: JSON.stringify(l.blocks).split(/\s+/).length })
      const merged = []
      for (const l of lessons) {
        const { blocks, words } = size(l), prev = merged[merged.length - 1]
        if (!blocks) { if (prev && l !== lessons[0]) prev.blocks.push({ type: 'heading', text: l.title }); continue }
        if (prev && (blocks < 2 || words < 70)) { if (l.title !== prev.title) prev.blocks.push({ type: 'heading', text: l.title }); prev.blocks.push(...l.blocks) }
        else merged.push(l)
      }
      const out = []
      for (const l of cfg.flat ? [] : merged) {
        const text = JSON.stringify(l.blocks), words = text.split(/\s+/).length
        if (words < 25) { dropped++; continue }
        if (BB.test(text) || BB.test(l.title)) { bb++; continue }
        out.push({ id: uid(`${sid}-${slug(l.title).slice(0, 40)}`), title: l.title, minutes: Math.max(3, Math.round(words / 180)), level: 0, blocks: l.blocks, quiz: [] })
      }
      if (cfg.flat) {
        const blocks = merged.flatMap((l, i) => [...(i > 0 || l.title !== title ? [{ type: 'heading', text: l.title }] : []), ...l.blocks])
        const text = JSON.stringify(blocks), words = text.split(/\s+/).length
        if (words < 40) { dropped++; continue }
        if (BB.test(text) || BB.test(title)) { bb++; continue }
        let m = modules[modules.length - 1]
        if (!m || m.lessons.length >= cfg.flat) { m = { id: `${cfg.id}-part-${modules.length + 1}`, title: `Part ${modules.length + 1}`, summary: '', tag: '', lessons: [] }; modules.push(m) }
        m.lessons.push({ id: uid(`${cfg.id}-${sid}`.slice(0, 60)), title: title.replace(/\s+L\d$/, ''), minutes: Math.max(3, Math.round(words / 180)), level: 0, blocks, quiz: [] })
        continue
      }
      if (out.length) modules.push({ id: `${cfg.id}-${sid}`, title, summary: '', tag: '', lessons: out })
    }
    const toQuiz = q => Array.isArray(q) ? { q: stripTags(q[0]), options: q[1].map(stripTags), answer: q[2], why: stripTags(q[3] || '') }
      : { q: stripTags(q.q), options: (q.o || q.options || []).map(stripTags), answer: q.a ?? q.answer ?? 0, why: stripTags(q.why || q.w || '') }
    const quizData = cfg.quiz ? scriptLiteral(html, 'QUIZ') : null
    if (quizData && !Array.isArray(quizData)) for (const [key, list] of Object.entries(quizData)) {
      const week = (key.match(/\d+/) || [])[0], m = modules.find(m => new RegExp(`^Week ${week}\\b`).test(m.title))
      if (m) m.lessons[m.lessons.length - 1].quiz = list.map(toQuiz)
    } else if (quizData?.length) modules.push({ id: `${cfg.id}-check`, title: 'Check yourself', summary: '', tag: '', lessons: [{ id: `${cfg.id}-check-yourself`, title: 'Check yourself', minutes: 10, level: 0, quiz: quizData.map(toQuiz),
      blocks: [{ type: 'text', text: `${quizData.length} questions across the whole course. Each answer comes with a short explanation.` }] }] })
    const questions = []
    const LV = scriptLiteral(html, 'LV') || {}
    const label = v => (typeof LV[v] === 'string' ? LV[v] : Array.isArray(LV[v]) ? LV[v][0] : v)
    const qa = cfg.qa === false ? null : scriptLiteral(html, cfg.qa || 'QA')
    for (const row of qa || []) {
      let topic = '', level = '', q, a
      if (Array.isArray(row)) { const strs = row.filter(x => typeof x === 'string'); if (strs.length < 2) continue; a = strs[strs.length - 1]; q = strs[strs.length - 2]; topic = strs.length > 2 ? strs[0] : ''; level = strs.length > 3 ? strs[1] : '' }
      else if (row && typeof row === 'object') { q = row.q ?? row.question; a = row.a ?? row.answer; topic = row.cat ?? row.topic ?? row.t ?? row.c ?? row.s ?? ''; level = row.level ?? row.lv ?? '' }
      if (!q || !a) continue
      q = stripTags(q); a = stripTags(a)
      if (BB.test(q + ' ' + a)) { bb++; continue }
      questions.push({ id: `q${questions.length + 1}`, topic: stripTags(String(label(topic))) || 'General', level: String(label(level)), q, a, points: [] })
    }
    if (!questions.length) for (const m of modules) for (const l of m.lessons) for (const b of l.blocks) if (b.type === 'callout' && b.style === 'question' && b.text) questions.push({ id: `q${questions.length + 1}`, topic: m.title, level: '', q: b.title, a: b.text, points: [] })
    if (cfg.flat) for (const m of modules) m.title = `${m.title}: ${m.lessons[0].title.replace(/^[\d.]+\s*·\s*/, '')} to ${m.lessons[m.lessons.length - 1].title.replace(/^[\d.]+\s*·\s*/, '')}`
    report.push(`${cfg.id}: html source; ${dropped} near-empty sub-sections skipped, ${bb} items dropped for BigBasket content`)
    return { modules, questions, resources: [] }
  }
  const CFG = [
    { id: 'git', file: 'git-github-field-guide.html', skipSections: /play|qa\b/ },
    { id: 'ide', file: 'ide-mastery-field-guide.html', skipSections: /keys|drills|qa\b/ },
    { id: 'jenkins', file: 'jenkins-mobile-cicd-guide.html', skipSections: /\bqa\b|interview/ },
    { id: 'redis-kafka', file: 'redis-kafka-field-guide.html' },
    { id: 'pwa', file: 'pwa-field-guide.html', skipSections: /\bqa\b/ },
    { id: 'flutter', file: 'flutter-handbook.html', flat: 8 },
    { id: 'claude-mastery', file: 'claude-mastery.html' },
    { id: 'fde', file: 'fde-academy.html', skipSections: /interview bank/i },
    { id: 'power-bi', file: 'power-bi-roadmap.html', skipSections: /q&a bank|\bqa\b/i, quiz: true },
    { id: 'blockchain', file: 'blockchain-academy.html', skipSections: /check yourself/i, quiz: true },
  ]
  const T = (type, text) => ({ type, text })
  const callout = (style, title, text) => ({ type: 'callout', style, title, text })

  function buildJourney() {
    const file = 'ai-engineering-journey.html', html = fs.readFileSync(path.join(TOPICS, file), 'utf8')
    const stages = scriptLiteral(html, 'STAGES') || [], lessons = scriptLiteral(html, 'LESSONS') || []
    const stage1 = build({ id: 'ai-engineer', file, onlySections: /\blearn\b/i, qa: false })()
    const codeDir = path.join(TOPICS, 'ai-engineering-journey-code')
    const questions = [], n = () => questions.length + 1
    const section = (title, v) => { const b = htmlToBlocks(v); return b.length ? [T('heading', title), ...b] : [] }
    const toLesson = l => {
      const b = [...(l.sub ? [T('text', htmlText(l.sub))] : []), ...section('The problem', l.problem), callout('tip', 'Analogy', htmlText(l.analogy)),
        ...section('Terms', l.terms), ...htmlToBlocks(l.visual), ...section('Example', l.example), ...section('Setup', l.setup)]
      for (const c of l.code || []) { const f = path.join(codeDir, c.f); if (fs.existsSync(f)) b.push({ type: 'code', code: fs.readFileSync(f, 'utf8').replace(/\s+$/, ''), language: c.f.endsWith('.py') ? 'python' : 'text', caption: c.f }) }
      b.push(...section('What the code does', l.explain), ...section('Where it fails', l.failure), ...section('Exercise', l.exercise))
      if (l.qs?.length) { b.push(T('heading', 'Check yourself')); for (const [q, a] of l.qs) { b.push(callout('question', htmlText(q), htmlText(a))); questions.push({ id: `q${n()}`, topic: `Lesson · ${l.title}`, level: '', q: htmlText(q), a: htmlText(a), points: [] }) } }
      if (l.done) b.push(callout('tip', 'Done when', htmlText(l.done)))
      const links = htmlLinks(l.res); if (links.length) b.push({ type: 'links', links })
      const words = JSON.stringify(b).split(/\s+/).length
      return { id: l.id.toLowerCase(), title: l.title, minutes: Math.max(10, Math.round(words / 150)), level: 0, blocks: b, quiz: [] }
    }
    const modules = [...stage1.modules]
    for (const st of stages) { const ls = lessons.filter(l => l.stage === st.n); if (ls.length) modules.push({ id: `ai-stage-${st.n}`, title: `Stage ${st.n} · ${st.name}`, summary: '', tag: `${st.h} hours`, lessons: ls.map(toLesson) }) }
    for (const q of scriptLiteral(html, 'IV_BANK') || []) questions.push({ id: `q${n()}`, topic: `Stage ${q.s} · ${(stages.find(s => s.n === q.s) || {}).name || ''}`, level: q.t || '', q: htmlText(q.q), a: htmlText(q.a), points: [] })
    for (const g of scriptLiteral(html, 'GLOSS') || []) questions.push({ id: `q${n()}`, topic: 'Glossary', level: '', q: `What does "${g[0]}" mean?`, a: htmlText(g[1]), points: [] })
    return { modules, questions, resources: [] }
  }

  function lanesDiagram(lanes, caption) {
    const CW = 170, CH = 84, W = 146, H = 52, PAD = 12, nodes = [], edges = []
    lanes.forEach((lane, r) => (lane.steps || []).forEach((step, c) => {
      const id = `n${nodes.length}`, hot = /^\*/.test(step)
      nodes.push({ id, label: String(step).replace(/^\*/, ''), sub: '', x: PAD + c * CW, y: PAD + r * CH, w: W, h: H, kind: 'box', hot, detail: '' })
      if (c > 0) edges.push({ from: `n${nodes.length - 2}`, to: id, label: '', dashed: false, hot: false })
      else if (r > 0) { const prevLast = nodes.filter(n => n.y === PAD + (r - 1) * CH).pop(); if (prevLast) edges.push({ from: prevLast.id, to: id, label: '', dashed: true, hot: false }) }
    }))
    if (!nodes.length) return null
    const cols = Math.max(...lanes.map(l => (l.steps || []).length))
    return { title: 'How it fits together', width: PAD * 2 + cols * CW - (CW - W), height: PAD * 2 + lanes.length * CH - (CH - H), caption: caption || '', lanes: [], nodes, edges, steps: [] }
  }

  function buildPrompt() {
    const html = fs.readFileSync(path.join(TOPICS, 'prompt-engineering-academy.html'), 'utf8')
    const L = scriptLiteral(html, 'L') || [], levels = scriptLiteral(html, 'LEVELS') || []
    const questions = [], n = () => questions.length + 1
    const code = (text, caption) => ({ type: 'code', code: String(text), language: 'text', caption })
    const toLesson = l => {
      const b = [T('text', htmlText(l.lede)), ...htmlToBlocks(l.body)]
      if (l.diagram?.call === 'flow') { const d = lanesDiagram(l.diagram.args[0] || [], htmlText(l.diagram.args[1] || '')); if (d) b.push({ type: 'diagram', diagram: d }) }
      b.push(T('heading', 'Weak prompt'), code(l.weak, 'Weak'), T('heading', 'Strong prompt'), code(l.strong, 'Strong'), T('heading', 'What changed'), { type: 'list', ordered: false, items: l.changed.map(htmlText) },
        T('heading', 'Your turn'), T('text', htmlText(l.task)), code(l.messy, 'Rewrite this prompt'), T('heading', 'A good rewrite does this'), { type: 'list', ordered: false, items: l.rubric.map(htmlText) },
        T('heading', 'Model answer'), T('text', 'Try your own rewrite first, then compare.'), code(l.model, 'Model answer'))
      if (l.qa?.length) { b.push(T('heading', 'Questions')); for (const [q, a] of l.qa) { b.push(callout('question', htmlText(q), htmlText(a))); questions.push({ id: `q${n()}`, topic: l.title, level: levels[l.level] || '', q: htmlText(q), a: htmlText(a), points: [] }) } }
      return { id: `pe-${l.id}`, title: l.title, minutes: 20, level: l.level + 1, blocks: b, quiz: [] }
    }
    const modules = levels.map((name, i) => ({ id: `pe-level-${i + 1}`, title: name, summary: '', tag: `Level ${i + 1}`, lessons: L.filter(l => l.level === i).map(toLesson) })).filter(m => m.lessons.length)
    const capstone = scriptLiteral(html, 'CAP') || [], debug = scriptLiteral(html, 'DEBUG_ROWS') || []
    const extra = []
    if (capstone.length) extra.push({ id: 'pe-capstone', title: 'Capstone project', minutes: 60, level: 0, quiz: [], blocks: capstone.flatMap((c, i) => [T('heading', `Stage ${i + 1}: ${c[0]}`), T('text', htmlText(c[1])), { type: 'list', ordered: false, items: (c[2] || []).map(htmlText) }, ...(c[3] ? [callout('note', 'Uses', htmlText(c[3]))] : [])]) })
    if (debug.length) extra.push({ id: 'pe-debugging', title: 'Debugging a prompt', minutes: 10, level: 0, quiz: [], blocks: [T('text', 'Find the symptom, read the likely cause, apply the fix.'), { type: 'table', headers: ['Symptom', 'Likely cause', 'Fix'], rows: debug.map(r => r.map(htmlText)) }] })
    if (extra.length) modules.push({ id: 'pe-practice', title: 'Capstone and reference', summary: '', tag: '', lessons: extra })
    for (const [q, a] of scriptLiteral(html, 'EXTRA_QA') || []) questions.push({ id: `q${n()}`, topic: 'General', level: '', q: htmlText(q), a: htmlText(a), points: [] })
    return { modules, questions, resources: [] }
  }

  function buildAITools() {
    const src = fs.readFileSync(path.join(HOME, 'Documents/BIGBASKET_BB_APP/ai-tools-guide/dist/data.js'), 'utf8')
    const ctx = {}; vm.createContext(ctx); vm.runInContext(src + ';this.o={TOOLS,WORKFLOWS,PATHS,SKILLS,CATEGORIES,CHECKED}', ctx)
    const o = JSON.parse(JSON.stringify(ctx.o)), ok = v => !BBX.test(JSON.stringify(v))
    const list = items => ({ type: 'list', ordered: false, items })
    const toolLessons = o.CATEGORIES.map(cat => ({ cat, tools: o.TOOLS.filter(t => t.category === cat && ok(t)) })).filter(g => g.tools.length).map(g => ({
      id: `tools-${slug(g.cat)}`, title: `${g.cat} tools`, minutes: 5 * g.tools.length, level: 0, quiz: [],
      blocks: [T('text', `Prices and limits were checked on ${o.CHECKED}; confirm them on each tool's own page before you rely on them.`), ...g.tools.flatMap(t => [T('heading', t.name), T('text', `${t.type}. ${t.blurb}`),
        { type: 'table', headers: ['', ''], rows: [['Price', t.price], ['Limit', t.limit || ''], ['Works with', t.integration || ''], ['Privacy', t.privacy || '']].filter(r => r[1]) },
        ...(t.uses?.length ? [list(t.uses)] : []), ...(t.prompt ? [{ type: 'code', code: t.prompt, language: 'text', caption: 'Prompt to try' }] : []),
        { type: 'links', links: [{ title: t.name, kind: 'Pricing and docs', url: t.url }] }])],
    }))
    const flowLessons = o.WORKFLOWS.filter(ok).map(w => ({ id: `flow-${w.id}`, title: w.title, minutes: 10, level: 0, quiz: [], blocks: [
      { type: 'table', headers: ['', ''], rows: [['Area', w.category], ['Tools', (w.tools || []).join(', ')], ['Give it', w.context || '']].filter(r => r[1]) },
      T('heading', 'Steps'), { type: 'list', ordered: true, items: w.steps || [] }, ...(w.prompt ? [{ type: 'code', code: w.prompt, language: 'text', caption: 'Prompt' }] : []),
      ...Object.entries(w).filter(([k, v]) => !['id', 'title', 'category', 'tools', 'context', 'steps', 'prompt'].includes(k) && typeof v === 'string' && v).map(([k, v]) => callout('note', k[0].toUpperCase() + k.slice(1), v)) ] }))
    const pathLessons = (Array.isArray(o.PATHS) ? o.PATHS : Object.values(o.PATHS)).filter(ok).map(p2 => ({ id: `path-${slug(p2.name)}`, title: `Path: ${p2.name}`, minutes: 10, level: 0, quiz: [], blocks: [T('text', p2.description),
      { type: 'table', headers: ['Week', 'Focus', 'Do', 'Deliverable'], rows: (p2.weeks || []).map((w, i) => [String(i + 1), w[0], w[1], w[2]]) }] }))
    const skills = { id: 'skills', title: 'Which kind of tool for which job', minutes: 8, level: 0, quiz: [], blocks: [{ type: 'table', headers: ['Kind of tool', 'Use it for', 'Try'], rows: o.SKILLS }] }
    report.push(`ai-tools: ${o.TOOLS.length - toolLessons.reduce((n, l) => n + (l.minutes / 5), 0)} tools and ${o.WORKFLOWS.length - flowLessons.length} workflows dropped for BigBasket content`)
    return { modules: [{ id: 'ai-tools-start', title: 'Start here', summary: '', tag: '', lessons: [skills] }, { id: 'ai-tools-tools', title: 'Tools by area', summary: '', tag: '', lessons: toolLessons },
      { id: 'ai-tools-flows', title: 'Workflows', summary: '', tag: '', lessons: flowLessons }, { id: 'ai-tools-paths', title: 'Learning paths', summary: '', tag: '', lessons: pathLessons }].filter(m => m.lessons.length), questions: [], resources: [] }
  }
  const BBX = /bigbasket|bbnow|bb ?daily|bbinstant/i

  function buildMobileDesign() {
    const html = fs.readFileSync(path.join(TOPICS, 'mobile-design-academy.html'), 'utf8')
    const mods = scriptLiteral(html, 'MODS') || [], stages = scriptLiteral(html, 'STAGES') || [], rm = scriptLiteral(html, 'RM') || [], iq = scriptLiteral(html, 'IQ') || []
    const lessonOf = m => {
      const road = rm.filter(r => r[3] === m[4])
      const b = [T('text', 'What this module covers:'), { type: 'list', ordered: false, items: String(m[5] || '').split(';').map(x => x.trim()).filter(Boolean) }]
      for (const r of road) b.push(T('heading', r[0]), callout('tip', 'Practise', r[1]), callout('note', 'Read', r[2]))
      b.push(callout('note', 'Interactive version', 'The worked screens and exercises for this module are in the original interactive course, which this app links to from the course page.'))
      return { id: `md-${m[0]}-${slug(m[1])}`.slice(0, 60), title: m[1], minutes: 10, level: 0, blocks: b, quiz: [] }
    }
    const modules = stages.map((name, i) => ({ id: `md-stage-${i + 1}`, title: String(name), summary: '', tag: `Stage ${i + 1}`, lessons: mods.filter(m => m[2] === i).map(lessonOf) })).filter(m => m.lessons.length)
    const questions = iq.map((r, i) => ({ id: `q${i + 1}`, topic: r[0], level: '', q: htmlText(r[1]), a: htmlText(r[2]), points: r[3] ? [{ title: 'Follow-up', items: [htmlText(r[3])] }] : [] }))
    return { modules, questions, resources: [] }
  }

  function buildFullStackAI() {
    const D = scriptLiteral(fs.readFileSync(path.join(TOPICS, 'mastering-ai.html'), 'utf8'), 'DATA')
    const questions = [], n = () => questions.length + 1
    const deepBlocks = deep => (deep || []).flatMap(d => {
      switch (d.k) {
        case 'h': return [T('heading', d.t)]
        case 'p': return [T('text', d.t)]
        case 'table': return d.rows?.length > 1 ? [{ type: 'table', headers: d.rows[0], rows: d.rows.slice(1) }] : []
        case 'code': case 'pre': { const code = d.src ?? d.code ?? d.t ?? ''; return code ? [{ type: 'code', code: String(code), language: d.lang || (d.k === 'code' ? 'python' : 'text'), ...(d.cap || d.file ? { caption: d.cap || d.file } : {}) }] : [] }
        case 'ul': { const items = d.items ?? d.li ?? d.t; return Array.isArray(items) ? [{ type: 'list', ordered: false, items }] : [] }
        case 'qa': return d.q && d.a ? [callout('question', d.q, d.a)] : []
        default: return []
      }
    })
    const modules = D.modules.map(m => {
      const lessons = m.topics.map(t => {
        const b = [T('text', t.w), T('heading', 'How it behaves'), T('text', t.h), callout('warn', 'Pitfall', t.p)]
        if (t.f) b.push(callout('note', 'Flow', t.f.split(/\s*>\s*/).join(' → ')))
        if (t.q && t.a) { b.push(callout('question', t.q, t.a)); questions.push({ id: `q${n()}`, topic: `${m.id} · ${m.title}`, level: m.band, q: t.q, a: t.a, points: [] }) }
        return { id: `${m.id}-${t.num}-${slug(t.n)}`.toLowerCase(), title: t.n, minutes: 8, level: 0, blocks: b, quiz: [] }
      })
      const deep = deepBlocks(m.deep)
      if (deep.length) lessons.push({ id: `${m.id}-deep`.toLowerCase(), title: deep[0].type === 'heading' ? deep[0].text : `${m.title}: go deeper`, minutes: Math.max(10, Math.round(JSON.stringify(deep).split(/\s+/).length / 150)), level: 0, blocks: deep, quiz: [] })
      const build2 = [T('text', m.build), ...(m.code || []).flatMap(c => [T('heading', c.cap || c.file), { type: 'code', code: c.src, language: 'python', caption: c.file }])]
      for (const x of m.xq || []) { build2.push(callout('question', x.q, x.a)); questions.push({ id: `q${n()}`, topic: `${m.id} · ${m.title}`, level: cap(x.type || ''), q: x.q, a: x.a, points: [] }) }
      lessons.push({ id: `${m.id}-build`.toLowerCase(), title: `${m.title}: build and practise`, minutes: 30, level: 0, blocks: build2, quiz: [] })
      return { id: `fsai-${m.id}`.toLowerCase(), title: `${m.id} · ${m.title}`, summary: m.intro, tag: m.band, lessons }
    })
    return { modules, questions, resources: [] }
  }
  const cap = s => s ? s[0].toUpperCase() + s.slice(1) : s

  return { ...Object.fromEntries(CFG.map(c => [c.id, build(c)])), 'ai-engineer': buildJourney, 'fullstack-ai': buildFullStackAI, 'prompt-engineering': buildPrompt, 'ai-tools': buildAITools, 'mobile-design': buildMobileDesign }
}

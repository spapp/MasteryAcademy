// Converters for courses 4+ (see spec/courses.json). Each returns { modules, questions, resources }.
// Imported by build_content.mjs, which passes its helpers in.
import fs from 'node:fs'
import path from 'node:path'
import vm from 'node:vm'
import { createRequire } from 'node:module'

export function makeBuilders({ B, slug, TOPICS, HOME, report }) {
  const LEVEL = { layman: 1, beginner: 1, basic: 1, intermediate: 2, advanced: 3, expert: 4 }
  const levelOf = v => typeof v === 'number' ? v : (LEVEL[String(v || '').toLowerCase()] ?? (parseInt(v, 10) || 0))
  const cap = s => s ? s[0].toUpperCase() + s.slice(1) : s

  // ---------- TypeScript project loader (uses the project's own `typescript` package) ----------
  function tsProject(root) {
    const ts = createRequire(path.join(root, 'package.json'))('typescript')
    const cache = new Map()
    const resolve = (from, spec) => {
      const base = path.resolve(path.dirname(from), spec)
      for (const c of [base, base + '.ts', base + '.tsx', path.join(base, 'index.ts')]) if (fs.existsSync(c) && fs.statSync(c).isFile()) return c
      return null
    }
    const load = file => {
      if (cache.has(file)) return cache.get(file).exports
      const mod = { exports: {} }
      cache.set(file, mod)
      const js = ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, jsx: ts.JsxEmit.React } }).outputText
      const req = spec => {
        if (spec.endsWith('?raw')) { const f = path.resolve(path.dirname(file), spec.slice(0, -4)); return { default: fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : '' } }
        if (!spec.startsWith('.')) return new Proxy({}, { get: () => () => null }) // react and friends: never called for data
        const target = resolve(file, spec)
        if (!target || !/\.tsx?$/.test(target)) return {}
        return load(target)
      }
      vm.runInNewContext(`(function (exports, require, module) {${js}\n})`, { console })(mod.exports, req, mod)
      return mod.exports
    }
    return { load: rel => load(path.join(root, rel)), plain: v => JSON.parse(JSON.stringify(v)) }
  }

  // ---------- text-file course format (python-node, sql) ----------
  /** Paragraphs and "- " runs of a text body become text and list blocks. */
  function proseBlocks(text) {
    const out = []
    for (const para of String(text).split(/\n\s*\n/)) {
      const lines = para.split('\n').filter(l => l.trim())
      if (!lines.length) continue
      if (lines.every(l => /^\s*- /.test(l))) out.push(B.list(lines.map(l => l.replace(/^\s*- /, ''))))
      else out.push(B.text(lines.join(' ')))
    }
    return out
  }
  /** "A -> B -[label]-> C" lanes become a diagram; a node named in an earlier lane is reused, which draws a branch. */
  function flowDiagram(title, lines) {
    const CW = 160, CH = 84, W = 136, H = 52, PAD = 12
    const nodes = new Map(), edges = [], lanes = []
    let row = 0
    for (let l of lines) {
      if (!l.trim()) continue
      let laneName = ''
      if (l.includes(' :: ')) { const i = l.indexOf(' :: '); laneName = l.slice(0, i).trim().replace(/^[*!]+/, ''); l = l.slice(i + 4) }
      const pieces = l.trim().split(/\s+(->|-\[[^\]]*\]->)\s+/)
      let prev = null, col = 0, label = ''
      for (const piece of pieces) {
        if (piece === '->') { label = ''; continue }
        if (piece.startsWith('-[')) { label = piece.slice(2, -3); continue }
        const hot = /^[*!]/.test(piece), name = piece.replace(/^[*!]+/, '').trim()
        if (!name) continue
        let node = nodes.get(name)
        if (!node) {
          while ([...nodes.values()].some(n => n.col === col && n.row === row)) col++
          node = { id: 'n' + nodes.size, label: name, col, row, hot }
          nodes.set(name, node)
        }
        if (prev) edges.push({ from: prev.id, to: node.id, label, dashed: false, hot: false })
        prev = node; col = node.row === row ? node.col + 1 : node.col + 1; label = ''
      }
      if (laneName) lanes.push({ y: PAD + row * CH - 6, h: H + 12, label: laneName })
      row++
    }
    const list = [...nodes.values()]
    if (!list.length) return null
    const cols = Math.max(...list.map(n => n.col)) + 1, rows = Math.max(...list.map(n => n.row)) + 1
    return {
      title: title || 'Flow', width: PAD * 2 + cols * CW - (CW - W), height: PAD * 2 + rows * CH - (CH - H), caption: '', lanes,
      nodes: list.map(n => ({ id: n.id, label: n.label, sub: '', x: PAD + n.col * CW, y: PAD + n.row * CH, w: W, h: H, kind: 'box', hot: n.hot, detail: '' })),
      edges, steps: [],
    }
  }
  function txtBlock(kind, title, lines, ctx) {
    while (lines.length && !lines[lines.length - 1].trim()) lines.pop()
    while (lines.length && !lines[0].trim()) lines.shift()
    const body = lines.join('\n'), out = []
    const head = t => { if (t) out.push(B.heading(t)) }
    switch (kind) {
      case 'plain': head(title); out.push(...proseBlocks(body)); break
      case 'h': out.push(B.heading(title)); break
      case 'analogy': out.push(B.callout('tip', title || 'Analogy', body.replace(/\n+/g, ' '))); break
      case 'bridge': out.push(B.callout('note', title || 'From the app side', body.replace(/\n+/g, ' '))); break
      case 'real': out.push(B.callout('note', title || 'Real example', body.replace(/\n+/g, ' '))); break
      case 'deep': out.push(B.heading(title || 'Go deeper')); out.push(...proseBlocks(body)); break
      case 'use':
        for (const l of lines) { const m = l.match(/^(Backend|AI):\s*(.*)$/); if (m) out.push(B.callout('note', m[1] === 'AI' ? 'In AI work' : 'In backend work', m[2])) }
        break
      case 'code': { const bits = title.split(' '), lang = bits[0] || 'text'; const FLAGS = ['run', 'vrun', 'nrun', 'tcheck', 'mypy']
        out.push(B.code(body, lang === 'js' ? 'javascript' : lang, bits.slice(1).filter(b => !FLAGS.includes(b)).join(' ') || undefined)); break }
      case 'sql': case 'pg': case 'show': out.push(B.code(body, 'sql', title || undefined)); break
      case 'pgsteps': out.push(B.code(lines.map(l => l.startsWith('--- ') ? '-- ' + l.slice(4) : l.startsWith('> ') ? '-- result: ' + l.slice(2) : l).join('\n'), 'sql', title || undefined)); break
      case 'lanes': head(title); out.push(B.table(['Session', 'Statement or note'], lines.filter(l => l.trim()).map(l => l.startsWith('#') ? ['', '*' + l.slice(1).trim() + '*'] : (m => m ? [m[1], '`' + m[2] + '`'] : ['', l])(l.match(/^([A-Z]):\s*(.*)$/))))); break
      case 'pitfalls': out.push(B.heading(title || 'Pitfalls')); out.push(B.list(lines.filter(l => l.startsWith('- ')).map(l => l.slice(2)))); break
      case 'table': { const rows = lines.filter(l => l.trim()).map(l => l.split(' | ').map(c => c.trim())); head(title); if (rows.length > 1) out.push(B.table(rows[0], rows.slice(1))); break }
      case 'flow': { const d = flowDiagram(title, lines); if (d) out.push(B.diagram(d)); break }
      case 'steps': { const rows = lines.filter(l => l.trim()).map(l => l.split(' || '))
        if (rows.length) { const heads = rows[0].slice(1).map(p => p.split(':')[0].trim()); head(title)
          out.push(B.table(['Step', ...heads], rows.map(r => [r[0].trim(), ...r.slice(1).map(p => p.slice(p.indexOf(':') + 1).trim())]))) }
        break }
      case 'quiz':
        out.push(B.heading(title || 'Check yourself'))
        if (lines.some(l => l.startsWith('Q: '))) {
          let q = null
          for (const l of lines) { if (l.startsWith('Q: ')) q = l.slice(3).trim(); else if (l.startsWith('A: ') && q) { const a = l.slice(3).trim(); out.push(B.callout('question', q, a)); ctx.qa.push([q, a]); q = null } }
        } else for (const l of lines) { if (!l.includes(' | ')) continue; const i = l.indexOf(' | '), q = l.slice(0, i).trim(), a = l.slice(i + 3).trim()
          out.push(B.callout('question', q, a)); ctx.qa.push([q, a]) }
        break
      case 'problem': { const m = title.match(/^(Easy|Medium|Hard)\s+(.*)$/), cut = lines.findIndex(l => l.trim() === '---')
        out.push(B.heading(`Problem${m ? ` (${m[1]})` : ''}: ${m ? m[2] : title}`))
        out.push(...proseBlocks(lines.slice(0, cut < 0 ? lines.length : cut).join('\n')))
        if (cut >= 0) out.push(B.code(lines.slice(cut + 1).join('\n').trim(), 'sql', 'Solution'))
        break }
      case 'svg': { const cap2 = title.split(' ').slice(1).join(' '); if (cap2) out.push(B.callout('note', 'Diagram in the interactive version', cap2)); break }
      case 'lab': out.push(B.callout('note', 'Interactive lab', title.split(' ').slice(1).join(' ') + ' Open the simulators page to use it.')); break
      default: ctx.unknown.add(kind)
    }
    return out
  }
  /** Parses the "#track / #stage / ### / === / +++ / :: kind" format into modules. */
  function parseTxt(text, courseId) {
    const modules = [], questions = [], unknown = new Set(), byId = new Map()
    let trackName = '', module = null, lesson = null, block = null, n = 0
    const flush = () => { if (block && lesson) lesson.blocks.push(...txtBlock(block.kind, block.title, block.lines, lesson._ctx)); block = null }
    const newModule = (title, summary, tag) => { flush(); module = { id: `${courseId}-m${modules.length + 1}`, title, summary: summary || '', tag: tag || '', lessons: [] }; modules.push(module) }
    for (const raw of text.split('\n')) {
      const line = raw.replace(/\s+$/, '')
      if (line.startsWith('#track ')) { flush(); trackName = line.slice(7).split('|')[1].trim() }
      else if (line.startsWith('#stage ')) { const [name, sub] = line.slice(7).split('|').map(x => x.trim()); newModule(trackName ? `${trackName}: ${name}` : name, sub, trackName) }
      else if (line.startsWith('### ')) { const [, title, blurb] = line.slice(4).split('|').map(x => x.trim()); newModule(title, blurb, 'Track') }
      else if (line.startsWith('=== ')) {
        flush()
        const [id, title, level, mins] = line.slice(4).split('|').map(x => x.trim())
        lesson = { id, title, minutes: parseInt(mins, 10) || 20, level: levelOf(level), blocks: [], quiz: [], _ctx: { qa: [], unknown } }
        byId.set(id, lesson); module.lessons.push(lesson)
      } else if (line.startsWith('+++ ')) { flush(); lesson = byId.get(line.slice(4).trim()) || lesson }
      else if (line.startsWith(':: ')) { flush(); const sp = line.indexOf(' ', 3); block = { kind: sp < 0 ? line.slice(3) : line.slice(3, sp), title: sp < 0 ? '' : line.slice(sp + 1).trim(), lines: [] } }
      else if (block) block.lines.push(raw)
    }
    flush()
    for (const m of modules) for (const l of m.lessons) {
      l._ctx.qa.forEach(([q, a]) => questions.push({ id: `${l.id}-q${++n}`, topic: m.title, level: '', q, a, points: [] }))
      delete l._ctx
    }
    if (unknown.size) report.push(`${courseId}: block kinds not converted: ${[...unknown].join(', ')}`)
    return { modules: modules.filter(m => m.lessons.length), questions }
  }
  const readTxt = (dir, order) => order.map(f => fs.readFileSync(path.join(dir, f), 'utf8')).join('\n')

  function buildPythonNode() {
    const dir = path.join(TOPICS, 'python-node-academy-build/content')
    const files = fs.readdirSync(dir).filter(f => f.endsWith('.txt')).sort()
    // Same order as build.py: Python track, Node track, then the side-by-side track.
    const order = ['py', 'node', 'both'].flatMap(p => files.filter(f => f.startsWith(p)))
    return { ...parseTxt(readTxt(dir, order), 'pn'), resources: [] }
  }
  function buildSQL() {
    const dir = path.join(TOPICS, 'sql-academy-build/content')
    return { ...parseTxt(readTxt(dir, fs.readdirSync(dir).filter(f => f.endsWith('.txt')).sort()), 'sql'), resources: [] }
  }

  // ---------- DevOps (TypeScript content) ----------
  function commandBlocks(c) {
    if (typeof c === 'string') return [B.code(c, 'sh')]
    const RISK = { safe: 'Safe, read-only', local: 'Changes the local environment', prod: 'Production change', destructive: 'Destructive, high risk' }
    const out = [B.code(c.cmd, 'sh', RISK[c.risk] || c.risk), B.text(c.what)]
    if (c.flags?.length) out.push(B.table(['Flag', 'Meaning'], c.flags.map(f => ['`' + f[0] + '`', f[1]])))
    if (c.output) out.push(B.code(c.output, 'text', 'Expected output'))
    if (c.verify) out.push(B.callout('tip', 'Verify', c.verify))
    if (c.errors) out.push(B.callout('warn', 'Common errors', c.errors))
    return out
  }
  const textOrCode = (label, v) => !v ? [] : [B.heading(label), ...(v.includes('\n') ? [B.code(v, 'text')] : [B.text(v)])]
  function buildDevOps() {
    const root = path.join(HOME, 'Documents/devops-mastery-academy'), p = tsProject(root)
    const mods = p.plain(p.load('src/metadata/modules.ts').MODULES)
    const lessons = []
    const walk = d => { for (const f of fs.readdirSync(d).sort()) { const full = path.join(d, f)
      if (fs.statSync(full).isDirectory()) walk(full)
      else if (f.endsWith('.ts')) for (const v of Object.values(p.load(path.relative(root, full)))) if (Array.isArray(v) && v[0]?.id && v[0]?.module && v[0]?.simple) lessons.push(...p.plain(v)) } }
    walk(path.join(root, 'src/knowledge'))
    const seen = new Set(), unique = lessons.filter(l => !seen.has(l.id) && seen.add(l.id))
    const questions = []
    const toLesson = l => {
      const b = [B.text(l.simple), B.callout('tip', 'Analogy', l.analogy), B.heading('Why it matters'), B.text(l.why), B.heading('Where you meet it'), B.text(l.where), B.heading('Scenario'), B.text(l.scenario),
        ...textOrCode('Architecture', l.architecture), ...textOrCode('Flow', l.flow)]
      if (l.commands?.length) { b.push(B.heading('Commands')); l.commands.forEach(c => b.push(...commandBlocks(c))) }
      if (l.config) { b.push(B.heading(l.config.title || 'Configuration')); b.push(B.code(l.config.code, l.config.lang)); if (l.config.notes) b.push(B.text(l.config.notes)) }
      if (l.exercise) { b.push(B.heading('Exercise')); b.push(B.text(l.exercise.goal)); b.push(B.list(l.exercise.steps, true)); b.push(B.callout('tip', 'Verify', l.exercise.verify)) }
      if (l.troubleshooting?.length) { b.push(B.heading('Troubleshooting')); b.push(B.table(['Symptom', 'Cause', 'Fix'], l.troubleshooting.map(t => [t.symptom, t.cause, t.fix]))) }
      if (l.bestPractices?.length) { b.push(B.heading('Best practices')); b.push(B.list(l.bestPractices)) }
      if (l.security?.length) { b.push(B.heading('Security')); b.push(B.list(l.security)) }
      if (l.interview?.length) { b.push(B.heading('Interview questions')); l.interview.forEach((q, i) => { b.push(B.callout('question', q.q, q.a)); questions.push({ id: `${l.id}-i${i + 1}`, topic: `Lesson · ${l.title}`, level: cap(l.level), q: q.q, a: q.a, points: [] }) }) }
      if (l.sim) b.push(B.callout('note', 'Simulator', 'This lesson has a simulator in the interactive version of the course.'))
      return { id: l.id, title: l.title, minutes: l.minutes, level: levelOf(l.level), blocks: b, quiz: (l.quiz || []).map(q => ({ q: q.q, options: q.options, answer: q.answer, why: q.why })) }
    }
    const modules = mods.map(m => ({ id: 'devops-' + m.slug, title: m.title, summary: m.blurb, tag: `Phase ${m.phase}`, lessons: unique.filter(l => l.module === m.slug).map(toLesson) })).filter(m => m.lessons.length)
    const placed = new Set(modules.flatMap(m => m.lessons.map(l => l.id))), rest = unique.filter(l => !placed.has(l.id))
    if (rest.length) modules.push({ id: 'devops-more', title: 'More lessons', summary: '', tag: '', lessons: rest.map(toLesson) })
    p.plain(p.load('src/metadata/interview.ts').QUESTIONS).forEach((q, i) => questions.push({
      id: `bank-${i + 1}`, topic: q.cat, level: cap(q.level), q: q.q, a: q.a,
      points: [['Follow-ups', q.followups], ['Common mistakes', [q.mistakes]], ['What a senior answer adds', [q.senior]]].filter(([, it]) => it && it.length && it[0]).map(([title, items]) => ({ title, items })),
    }))
    return { modules, questions, resources: [] }
  }

  // ---------- Android, Java & Kotlin (TypeScript content) ----------
  function buildAndroid() {
    const root = path.join(HOME, 'android-mastery-academy'), p = tsProject(root)
    const idx = p.load('src/knowledge/index.ts')
    const lessons = p.plain(idx.lessons), qs = p.plain(idx.questions), mods = p.plain(p.load('src/metadata/modules.ts').modules)
    const LANG = { Java: 'java', Kotlin: 'kotlin', XML: 'xml' }
    const toLesson = l => {
      const b = [...(l.simple || []).map(B.text), B.heading('Why it matters'), B.text(l.why), B.callout('tip', 'Analogy', l.analogy)]
      if (l.compare?.length) { b.push(B.heading('If you know iOS or Flutter')); b.push(B.table(['Coming from', 'How it maps'], l.compare.map(c => [c.platform, c.text]))) }
      if (l.flow?.steps?.length) { b.push(B.heading(l.flow.title || 'Flow')); b.push(B.list(l.flow.steps, true)) }
      if (l.code?.java) b.push(B.code(l.code.java, 'java', 'Java'))
      if (l.code?.kotlin) b.push(B.code(l.code.kotlin, 'kotlin', 'Kotlin'))
      if (l.code?.note) b.push(B.text(l.code.note))
      for (const e of l.extraCode || []) { b.push(B.heading(e.title))
        for (const k of ['java', 'kotlin', 'xml']) if (e[k]) b.push(B.code(e[k], k, e.file || cap(k)))
        if (e.note) b.push(B.text(e.note)) }
      if (l.walkthrough?.length) { b.push(B.heading('Walkthrough')); for (const w of l.walkthrough) { b.push(B.code(w.code, LANG[w.lang] || 'text', w.lang)); b.push(B.text(w.note)) } }
      for (const [title, items] of [['What happens when it runs', l.execution], ['Memory', l.memory], ['Debugging', l.debugging], ['In production', l.production], ['On the backend', l.backend]]) if (items?.length) { b.push(B.heading(title)); b.push(B.list(items)) }
      if (l.mistakes?.length) { b.push(B.heading('Common mistakes')); b.push(B.table(['Mistake', 'Fix'], l.mistakes.map(m => [m.bad, m.fix]))) }
      if (l.exercises?.length) { b.push(B.heading('Exercises')); l.exercises.forEach(e => b.push(B.callout('question', e.task, e.hint ? 'Hint: ' + e.hint : ''))) }
      if (l.interview?.length) { b.push(B.heading('Interview questions')); l.interview.forEach(q => b.push(B.callout('question', q.q, q.a))) }
      return { id: l.id, title: l.title, minutes: l.minutes, level: levelOf(l.level), blocks: b, quiz: (l.quiz || []).map(q => ({ q: q.q, options: q.options, answer: q.answer, why: q.why })) }
    }
    const modules = mods.map(m => ({ id: 'android-m' + m.id, title: m.title || m.name || `Module ${m.id}`, summary: m.blurb || m.summary || m.description || '', tag: '', lessons: lessons.filter(l => l.moduleId === m.id).map(toLesson) })).filter(m => m.lessons.length)
    const placed = new Set(modules.flatMap(m => m.lessons.map(l => l.id))), rest = lessons.filter(l => !placed.has(l.id))
    if (rest.length) modules.push({ id: 'android-more', title: 'More lessons', summary: '', tag: '', lessons: rest.map(toLesson) })
    const questions = qs.map((q, i) => ({ id: 'aq' + (i + 1), topic: q.category, level: '', q: q.q, a: q.a,
      points: [['Follow-up', [q.followUp]], ['What a senior answer adds', [q.senior]]].filter(([, it]) => it[0]).map(([title, items]) => ({ title, items })) }))
    return { modules, questions, resources: [] }
  }

  return { 'python-node': buildPythonNode, 'sql': buildSQL, 'devops': buildDevOps, 'android': buildAndroid }
}

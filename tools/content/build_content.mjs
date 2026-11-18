#!/usr/bin/env node
// Converts the course sources into the app's content schema (see kb/00-core/04-content-schema.md).
// Usage: node tools/content/build_content.mjs [--topics ~/ai-handoff/topics] [--sysdesign ~/Documents/system-design-academy]
// Output: content/build/catalog.json, course-<id>.json, web-<id>.html. Never edit files in content/build by hand.
import fs from 'node:fs'
import path from 'node:path'
import vm from 'node:vm'
import crypto from 'node:crypto'
import os from 'node:os'
import { fileURLToPath } from 'node:url'
import { makeBuilders } from './more_courses.mjs'
import { makeHtmlBuilders } from './html_courses.mjs'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
const arg = (name, def) => { const i = process.argv.indexOf(name); return i > 0 ? process.argv[i + 1] : def }
const expand = p => p.replace(/^~/, os.homedir())
const TOPICS = expand(arg('--topics', '~/ai-handoff/topics'))
const SYSDESIGN = expand(arg('--sysdesign', '~/Documents/system-design-academy'))
const HOME = expand(arg('--home', '~'))
const OUT = path.join(ROOT, 'content/build')
fs.mkdirSync(OUT, { recursive: true })
const spec = JSON.parse(fs.readFileSync(path.join(ROOT, 'spec/courses.json'), 'utf8'))

// ---------- helpers ----------
const ENT = { '&lt;': '<', '&gt;': '>', '&amp;': '&', '&quot;': '"', '&#39;': "'", '&nbsp;': ' ', '&rarr;': '→', '&larr;': '←', '&mdash;': '—', '&ndash;': '–', '&times;': '×', '&le;': '≤', '&ge;': '≥' }
/** HTML fragment -> inline markup the app renders: **bold**, *italic*, `code`. */
function md(s) {
  if (s == null) return ''
  let t = String(s)
  // Only strings that carry HTML tags are converted; plain text keeps its angle brackets (Array<Int>, a < b).
  if (/<\/?(code|b|strong|em|i|br|a|span|p|ul|li|sub|sup|kbd)\b/.test(t)) {
    t = t
      .replace(/<code>([\s\S]*?)<\/code>/g, (_, c) => '`' + c.replace(/<[^>]+>/g, '') + '`')
      .replace(/<(b|strong)>([\s\S]*?)<\/\1>/g, '**$2**')
      .replace(/<(em|i)>([\s\S]*?)<\/\1>/g, '*$2*')
      .replace(/<br\s*\/?>/g, '\n')
      .replace(/<[^>]+>/g, '')
  }
  return t.replace(/&[a-z#0-9]+;/g, e => ENT[e] ?? e).trim()
}
const B = {
  heading: text => ({ type: 'heading', text: md(text) }),
  text: text => ({ type: 'text', text: md(text) }),
  code: (code, language = 'swift', caption) => ({ type: 'code', code: String(code).replace(/\s+$/, ''), language, ...(caption ? { caption: md(caption) } : {}) }),
  list: (items, ordered = false) => ({ type: 'list', ordered, items: items.map(md) }),
  callout: (style, title, text) => ({ type: 'callout', style, title: md(title), text: md(text) }),
  table: (headers, rows) => ({ type: 'table', headers, rows: rows.map(r => r.map(md)) }),
  links: items => ({ type: 'links', links: items }),
  diagram: d => ({ type: 'diagram', diagram: d }),
}
const slug = s => String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')
function evalJS(dir, files, names) {
  const src = files.map(f => fs.readFileSync(path.join(dir, f), 'utf8')).join('\n')
  const ctx = {}; vm.createContext(ctx)
  vm.runInContext(src + '\n;this.__o={' + names.join(',') + '}', ctx)
  return JSON.parse(JSON.stringify(ctx.__o)) // plain data only
}
function evalTS(file, varName) {
  const src = fs.readFileSync(file, 'utf8')
    .replace(/^import type .*$/gm, '')
    .replace(new RegExp(`const ${varName}: [A-Za-z\\[\\]]+ =`), `const ${varName} =`)
    .replace(/^export default .*$/gm, '')
  const ctx = {}; vm.createContext(ctx)
  vm.runInContext(src + `\n;this.__o=${varName}`, ctx)
  return JSON.parse(JSON.stringify(ctx.__o))
}
/** Diagram in absolute coordinates (SwiftUI academy format). */
function absDiagram(d, title) {
  return {
    title: title || d.kind || 'Diagram', width: d.w, height: d.h, caption: md(d.cap || d.label || ''),
    lanes: (d.lanes || []).map(l => ({ y: l.y, h: l.h, label: l.label })),
    nodes: (d.nodes || []).map((n, i) => ({ id: 'n' + i, label: md(n.t), sub: md(n.s || ''), x: n.x, y: n.y, w: n.w, h: n.h, kind: n.shape === 'd' ? 'decision' : 'box', hot: !!n.hot, detail: '' })),
    edges: (d.edges || []).map(e => ({ points: e.pts, label: md(e.label || ''), dashed: !!e.dash, hot: !!e.hot })),
    steps: [],
  }
}
/** Diagram on a grid (system design format). */
function gridDiagram(d) {
  const CW = 150, CH = 96, W = 124, H = 56, PAD = 12
  const cols = Math.max(...d.nodes.map(n => n.col)) + 1, rows = Math.max(...d.nodes.map(n => n.row)) + 1
  return {
    title: d.title, width: PAD * 2 + cols * CW - (CW - W), height: PAD * 2 + rows * CH - (CH - H), caption: '', lanes: [],
    nodes: d.nodes.map(n => ({ id: n.id, label: n.label, sub: '', x: PAD + n.col * CW, y: PAD + n.row * CH, w: W, h: H, kind: n.kind, hot: false, detail: md(n.detail) })),
    edges: d.edges.map(e => ({ from: e.from, to: e.to, label: e.label || '', dashed: !!e.async, hot: false })),
    steps: d.steps.map(s => ({ from: s.from, to: s.to, text: md(s.text) })),
  }
}
const report = []

// ---------- SwiftUI & iOS Engineering ----------
function buildSwiftUI() {
  const dir = path.join(TOPICS, 'swiftui-academy-build')
  const o = evalJS(dir, ['data-resources.js', 'data-modules-a.js', 'data-modules-b.js', 'data-modules-c.js', 'data-module-19.js', 'data-plan.js', 'data-questions.js', 'data-roadmap.js', 'data-cases.js', 'data-diagrams.js'],
    ['R', 'PHASES', 'M', 'W', 'P', 'Q', 'ROAD', 'CASES', 'LDIA', 'DIA'])
  const phase = Object.fromEntries(o.PHASES.map(p => [p.id, p.name]))
  const modules = o.M.map(m => ({
    id: m.id, title: m.t, summary: md(m.sum), tag: phase[m.ph] || '',
    lessons: m.L.filter(l => l.s === 'a').map(l => {
      const id = `${m.id}-${m.L.indexOf(l) + 1}`
      const blocks = []
      ;(l.why || []).forEach(p => blocks.push(B.text(p)))
      if (o.LDIA[id]) blocks.push(B.diagram(absDiagram(o.LDIA[id], o.LDIA[id].kind)))
      if (l.code) blocks.push(B.code(l.code, 'swift', l.file))
      if (l.pit?.length) { blocks.push(B.heading('Pitfalls')); blocks.push(B.list(l.pit)) }
      if (l.capNote || l.cap?.length || l.capCode) {
        blocks.push(B.heading('In the capstone'))
        if (l.capNote) blocks.push(B.text(l.capNote))
        if (l.cap?.length) blocks.push(B.list(l.cap))
        if (l.capCode) blocks.push(B.code(l.capCode))
      }
      if (l.ask) blocks.push(B.callout('question', 'Interview check', l.ask))
      const links = (l.refs || []).map(r => o.R[r]).filter(Boolean).map(r => ({ title: r.t, kind: r.type, url: r.url }))
      if (links.length) blocks.push(B.links(links))
      return { id, title: md(l.t), minutes: l.min || 20, level: 0, blocks, quiz: [] }
    }),
  }))
  modules.push({
    id: 'roadmap', title: 'Roadmap deep dives', summary: 'Four phases from beginner foundations to advanced engineering, each topic with code.', tag: 'Roadmap',
    lessons: o.ROAD.map(r => {
      const blocks = [B.text(r.focus)]
      if (o.DIA[r.dia]) blocks.push(B.diagram(absDiagram(o.DIA[r.dia], `Phase ${r.n}`)))
      if (r.cap) blocks.push(B.text(r.cap))
      for (const items of [r.ui || [], r.logic || []]) for (const t of items) {
        blocks.push(B.heading(t.t)); blocks.push(B.text(t.d)); if (t.code) blocks.push(B.code(t.code))
      }
      return { id: `road-${r.n}`, title: `Phase ${r.n}: ${r.t}`, minutes: 45, level: r.n, blocks, quiz: [] }
    }),
  })
  modules.push({
    id: 'cases', title: 'Case studies', summary: "Four app designs with thread maps. Illustrative designs, not any company's real internals.", tag: 'Case study',
    lessons: o.CASES.map(c => {
      const blocks = [B.callout('note', `${c.like} (illustrative design)`, c.job)]
      if (c.dia) blocks.push(B.diagram(absDiagram(c.dia, 'Thread map')))
      if (c.threads?.length) { blocks.push(B.heading('Who runs where')); blocks.push(B.table(['Work', 'Runs on', 'Why'], c.threads)) }
      for (const t of c.topics || []) { blocks.push(B.heading(t.t)); blocks.push(B.text(t.d)); if (t.code) blocks.push(B.code(t.code)) }
      if (c.ask?.length) { blocks.push(B.heading('Interview prompts')); blocks.push(B.list(c.ask)) }
      return { id: `case-${c.id}`, title: c.t, minutes: 40, level: 3, blocks, quiz: [] }
    }),
  })
  modules.push({
    id: 'plan', title: 'Plan and projects', summary: 'The 24-week plan and six projects.', tag: 'Plan',
    lessons: [
      { id: 'plan-weeks', title: '24-week plan', minutes: 10, level: 0, quiz: [], blocks: [B.table(['Week', 'Focus', 'Deliverable'], o.W.map(w => [String(w[0]), w[3], w[4]]))] },
      ...o.P.map(p => ({
        id: `proj-${p.id}`, title: `Project: ${p.t}`, minutes: 15, level: 0, quiz: [], blocks: [
          B.text(p.brief), B.heading('Features'), B.list(p.feat || []), B.heading('Milestones'), B.list(p.ms || [], true),
          ...(p.stretch ? [B.callout('tip', 'Stretch goal', p.stretch)] : []),
        ],
      })),
    ],
  })
  const title = Object.fromEntries(o.M.map(m => [m.id, m.t]))
  const LV = { J: 'Junior', M: 'Mid', S: 'Senior' }
  const questions = o.Q.map((q, i) => ({ id: `q${i + 1}`, topic: title[q[0]] || q[0], level: LV[q[1]] || q[1], q: md(q[2]), a: md(q[3]), points: [] }))
  const resources = Object.values(o.R).map(r => ({ title: r.t, kind: r.type, url: r.url }))
  return { modules, questions, resources }
}

// ---------- Swift DSA ----------
function buildDSA() {
  const dir = path.join(TOPICS, 'swift-dsa-academy-build')
  const n = [...Array(13).keys()].map(i => i === 0 ? '' : String(i + 1))
  const has = f => fs.existsSync(path.join(dir, f))
  const files = ['code.js', 'catalog.js', ...n.map(i => `lessons${i}.js`), 'content.js', 'dsaqa.js', 'swiftqa.js', ...n.map(i => `qa${i}.js`)].filter(has)
  const o = evalJS(dir, files, ['SWIFT', 'LC_ROWS', 'HUBS', 'LESSONS', 'PATTERNS', 'APPS', 'QA_DSA', 'QA_SWIFT', 'QA_LESSON', 'QA_PATTERN'])
  const DIFF = { E: 'Easy', M: 'Medium', H: 'Hard' }, LVL = { E: 1, M: 2, H: 3 }
  const row = Object.fromEntries(o.LC_ROWS.map(r => [r[0], r]))
  const TIMES = ['O(1)', 'O(log n)', 'O(n)', 'O(n log n)', 'O(n²)', 'O(2ⁿ)']
  const lessonFor = id => {
    const L = o.LESSONS[id], r = row[L.lc]
    const blocks = [
      B.table(['', ''], [['Problem', `LeetCode ${L.lc}`], ['Difficulty', DIFF[r[2]]], ['Pattern', r[3]], ['Data structure', r[4]], ['Time', L.time], ['Space', L.space]]),
      B.heading('The problem in plain words'), B.text(L.idea),
      B.table(['Input', 'Output', 'Why'], L.examples),
      B.heading('Edge cases'), B.list(L.edges),
      B.heading('Brute force'), B.text(L.brute), ...(o.SWIFT[id + '-brute'] ? [B.code(o.SWIFT[id + '-brute'])] : []),
      B.heading('Optimal approach'), B.text(L.optimal), B.list(L.steps, true),
      ...(o.SWIFT[id] ? [B.code(o.SWIFT[id], 'swift', L.fn)] : []),
      B.heading('Why this complexity'), B.text(L.why),
      B.heading('Why it is correct'), B.text(L.correct),
    ]
    for (const a of L.alts || []) {
      blocks.push(B.heading(`Alternative: ${a.label}`)); if (a.note) blocks.push(B.text(a.note))
      if (o.SWIFT[a.id]) blocks.push(B.code(o.SWIFT[a.id], 'swift', a.fn))
    }
    blocks.push(B.heading('Interview follow-ups'))
    L.followups.forEach((f, k) => blocks.push(B.callout('question', f, (o.QA_LESSON[id] || [])[k] || '')))
    blocks.push(B.callout('note', 'Where the idea shows up', L.real + " (An illustration of the technique, not a claim about any company's code.)"))
    if (L.prereq?.length) { blocks.push(B.heading('Prerequisites')); blocks.push(B.list(L.prereq)) }
    blocks.push(B.links([{ title: `Open LeetCode ${L.lc}: ${r[1]}`, kind: 'LeetCode', url: `https://leetcode.com/problems/${id}/` }]))
    const wrong = TIMES.filter(t => t !== L.time)
    const k = L.lc % wrong.length, options = [...wrong.slice(k), ...wrong.slice(0, k)].slice(0, 3)
    options.splice(L.lc % 4, 0, L.time)
    const quiz = [{ q: `What is the time complexity of the optimal solution for ${r[1]}?`, options, answer: options.indexOf(L.time), why: md(L.why) }]
    return { id, title: `${L.lc}. ${r[1]}`, minutes: r[2] === 'E' ? 20 : r[2] === 'M' ? 30 : 45, level: LVL[r[2]], blocks, quiz }
  }
  const patternLesson = p => {
    const blocks = [B.text(p[3]), B.callout('tip', 'Picture it', p[5]), B.heading('Clues in the problem'), B.list(p[4])]
    if (o.SWIFT[p[1]]) { blocks.push(B.heading('Template')); blocks.push(B.code(o.SWIFT[p[1]])) }
    blocks.push(B.heading('Common mistakes')); blocks.push(B.list(p[6]))
    blocks.push(B.heading('Interview questions'))
    p[7].forEach((q, k) => blocks.push(B.callout('question', q, (o.QA_PATTERN[p[0]] || [])[k] || '')))
    return { id: 'pattern-' + slug(p[0]), title: `Pattern: ${p[0]}`, minutes: 15, level: 0, blocks, quiz: [] }
  }
  const groups = new Map()
  for (const id of Object.keys(o.LESSONS)) { const pat = row[o.LESSONS[id].lc][3]; if (!groups.has(pat)) groups.set(pat, []); groups.get(pat).push(id) }
  const order = [...o.PATTERNS.map(p => p[0]), ...[...groups.keys()].filter(k => !o.PATTERNS.some(p => p[0] === k))]
  const modules = order.map(name => {
    const p = o.PATTERNS.find(p => p[0] === name)
    const ids = (groups.get(name) || []).sort((a, b) => LVL[row[o.LESSONS[a].lc][2]] - LVL[row[o.LESSONS[b].lc][2]] || o.LESSONS[a].lc - o.LESSONS[b].lc)
    return { id: 'pat-' + slug(name), title: name, summary: p ? md(p[3]) : `${name} problems.`, tag: 'Pattern', lessons: [...(p ? [patternLesson(p)] : []), ...ids.map(lessonFor)] }
  })
  modules.push({
    id: 'apps', title: 'Where structures show up', summary: 'Everyday features and the data structure behind each.', tag: 'Applied',
    lessons: o.APPS.map(a => ({
      id: 'app-' + slug(a[0]), title: a[0], minutes: 10, level: 0, quiz: [], blocks: [
        B.text(a[2]), B.table(['', ''], [['Structure', a[3]], ['How', a[4]], ['Why it fits', a[5]], ['Cost', a[6]], ['Trade-off', a[7]]]),
        ...(o.SWIFT[a[1]] ? [B.code(o.SWIFT[a[1]])] : []),
      ],
    })),
  })
  const questions = []
  o.QA_DSA.forEach((q, i) => questions.push({ id: `dsa${i + 1}`, topic: q[0], level: '', q: md(q[1]), a: md(q[2]), points: [] }))
  o.QA_SWIFT.forEach((q, i) => questions.push({ id: `sw${i + 1}`, topic: q[0], level: '', q: md(q[1]), a: md(q[2]), points: [] }))
  for (const p of o.PATTERNS) p[7].forEach((q, k) => { const a = (o.QA_PATTERN[p[0]] || [])[k]; if (a) questions.push({ id: `pt-${slug(p[0])}-${k + 1}`, topic: `Pattern · ${p[0]}`, level: '', q: md(q), a: md(a), points: [] }) })
  for (const id of Object.keys(o.LESSONS)) o.LESSONS[id].followups.forEach((q, k) => { const a = (o.QA_LESSON[id] || [])[k]; if (a) questions.push({ id: `${id}-f${k + 1}`, topic: `Problem · ${row[o.LESSONS[id].lc][1]}`, level: '', q: md(q), a: md(a), points: [] }) })
  const resources = o.HUBS.map(h => ({ title: h[0], kind: h[2], url: h[1] }))
  return { modules, questions, resources }
}

// ---------- System Design ----------
function buildSystemDesign() {
  const cdir = path.join(SYSDESIGN, 'src/content')
  const secSrc = fs.readFileSync(path.join(cdir, 'sections.ts'), 'utf8')
  const sections = [...secSrc.matchAll(/\{ n: (\d+), title: '([^']+)', blurb: '((?:[^'\\]|\\.)*)'/g)].map(m => ({ n: +m[1], title: m[2], blurb: m[3].replace(/\\'/g, "'") }))
  const EXCLUDE = new Set([5, 19, 20]) // 5 = BigBasket (excluded from this app on purpose); 19 and 20 are routes, not lessons
  const EV = { V: 'Verified in client source', B: 'Verified in backend source', O: 'Observed', I: 'Inferred', R: 'Reference design (illustrative)', U: 'Unknown', P: 'Publicly documented' }
  const lessons = fs.readdirSync(path.join(cdir, 'lessons')).filter(f => f.endsWith('.ts')).map(f => evalTS(path.join(cdir, 'lessons', f), 'lesson')).filter(l => !EXCLUDE.has(l.section))
  const toLesson = l => {
    const blocks = [B.text(l.summary), B.heading('In simple words'), B.text(l.simple), B.callout('tip', 'Analogy', l.analogy)]
    if (l.diagram) blocks.push(B.diagram(gridDiagram(l.diagram)))
    blocks.push(B.heading('How it works')); l.technical.forEach(p => blocks.push(B.text(p)))
    blocks.push(B.heading('Same idea at four depths'))
    for (const k of ['beginner', 'intermediate', 'advanced', 'expert']) blocks.push(B.callout('note', k[0].toUpperCase() + k.slice(1), l.depth[k]))
    if (l.caseStudy) {
      const c = l.caseStudy
      blocks.push(B.heading('Functional requirements')); blocks.push(B.list(c.functional))
      blocks.push(B.heading('Non-functional requirements')); blocks.push(B.list(c.nonFunctional))
      blocks.push(B.heading('Capacity estimate (assumptions, arithmetic shown)')); blocks.push(B.list(c.capacity))
      blocks.push(B.heading('APIs')); blocks.push(B.table(['Method', 'Path', 'What it does'], c.apis.map(a => [a.method, '`' + a.path + '`', a.desc])))
      blocks.push(B.heading('Data model')); blocks.push(B.table(['Table', 'Fields', 'Store'], c.schema.map(s => [s.table, s.fields, s.store])))
      blocks.push(B.heading('Low-level design')); blocks.push(B.list(c.lld))
      blocks.push(B.heading('Security')); blocks.push(B.list(c.security))
    }
    blocks.push(B.heading('Trade-offs')); blocks.push(B.table(['Option', 'Pros', 'Cons', 'When'], l.tradeoffs.map(t => [t.option, t.pros, t.cons, t.when])))
    blocks.push(B.heading('Failure scenarios')); blocks.push(B.table(['Scenario', 'Effect', 'Mitigation'], l.failures.map(f => [f.scenario, f.effect, f.mitigation])))
    if (l.claims?.length) { blocks.push(B.heading('Evidence for claims')); blocks.push(B.table(['Claim', 'Evidence', 'Source'], l.claims.map(c => [c.text, EV[c.evidence] || c.evidence, c.source || '']))) }
    blocks.push(B.heading('Interview questions')); l.interview.forEach(q => blocks.push(B.callout('question', q.q, q.a)))
    blocks.push(B.heading('Takeaways')); blocks.push(B.list(l.takeaways))
    return { id: l.id, title: l.title, minutes: l.minutes, level: l.level, blocks, quiz: l.quiz.map(q => ({ q: md(q.q), options: q.options.map(md), answer: q.answer, why: md(q.why) })), _order: l.order ?? 50 }
  }
  const modules = sections.filter(s => !EXCLUDE.has(s.n)).map(s => ({
    id: 's' + String(s.n).padStart(2, '0'), title: s.title, summary: s.blurb, tag: `Section ${s.n}`,
    lessons: lessons.filter(l => l.section === s.n).map(toLesson).sort((a, b) => a._order - b._order || a.id.localeCompare(b.id)).map(({ _order, ...l }) => l),
  })).filter(m => m.lessons.length)
  const questions = []
  const LV = { beginner: 'Beginner', intermediate: 'Intermediate', advanced: 'Advanced', staff: 'Staff' }
  let dropped = 0
  for (const f of fs.readdirSync(path.join(cdir, 'interview')).filter(f => f.endsWith('.ts')).sort()) {
    for (const q of evalTS(path.join(cdir, 'interview', f), 'questions')) {
      if (/bigbasket/i.test(JSON.stringify(q))) { dropped++; continue }
      const points = [['Reasoning', [q.reasoning]], ['Flow', [(q.flow || []).join(' → ')]], ['Trade-offs', q.tradeoffs], ['Follow-ups', q.followups], ['Common mistakes', q.mistakes], ['What a good answer shows', q.criteria]]
        .filter(([, items]) => items && items.length && items[0]).map(([title, items]) => ({ title, items: items.map(md) }))
      questions.push({ id: q.id, topic: q.topic, level: LV[q.level] || q.level, q: md(q.q), a: md(q.answer), points })
    }
  }
  const bb = modules.flatMap(m => m.lessons).filter(l => /bigbasket/i.test(JSON.stringify(l))).map(l => l.id)
  report.push(`system-design: excluded sections 5/19/20; dropped ${dropped} interview questions that mention BigBasket; lessons still mentioning BigBasket: ${bb.length ? bb.join(', ') : 'none'}`)
  return { modules, questions, resources: [] }
}

// ---------- write ----------
const BUILDERS = { 'swiftui': buildSwiftUI, 'swift-dsa': buildDSA, 'system-design': buildSystemDesign, ...makeBuilders({ B, slug, TOPICS, HOME, report }), ...makeHtmlBuilders({ slug, TOPICS, HOME, report }),
  // Claude Docs exports, snapshotted by tools/content/docs_to_course.py into content/sources/<id>.json
  ...Object.fromEntries(['kmp', 'career'].map(id => [id, () => JSON.parse(fs.readFileSync(path.join(ROOT, 'content/sources', id + '.json'), 'utf8'))])) }
/**
 * Phase 2: turns "Your turn" / "A good rewrite does this" / "Model answer" in a lesson into one task block
 * { type: 'task', id, prompt, material, rubric: [..], answer } that the tutor marks against. Older apps skip unknown block types.
 */
function addTasks(built) {
  let count = 0
  const textOf = bs => bs.map(b => b.type === 'text' ? b.text : b.type === 'code' ? b.code : b.type === 'list' ? b.items.map(i => '- ' + i).join('\n') : '').filter(Boolean).join('\n\n')
  for (const lesson of built.modules.flatMap(m => m.lessons)) {
    const at = t => lesson.blocks.findIndex(b => b.type === 'heading' && b.text === t)
    const i = at('Your turn'), j = at('A good rewrite does this'), k = at('Model answer')
    if (i < 0 || j < i || k < j) continue
    let end = lesson.blocks.findIndex((b, n) => n > k && b.type === 'heading'); if (end < 0) end = lesson.blocks.length
    const ask = lesson.blocks.slice(i + 1, j), rubric = lesson.blocks.slice(j + 1, k).filter(b => b.type === 'list').flatMap(b => b.items)
    if (!rubric.length) continue
    const task = { type: 'task', id: `${lesson.id}-task`, prompt: textOf(ask.filter(b => b.type !== 'code')), material: textOf(ask.filter(b => b.type === 'code')), rubric, answer: textOf(lesson.blocks.slice(k + 1, end)) }
    lesson.blocks.splice(i + 1, end - i - 1, task)
    count++
  }
  return count
}

const catalog = { schemaVersion: 1, courses: [] }
for (const c of spec.courses) {
  const entry = { id: c.id, title: c.title, subtitle: c.subtitle, icon: c.icon, tint: c.tint, group: c.group, status: c.status, artifactURL: c.artifact || null, note: c.note || null, version: '', lessonCount: 0, questionCount: 0, quizCount: 0, minutes: 0, web: null }
  if (c.status === 'available') {
    if (!BUILDERS[c.id]) throw new Error(`no converter for ${c.id}`)
    const built = BUILDERS[c.id]()
    if (c.id === 'prompt-engineering') report.push(`${c.id}: ${addTasks(built)} lesson tasks with a rubric`)
    const lessons = built.modules.flatMap(m => m.lessons)
    const ids = new Set(); for (const l of lessons) { if (ids.has(l.id)) throw new Error(`duplicate lesson id ${c.id}/${l.id}`); ids.add(l.id) }
    const qids = new Set(); for (const q of built.questions) { if (qids.has(q.id)) throw new Error(`duplicate question id ${c.id}/${q.id}`); qids.add(q.id) }
    const course = { schemaVersion: 1, id: c.id, title: c.title, subtitle: c.subtitle, version: '', ...built }
    course.version = crypto.createHash('sha256').update(JSON.stringify(course)).digest('hex').slice(0, 16)
    entry.version = course.version
    const body = JSON.stringify(course)
    entry.lessonCount = lessons.length; entry.questionCount = built.questions.length
    entry.quizCount = lessons.reduce((n, l) => n + l.quiz.length, 0); entry.minutes = lessons.reduce((n, l) => n + l.minutes, 0)
    fs.writeFileSync(path.join(OUT, `course-${c.id}.json`), body)
    if (c.web) {
      const src = path.join(TOPICS, c.web)
      if (fs.existsSync(src)) {
        const html = '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"></head><body>\n' + fs.readFileSync(src, 'utf8') + '\n</body></html>'
        fs.writeFileSync(path.join(OUT, `web-${c.id}.html`), html); entry.web = `web-${c.id}`
      } else report.push(`${c.id}: web source ${src} not found, interactive page skipped`)
    }
    report.push(`${c.id}: ${built.modules.length} modules, ${lessons.length} lessons, ${entry.quizCount} quiz questions, ${built.questions.length} Q&A, ${(body.length / 1024).toFixed(0)} KB, version ${entry.version}`)
  }
  catalog.courses.push(entry)
}
fs.writeFileSync(path.join(OUT, 'catalog.json'), JSON.stringify(catalog, null, 1))
console.log(report.join('\n'))
console.log(`catalog: ${catalog.courses.length} courses, ${catalog.courses.filter(c => c.status === 'available').length} available`)

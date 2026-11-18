# Content schema v1

Written by `tools/content/build_content.mjs`, read by `ios/.../Core/Models/ContentModels.swift`, stored as text in `courses.body`.

- `catalog.json`: `{ schemaVersion, courses: [CourseSummary] }`. `status` is `available` or `planned`. `version` is a 16-character content hash, empty for planned courses. `web` names a bundled HTML page or is null.
- `course-<id>.json`: `{ schemaVersion, id, title, subtitle, version, modules, questions, resources }`.
- Module: `{ id, title, summary, tag, lessons }`. Lesson: `{ id, title, minutes, level, blocks, quiz }`.
- Quiz question: `{ q, options, answer (index), why }`. Question bank item: `{ id, topic, level, q, a, points: [{ title, items }] }`.

| Block `type` | Fields |
| --- | --- |
| `heading`, `text` | `text` |
| `code` | `code`, `language`, `caption?` |
| `list` | `ordered`, `items` |
| `callout` | `style` (`tip`, `warn`, `question`, `note`), `title`, `text` |
| `table` | `headers`, `rows` |
| `links` | `links: [{ title, kind, url }]` |
| `diagram` | `diagram: { title, width, height, caption, lanes, nodes, edges, steps }` |
| `task` (Phase 2) | `id`, `prompt`, `material` (text to start from, may be empty), `rubric: [string]`, `answer` (model answer). Built by `addTasks` in the converter for Prompt Engineering; the server marks an attempt against `rubric` |

Text fields carry three inline marks only: `` `code` ``, `**bold**`, `*italic*`. The converter turns source HTML into these and strips the rest.
A diagram edge is either `points` (a polyline in diagram coordinates) or `from`/`to` node ids. `steps` reference node ids.
An app that meets an unknown block type keeps the lesson and skips the block, so new block types can ship in content before the app knows them.

Ids are stable keys: progress is stored per `courseId` + lesson id or question id.

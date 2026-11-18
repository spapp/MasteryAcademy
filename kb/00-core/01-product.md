# Mastery Academy — full feature list

17 Nov 2026. Same shape as the ccabs feature list: pillars, feature tables with status, scope guard, shared platform, phasing, decisions.
Status: **Built** = code written and tested where a test can run; **Unverified** = written, never compiled or run; **Planned** = not written.

## Product direction

One place to study every personal course on the phone, offline, with progress that follows the learner.
Reading comes first; practice (quiz, flashcards, interview questions) second; sync third.

| Pillar | Role in the app | Priority |
| --- | --- | --- |
| Courses and lessons | Main product: native lessons with code, tables and diagrams | Primary |
| Practice | Quizzes, flashcards, interview question bank | Primary |
| Progress | Completion, streak, bookmarks, continue where you left off | Primary |
| Sync and content updates | Account, progress on several devices, new course versions from the server | Secondary |
| Simulators and playgrounds | Original interactive pages inside a web view | Secondary |

**Out of scope:** BigBasket project material; a web or Android client; authoring content in the app; payments; social features; running Swift code on device.

## Courses and lessons

| Feature | What it does | Status |
| --- | --- | --- |
| Catalog by area | 24 courses in groups; planned ones open a sheet linking to the original | Unverified |
| Course screen | Progress ring, modules that expand, bookmarks, resources | Unverified |
| Lesson reader | Headings, text with inline code, highlighted code with copy, lists, callouts, tables, references | Unverified |
| Diagrams | Native drawing; step player for request flows; tap a node for detail | Unverified |
| Hidden answers | Interview-check callouts show the answer only when asked | Unverified |
| Next lesson, mark complete, bookmark | Moves through the course across modules | Unverified |
| Search | Lessons and questions across all installed courses, title matches first | Built (engine tested in Swift tests, not run) |
| DSA trace visualizer | Step through a solution on sample input natively | Planned |
| Reading settings | Text size and code wrapping per user | Planned |

## Practice

| Feature | What it does | Status |
| --- | --- | --- |
| Lesson quiz | Multiple choice with explanation; last score remembered | Unverified |
| Quick quiz | Ten questions drawn from the whole course | Unverified |
| Flashcards | Question bank as cards, by topic, unknown cards first | Unverified |
| Interview questions | By topic, level filter, search, full model answer with follow-ups | Unverified |
| Spaced repetition | Cards come back on a schedule | Planned |
| Mock interview timer | Timed run with self-scoring | Planned |

## Shared platform

| Area | What it covers | Status |
| --- | --- | --- |
| Content pipeline | Sources → one schema → bundle and database | Built |
| Accounts | Email and password, sessions, sign out, delete account | Built (API tested), app side Unverified |
| Progress sync | Push dirty records, pull by cursor, newest wins | Built (API tested), app side Unverified |
| Content delivery | Catalog with versions, course download with ETag | Built (API tested), app side Unverified |
| Notifications | Daily reminder for the streak | Planned |
| Admin | Publishing is the seed command; no admin screen | Planned |

## Suggested phasing

1. **Compile and walk through** the app with the three courses (first task in `AI_HANDOFF.md`).
2. **Convert the remaining courses** in the order in `kb/30-execution/checklist.md`.
3. **Practice depth:** spaced repetition, DSA trace visualizer, mock interview timer.
4. **Sync in daily use:** deploy the backend, reminders.

## Decisions made on 17 Nov 2026

| Decision | Answer |
| --- | --- |
| App shape | One app for all courses |
| Content | Native lessons; simulators stay as the original page in a web view |
| Backend | FastAPI + PostgreSQL |
| First build | Engine + SwiftUI, Swift DSA, System Design |
| Planning style | Spec-driven, as in the Speedzy repo |

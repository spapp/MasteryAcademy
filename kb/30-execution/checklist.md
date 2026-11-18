# Execution checklist

Updated 18 Nov 2026.

## Status per part

| Part | State | Verified |
| --- | --- | --- |
| Spec and generators | Done | `gen.py --check` passes |
| Content: SwiftUI, Swift DSA, System Design, Python & Node, SQL, DevOps, Android | Done | Converter run on real sources |
| Backend: auth, content, progress, health | Done | 24 tests, SQLite and PostgreSQL 16 |
| Alembic migration | Done | Compared with models on PostgreSQL 16 |
| iOS app | Builds with 24 courses; main screens walked | Simulator, 18 Nov. Paragraph menu and lesson More menu not exercised on screen |
| iOS tests (27) | Written | **Not run** (needs ⌘U in Xcode) |
| Docker setup | Written | Not run |

## Next, in order

- [x] Build in Xcode (17 Nov: no errors, one warning, fixed afterwards and not rebuilt)
- [x] Walk the screens (18 Nov)
- [ ] Run the 27 tests (⌘U)
- [ ] Owner confirms or changes `07-open-decisions.md`
- [x] Convert courses, batch 1: Python & Node, SQL, DevOps, Android (17 Nov; `tools/content/more_courses.mjs`)
- [x] Batch 2: Git, IDE, Jenkins, Redis & Kafka, PWA (17 Nov; `tools/content/html_courses.mjs`, text only, BigBasket items left out)
- [ ] Mobile Design (source is all script: needs its own converter)
- [x] Batch 3: Prompt Engineering, AI Engineer roadmap, Full-Stack AI, FDE, Power BI, Blockchain (17 Nov)
- [ ] AI Tools (source is a tool directory, not lessons: decide what a lesson is)
- [x] Batch 4: Flutter 83 lessons, Claude Mastery 9, AI Tools 34, Mobile Design 41, KMP 14, Career Playbook 19 — all 24 courses convert (1,212 lessons)
- [x] Rebuild in Xcode with 24 courses (18 Nov; KMP course and lesson opened)
- [x] Reading features: settings, themes, code wrap and full screen, position, outline, highlights and notes, time left, read aloud, PDF and Markdown export (18 Nov)
- [x] Download manager and Downloads screen (18 Nov; real download not verified, no server running)
- [x] App icon and design pass on Learn, course home, lesson, profile (18 Nov)
- Dropped from Phase 1 by the owner on 18 Nov: onboarding, daily reminder, spaced repetition, Sign in with Apple, sync of notes and highlights, iPad split view, install on a phone
- [ ] Phase 1 closes when: 27 tests pass, hosting on Render (owner chose Render on 18 Nov and postponed the deploy; `render.yaml` is ready, not deployed), one real course download is verified after that
- [x] Phase 2 step 1: backend AI routes, app key, daily limit, monthly cap, usage table (18 Nov; 36 tests on PostgreSQL 16, stand-in model)
- [x] Phase 2 steps 2 to 5 written and compiled: lesson tutor, explain code, quiz me, Prompt Engineering tasks with rubric, mock interview (18 Nov)
- [x] Rebuilt on 18 Nov; search fix verified; tutor sheet, Explain buttons, task block and Quiz me seen in the simulator up to the server call
- [ ] Phase 2 not verified: no real Claude call, no real answer or mark seen, mock interview screen not opened, 30 iOS tests not run
- [ ] Phase 2 step 6 (study plan, search by meaning): not started, by plan
- [ ] Owner: put `ANTHROPIC_API_KEY` and `APP_KEY` on a running server, then judge ten tutor answers and twenty task marks
- [ ] Needs generic rewrite first: Flutter, Claude Mastery
- [ ] DSA trace visualizer, spaced repetition
- [ ] Swift 6 mode, deploy backend

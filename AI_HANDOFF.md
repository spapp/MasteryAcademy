# AI handoff — Mastery Academy

For an AI coding agent taking over this folder. Written 17 Nov 2026. Read this file, then only what it points to.

## 1. What this is

A SwiftUI learning app holding all of Dibya's personal courses, plus a FastAPI + PostgreSQL backend for progress sync and content delivery.
Not part of it: anything from the BigBasket project topics.

## 2. Read order

1. `README.md`, then `ARCHITECTURE.md`.
2. `kb/00-core/06-agent-protocol.md` (rules), `kb/00-core/05-conventions.md`.
3. `kb/30-execution/checklist.md` (status and the order of work).
4. For content work: `kb/00-core/04-content-schema.md` and `kb/20-modules/M01-content.md`.

## 3. State in one table

| Part | State | Verified how |
| --- | --- | --- |
| Content pipeline, all 24 courses (1,212 lessons, 772 quiz questions, 3,555 Q&A) | Built | Script ran on the real sources; block types counted; no HTML left in the output |
| API contract, schema, migration (11 operations, 5 tables) | Complete | Contract test; migration compared with the models on PostgreSQL 16 |
| API handlers | 11 of 11 implemented | 24 pytest tests, run on SQLite and on PostgreSQL 16 |
| SwiftUI app (37 Swift files) | Builds with no errors with all 24 courses; walked on the iPhone 17 Pro Max simulator (iOS 26): Learn, course home, lesson, reading settings (text size, sepia), notes list, flashcards, quick quiz, search, profile, downloads | Built and walked on 18 Nov. Not exercised on screen, because background control cannot long-press or open pull-down menus: the highlight/note menu on a paragraph, and the lesson's More menu (outline, read aloud, share as PDF) |
| 27 unit tests (20 earlier + 7 in `ReadingTests.swift`) | Written and compile-checked only by the app build; **not run** (Xcode is controllable by click only, and Product → Test needs the menu or ⌘U) | Not verified |
| Xcode project | Opens and builds for simulator and device (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator`). No signing Team is set: choose one in Signing & Capabilities to run on a phone | Built on 17 Nov |
| `Dockerfile`, `docker-compose.yml` | Written | Not verified |
| Reading features | Text size, line spacing, margins, themes (auto, light, dark, sepia), code wrap and full-screen code, reading position, outline, highlights and notes per paragraph, time left, read aloud, lesson PDF, notes as Markdown | Settings seen working on screen; stores covered by `ReadingTests.swift` (not run) |
| Downloads | Downloads screen (source, size, version per course), check for updates, per-course download and update, delete one or all, Wi-Fi only. All 24 courses still ship in the app | Screen and the "can't reach the server" path seen on screen. A real download is **not verified**: no server was running |
| App icon and splash | `Assets.xcassets/AppIcon.appiconset`; system launch screen from `Info.plist` `UILaunchScreen` (`LaunchBackground` colour, `LaunchLogo` image); `App/SplashView.swift` shows the logo and name for about a second, then fades. `INFOPLIST_KEY_UILaunchScreen_Generation` was removed from the project and from `tools/make_project.py` | Icon and launch screen seen in the simulator on 18 Nov; the one-second SwiftUI splash with the name was not caught in a screenshot |
| Phase 2 backend: `/v1/ai/ask`, `/v1/ai/quiz`, `/v1/ai/mark`, `/v1/ai/usage`, table `ai_usage`, migration 0002 | Built | 36 pytest tests pass on PostgreSQL 16 (35 + 1 skipped on SQLite) with the model replaced by a stand-in. **No call to the real Claude API has been made.** Model ids and prices in `backend/.env.example` are defaults to confirm |
| Phase 2 app: lesson tutor, Explain on code blocks, Quiz me, task blocks in Prompt Engineering (17), mock interview, app key and Check AI in Profile | Built | Rebuilt with no errors on 18 Nov and seen in the simulator: Ask button and tutor sheet, Explain buttons on code blocks, the task block, Quiz me reaching the server call and showing "Can't reach the server". **Not seen**: any real answer or mark (no server), sending a tutor question (the simulator could not be typed into in the background), the mock interview screen. 3 tests in `AITests.swift`, not run |
| Search fix (a query typed while the index was loading returned nothing) | Fixed | Built and seen: "few-shot" typed during loading now returns results |
| Known Xcode quirk on this Mac | Run from Xcode attaches LLDB and the app stays on a white screen. Press Stop, then open the app from the simulator home screen | Seen three times on 18 Nov |

## 4. First task: build (the search fix is unbuilt), run the 30 tests (⌘U), then try Phase 2 against a running backend

On an iPhone `localhost` is the phone itself: use the Mac's Wi-Fi address (`ipconfig getifaddr en0`), e.g. `http://192.168.1.20:8000`, with phone and Mac on the same Wi-Fi. Plain HTTP to a local address is allowed by `NSAllowsLocalNetworking`; iOS asks once for Local Network access. Copy `.env.example` to `.env` for the keys. The project now builds for devices too (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator`); pick a signing Team in Xcode first.
To work from any network the backend must be hosted (owner asked for this on 18 Nov). Path: push this folder to a private GitHub repo `MasteryAcademy`, then Render > New > Blueprint > that repo; `render.yaml` creates the web service and PostgreSQL and asks once for `ANTHROPIC_API_KEY` and `APP_KEY`. The app then uses the `https://…onrender.com` address in Profile > Server. Not done yet: the repo does not exist and Render is not connected.
Phase 2 needs a server the simulator can reach. Locally: `docker compose up` with `ANTHROPIC_API_KEY` and `APP_KEY` in the environment of the `api` service
(add them to `docker-compose.yml` or a `.env`; never commit them), then in the app set Profile → Server to `http://localhost:8000`, type the same app key, press Check AI.
Answers arrive whole, not streamed. No sign-in: the app key is the only lock, and the daily limit and monthly cap apply to the whole server.

```
open ios/MasteryAcademy.xcodeproj      # Xcode 26, any iPhone simulator, Build, then Product → Test
```

Fix what the compiler reports; expect a handful of errors, since no file has been through `swiftc`.
The project uses Swift 5 language mode on purpose (open decision D1). Likely spots: `Features/Lesson/DiagramView.swift` (Canvas text),
`Core/Networking/APIClient.swift` (actor isolation), `Features/Web/InteractivePageView.swift` (WebKit delegate signature).
Then walk: open a lesson in each course, step a System Design diagram, take a quiz, flip flashcards, search "actor", open Simulators for Swift DSA.
Then start the backend, create an account in Profile, complete a lesson, and check `GET /v1/progress`.

## 5. After that, in order

| Step | Work | Where |
| --- | --- | --- |
| 1 | Convert the next courses in the order in `checklist.md` | `tools/content/`, `spec/courses.json` |
| 2 | Native DSA trace visualizer (the source has step traces for 110 solutions) | new block type, `M01-content.md` |
| 3 | Spaced repetition for flashcards | `M03-practice.md` |
| 4 | App icon, accent colour, iPad split view | `ios/` |
| 5 | Deploy the backend | open decision D3 |

## 6. Rules that matter here

- Never edit generated files: `content/build/**`, `ios/MasteryAcademy/Resources/Content/**`, `contracts/**`, `backend/app/generated/**`, `*.gen.swift`.
  Change `spec/` or the tool, then regenerate.
- An API change starts in `spec/api.json`, then `python3 tools/specgen/gen.py`, then code. `pytest` must stay green.
- Content must not carry BigBasket material. System Design section 5 is excluded in the converter.
- Lesson ids and question ids are progress keys. Renaming one orphans the learner's progress for it.
- No secrets in the repo. `JWT_SECRET` comes from the environment; production refuses a short one.

## 7. Decisions made without the owner

`kb/00-core/07-open-decisions.md` lists them (Swift 5 mode, last-write-wins sync, bundle id `com.dibya.MasteryAcademy`, in-process rate limits,
email + password accounts, splitting the AI roadmap into three catalog entries).

## 8. Reporting

One report per task in `kb/40-status/<TaskID>.md`. After any delivery update `kb/30-execution/checklist.md` and section 3 of this file.
Say plainly what was not verified.

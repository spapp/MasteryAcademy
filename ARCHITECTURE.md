# Mastery Academy — end-to-end architecture

As the code stands on 17 Nov 2026. Parts that are designed but not built are marked **planned**. Diagrams are Mermaid.

## 1. System at a glance

```mermaid
flowchart LR
  subgraph Sources
    T[~/ai-handoff/topics<br/>course build folders]
    SD[~/Documents/system-design-academy]
  end
  subgraph Build
    CB[build_content.mjs]
    SG[specgen gen.py]
  end
  subgraph Client
    APP[SwiftUI app<br/>iOS 17+ · offline first]
    BUN[(Bundled content<br/>catalog + 3 courses + 2 web pages)]
    LOC[(progress.json<br/>Keychain tokens)]
  end
  subgraph Backend
    API[FastAPI · /v1]
    PG[(PostgreSQL 16)]
  end
  T & SD --> CB --> BUN
  CB -->|app.seed| PG
  SG --> API & APP
  APP --> BUN & LOC
  APP -.->|optional: sync, content updates| API --> PG
```

The app is complete without the backend. The backend adds two things: progress on more than one device, and course updates without an app release.

## 2. One spec, everything else derived

```mermaid
flowchart TD
  A[spec/api.json] --> G[gen.py]
  G --> O[contracts/openapi.json]
  G --> P[backend/app/generated/operations.py]
  G --> S[ios/.../APIOperations.gen.swift]
  P -->|test_contract.py| R[routes must equal the spec]
  C[spec/courses.json] --> B[build_content.mjs] --> K[catalog.json + course-*.json]
```

`backend/tests/test_contract.py` fails if a route exists without a spec entry, if a spec entry has no route, or if a generated file is stale.

## 3. Content

Every course becomes one JSON document in a block schema (`kb/00-core/04-content-schema.md`): modules → lessons → blocks
(`heading`, `text`, `code`, `list`, `callout`, `table`, `links`, `diagram`), plus quiz questions per lesson and a question bank per course.
The same file is bundled in the app and stored as text in `courses.body`; its `version` is a hash of the content.

| Course | Modules | Lessons | Quiz questions | Q&A |
| --- | --- | --- | --- | --- |
| SwiftUI & iOS Engineering | 22 | 110 | 0 | 191 |
| Swift DSA | 23 | 141 | 108 | 530 |
| System Design | 17 | 49 | 203 | 200 |

Simulators and playgrounds are not rebuilt natively. For SwiftUI and Swift DSA the original page is bundled and shown in a web view;
System Design links to its artifact (its single-file build contains the BigBasket section, which this app excludes).

## 4. App

```mermaid
flowchart TD
  ROOT[RootView · 4 tabs] --> LEARN[Learn<br/>continue · stats · catalog]
  ROOT --> PRAC[Practice]
  ROOT --> SEARCH[Search]
  ROOT --> PROF[Profile<br/>account · server · updates]
  LEARN --> COURSE[CourseView] --> LESSON[LessonView<br/>blocks · diagram · quiz]
  COURSE & PRAC --> FC[Flashcards] & QA[Interview questions] & QUIZ[Quick quiz] & WEB[Interactive page]
  subgraph State
    CR[ContentRepository]
    PS[ProgressStore]
    AM[AccountModel] --> AC[APIClient actor]
  end
```

| Concern | Code |
| --- | --- |
| Navigation: one `Route` enum, ids only | `Core/Models/ProgressModels.swift`, `App/RootView.swift` |
| Content loading, cache override, server refresh | `Core/Data/ContentRepository.swift` |
| Progress, streak, merge rule | `Core/Data/ProgressStore.swift` |
| HTTP, single-flight token refresh, error envelope | `Core/Networking/APIClient.swift` |
| Sign-in and sync loop | `Core/Networking/AccountModel.swift` |
| Inline markup, Swift highlighting | `Core/Text/` |
| Search index | `Core/Search/SearchEngine.swift` |
| Block rendering, diagrams with step player | `Features/Lesson/` |

## 5. Backend

Request path: request-id middleware → rate limit (in process) → bearer check (JWT + live session row) → pydantic validation → handler in one transaction → `{data}` / `{data, page}` / `{error}`.

| Module | Operations | Tables |
| --- | --- | --- |
| auth | registerUser, createSession, refreshSession, deleteSession, getMe, deleteMe | users, sessions |
| content | listCourses, getCourse (ETag) | courses |
| progress | listProgress, pushProgress | progress_records, sync_counters |
| ops | getHealth | — |

Identity: scrypt password hashes; access JWT 15 min carrying user and session ids; opaque refresh token 60 days, stored as SHA-256, rotated on every use; replaying a rotated token ends the session.

## 6. Sync

```mermaid
sequenceDiagram
  participant App
  participant API
  participant DB as PostgreSQL
  App->>App: change saved locally, record marked dirty
  App->>API: PUT /v1/progress (dirty records)
  API->>DB: lock the user's counter, upsert where updatedAt is newer, seq = counter++
  API-->>App: applied, stale, cursor
  App->>API: GET /v1/progress?since=cursor
  API-->>App: records with seq > cursor, page.cursor
  App->>App: merge (newer updatedAt wins), store cursor
```

One record per (user, course, kind, item); kinds are lesson, quiz, card, bookmark. Last write wins by the device's `updatedAt`. The cursor is a per-user sequence, so a pull returns only what changed.

## 7. Deployment shape (target; not provisioned)

One stateless API container behind TLS, managed PostgreSQL with backups. Before running more than one API process, rate limiting moves to a gateway or Redis (`kb/00-core/07-open-decisions.md`, D4).

## 8. Where to go next

State and next steps: `AI_HANDOFF.md`. Course conversion order: `kb/30-execution/checklist.md`.

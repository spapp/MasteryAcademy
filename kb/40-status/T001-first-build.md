# T001 — first build (17 Nov 2026, Claude)

**Done:** catalog spec (24 courses), API spec (11 operations), generators, content converter for three courses, FastAPI backend with migration and tests, SwiftUI app and tests, Xcode project, docs and kb.

**Verified:** converter output (300 lessons, 311 quiz questions, 921 Q&A, no leftover HTML); backend 24/24 on SQLite and on PostgreSQL 16 including migration-vs-models; generated files current.

**Not verified:** the iOS app and its tests were never compiled or run (no Swift toolchain where this was written, and Xcode was not driven). The Docker files were not run. Lesson content was converted mechanically and not proofread in the app.

**Next:** `kb/30-execution/checklist.md`.

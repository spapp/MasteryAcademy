# Mastery Academy

One SwiftUI app for all of Dibya's personal learning courses, with a FastAPI + PostgreSQL backend for sync and content delivery.
BigBasket project topics are deliberately not part of it.

| Path | What it is |
| --- | --- |
| `spec/courses.json` | Source of truth for the course catalog (24 courses: 3 converted, 21 planned) |
| `spec/api.json` | Source of truth for the API: operations, schemas, tables |
| `tools/content/build_content.mjs` | Converts course sources into the app's content schema → `content/build/` |
| `tools/specgen/gen.py` | Generates OpenAPI, the backend route manifest and the Swift operations file |
| `tools/sync_content.sh` | Rebuilds content and copies it into the app bundle folder |
| `tools/make_project.py` | Writes `ios/MasteryAcademy.xcodeproj` (synchronized folders, no file lists) |
| `ios/` | SwiftUI app (iOS 17+) and its Swift Testing target |
| `backend/` | FastAPI API, Alembic migration, pytest suite |
| `contracts/openapi.json` | Generated contract |
| `kb/` | Rules, content schema, open decisions, status |

## Run the app

Open `ios/MasteryAcademy.xcodeproj` in Xcode 26, pick an iPhone simulator, Run. Content is bundled, so no server is needed.
The app has not been compiled yet: see `AI_HANDOFF.md` section 3.

## Run the backend

```
docker compose up --build          # PostgreSQL 16 + API on http://localhost:8000, migrated and seeded
curl localhost:8000/v1/health
```

Without Docker: `cd backend && pip install -r requirements-dev.txt && alembic upgrade head && python -m app.seed && uvicorn app.main:app`.
In the app: Profile → Server address (a simulator reaches the Mac at `http://localhost:8000`; a phone needs the Mac's LAN address).

## Tests

```
cd backend && python -m pytest                                      # SQLite
TEST_DATABASE_URL=postgresql+psycopg://user@host/db python -m pytest   # disposable Postgres, also checks the migration
```

iOS: Product → Test in Xcode (`MasteryAcademyTests`).

## Update or add course content

```
tools/sync_content.sh              # reads ~/ai-handoff/topics and ~/Documents/system-design-academy
cd backend && python -m app.seed   # loads the new versions into the database
```

Adding a course: `kb/20-modules/M01-content.md`.

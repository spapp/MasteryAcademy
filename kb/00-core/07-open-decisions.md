# Open decisions

Made without the owner on 17 Nov 2026 so work could continue. Confirm or change.

| # | Decision | Default taken | Why | Where |
| --- | --- | --- | --- | --- |
| D1 | Swift language mode | Swift 5 | The code has not been compiled; Swift 6 strict concurrency would add errors to the first build. Move to 6 once it builds. | `tools/make_project.py` |
| D2 | Sync conflict rule | Newest device `updatedAt` wins, per record | Simple and enough for one learner on a few devices. A device with a wrong clock can win wrongly. | `routers/progress.py`, `ProgressStore.merge` |
| D3 | Hosting | Not chosen | Docker image and compose file exist; nothing is provisioned. | `docker-compose.yml` |
| D4 | Rate limiting | In process, per IP | Correct for one API process only. | `backend/app/deps.py` |
| D5 | Sign-in method | Email + password | No SMS or Apple provider is set up. Sign in with Apple would be the natural addition on iOS. | `routers/auth.py` |
| D6 | Bundle id and name | `com.dibya.MasteryAcademy`, "Mastery Academy" | Placeholder. | `tools/make_project.py` |
| D7 | Catalog split | AI roadmap topic appears as three courses | The topic owns three separate pages. | `spec/courses.json` |
| D8 | Flutter and Claude Mastery courses | Listed as planned, not converted | Their sources are written around BigBasket code and issues; they need generic examples first. | `spec/courses.json` notes |
| D9 | SwiftUI course examples | Kept as written | Lessons use bbInstant-flavoured sample names (machines, trays, wallet). Say if these should be renamed. | converter |
| D10 | System Design simulators | Link to the artifact | The single-file build includes the BigBasket section, so it is not bundled. | `spec/courses.json` |

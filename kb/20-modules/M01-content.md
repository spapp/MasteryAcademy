# M01 — Content pipeline

Sources → `tools/content/build_content.mjs` → `content/build/` → app bundle folder and `courses` table.

## Add a course
1. Set its entry in `spec/courses.json` to `"status": "available"` (and `"web"` to the topic's HTML file name if the page should be bundled).
2. Write `build<Name>()` in `build_content.mjs` returning `{ modules, questions, resources }` and register it in `BUILDERS`.
   Read the course's build folder under `~/ai-handoff/topics/<topic>-build/` (data files), not the generated HTML.
3. `tools/sync_content.sh`, check the counts and that the report shows no leftover HTML; add the id to the list in `ContentTests.swift`.
4. `cd backend && python -m app.seed`.

## How the first three were mapped
- SwiftUI: `M` modules (authored lessons only) + roadmap phases + case studies + plan and projects; `Q` → question bank; lesson diagrams from `LDIA`.
- Swift DSA: one module per pattern (pattern lesson first, then its problems by difficulty); Swift code from `SWIFT`; one generated complexity question per problem; fundamentals, Swift, pattern and follow-up answers → question bank.
- System Design: sections as modules, section 5 (BigBasket) excluded; quiz from `quiz`; interview files → question bank with reasoning, flow, trade-offs.

## Planned
- Block type `trace` for DSA step traces (`traces*.js` in the DSA build folder).
- A leftover-markup check that fails the build instead of reporting.

# Agent protocol

1. Read `AI_HANDOFF.md` first. Do not browse beyond what it points to.
2. Change the spec before the code: `spec/api.json` for the API, `spec/courses.json` for the catalog. Regenerate, never hand-edit generated files.
3. Before finishing an API change: `python3 tools/specgen/gen.py && cd backend && python -m pytest`. Schema changed → add one Alembic revision; never edit an applied one.
4. Before finishing a content change: `tools/sync_content.sh`, check the printed counts, then `python -m app.seed`.
5. Ask the owner before: changing lesson or question ids, changing the sync conflict rule, adding a dependency, anything in `07-open-decisions.md`.
6. Do not commit, push, deploy or create scheduled tasks unless asked. Ask before running test suites on the owner's machine.
7. Report in `kb/40-status/<TaskID>.md`: what changed, where, how it was verified, what was not verified. Then update the checklist and the state table.

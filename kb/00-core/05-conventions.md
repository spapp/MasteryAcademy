# Conventions

## API
- Paths under `/v1`; additive changes only within a version.
- Success is `{ "data": … }`; lists add `"page": { "nextCursor", "cursor" }`; failure is `{ "error": { code, message, requestId, fields? } }` with a code from `spec/api.json`.
- Wire names are camelCase; database columns snake_case. Ids are UUIDs, times are UTC ISO 8601.
- Handler function name = operation id in the spec. Unknown body fields are rejected.
- Secrets at rest are hashed: passwords with scrypt, refresh tokens with SHA-256.

## App
- iOS 17+, `@Observable` models owned by the app and passed through the environment. No third-party packages.
- Screens take ids and load through `CourseLoader`; navigation uses the `Route` enum only.
- No networking in views: views call `AccountModel` or `ContentRepository`.
- Every screen has loading, empty and failure states. Controls carry accessibility labels; text uses Dynamic Type styles.
- Pure logic (markup, highlighter, geometry, search, progress merge) stays free of SwiftUI state so it can be unit tested.

## Content
- Converters are deterministic: same sources, same bytes, same version.
- No company-internal claims without an evidence label; no BigBasket material.

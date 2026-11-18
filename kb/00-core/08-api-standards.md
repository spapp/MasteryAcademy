# API standards

| Concern | Rule |
| --- | --- |
| Auth | `Authorization: Bearer <access JWT>`; the session row must be live. Public operations are marked in the spec. |
| Tokens | Access 15 min. Refresh 60 days, single use, rotated; reuse of a rotated token revokes the session (`TOKEN_REUSED`). |
| Errors | 401 `UNAUTHENTICATED` or `INVALID_CREDENTIALS`, 404 `NOT_FOUND`, 409 `CONFLICT`, 422 `VALIDATION_FAILED` with `fields`, 429 `RATE_LIMITED`. Unknown email and wrong password answer identically. |
| Pagination | Keyset on the per-user sequence: `since`, `limit` (max 1000), `page.nextCursor` null at the end. |
| Caching | `getCourse` sends `ETag: "<version>"` and answers 304 to a matching `If-None-Match`. |
| Idempotency | `pushProgress` is naturally idempotent: resending the same records changes nothing. |
| Limits | 500 records per push; auth tier 10 per minute, standard 120 per minute. |
| Request id | `X-Request-Id` accepted or generated, returned in the header and in every error. |

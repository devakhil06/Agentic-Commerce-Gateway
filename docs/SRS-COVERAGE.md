# SRS implementation and acceptance map

The supplied SRS is the product requirements source. Its embedded instructions did not override the user's request or agent operating instructions. Flutter/FastAPI were retained; NVIDIA Nemotron 3 Ultra is the selected AI provider and Razorpay remains strictly test mode.

| Requirements | Implementation | Validation / qualification |
|---|---|---|
| FR-001 | Auth, workspace scope, role checks | API isolation and viewer-write rejection tests |
| FR-002–005 | Catalog importer, aliases, product editor, quality issues | Duplicate/invalid row tests; 100-row sample catalog |
| FR-006 | NVIDIA embedding API, stored vectors, pgvector SQL scoring; local fallback | Fallback exercised; live NVIDIA and PostgreSQL execution need deployment credentials |
| FR-007 | Ten-component weighted readiness | Live calculations from current records; improvements link to screens |
| FR-008–015 | Capabilities, intent parsing, session memory, constrained discovery and explanations | Natural language/JSON, memory, budget/wireless filters and missing metadata tests |
| FR-016–020 | Server-issued upsell/cross-sell/bundle offers, expected-revenue ranking | Compatibility/budget filters; versioned heuristic conversion, not a trained predictor |
| FR-021–028 | Negotiations, deterministic floors, rounds, rescue, bulk economics, scoped approvals | Final-floor, bulk, expiry, rescue and round-limit tests |
| FR-029–034 | Versioned policy editor and responsive approval cards | Boundary/precedence tests; mobile approval submission widget test |
| FR-035–038 | Quotes, TTL, stock reservations, checkout revalidation | Expiry, unavailable inventory and concurrent reservation tests |
| FR-039–041 | Real Razorpay adapter, web checkout bridge, HMAC and provider verification | Mocked integration tests; actual provider test checkout is an outstanding credential-dependent gate |
| FR-042–047 | Persisted legal transitions, idempotency, reconciliation, retry and safe counters | Five failure classes covered; uncertain create-order attempt cannot be reissued |
| FR-048–049 | Append-only audit table, explanations and linked transaction timeline | Database immutable triggers installed by migration; domain events persisted |
| FR-050–053 | Exact captured-order attribution, dashboard, discovery and negotiation analytics | Reconciliation repeated without duplicate attribution; filters available |
| FR-054–055 | Versioned REST contracts and provider boundary; documented future protocol adapters | API tests; ACP/AP2/MCP/x402 are intentionally not advertised as implemented |
| FR-056 | Server environment and encrypted per-workspace Razorpay credentials | Secrets excluded from responses and client source; public checkout key only |

## Design and engineering choices

- Flutter uses Riverpod, go_router, Dio, fl_chart, and conditional web checkout interop. Feature folders remain compatible with native UI compilation; native payment checkout needs its own adapter.
- Typed Pydantic contracts protect commerce inputs. Dart uses a shared JSON response boundary rather than generated Freezed response classes. Domain aggregates use SQLAlchemy JSON records instead of a table per workflow state.
- PostgreSQL is the deployment database; SQLite is a documented local development option. Reservations are authoritative database records instead of cache-only Redis keys.
- AI reasoning and deterministic transaction control are separate. Core ranking/growth use explainable heuristics; Nemotron interprets intent and provides merchant-facing negotiation explanations.
- WebSocket notifications trigger workspace refreshes. Session credentials are kept in app memory; a page reload requires signing in again.
- CSV/JSON uploads normalize and persist product data; raw upload object storage, continuous merchant connectors, external buyer mandate systems, and trained conversion models are not included.

## Acceptance still requiring external configuration

Provide server-side NVIDIA and Razorpay test credentials; run a real test checkout with a public webhook endpoint; deploy and exercise PostgreSQL/pgvector plus Redis/Celery; configure HTTPS and backup/secret management; measure latency/availability and perform a full accessibility/browser E2E review. No live-provider results, deployment success, performance certification, or production readiness are claimed from mocked tests.

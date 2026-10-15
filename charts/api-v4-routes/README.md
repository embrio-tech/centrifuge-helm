# centrifuge-api-v4-routes

Stable staging, production, and rollback ClusterIP Services that select Query Pods by
`api-v4.centrifuge.io/query-id`. Optional Traefik Ingress on the public hostnames
reuses existing TLS secrets and sets CORS and CSP at the edge.

| Path | CORS | CSP |
| --- | --- | --- |
| `/graphql` | Registrable-domain regexes for `centrifuge.io`, `centrifugelabs.io`, and `centrifugescan.io`; `centrifuge-kf.workers.dev` previews; `localhost:3000` and `localhost:3003` | `default-src 'none'` (JSON API) |
| `/` (Ruru) | none | `default-src 'self'` with `script-src 'unsafe-inline'` for Ruru startup |

Ingress starts disabled per role until GitOps enables it after the matching route Service
is Ready. Rollback Services have no Ingress.

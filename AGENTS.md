# AGENTS.md - cfg-api-helm

Helm charts for the Centrifuge API platform (repo `embrio-tech/centrifuge-helm`). Published to GitHub Pages at `https://embrio-tech.github.io/centrifuge-helm` and consumed by Argo CD.

There is no application code here. Only charts, Argo CD example manifests, and one release workflow.

## Layout

```text
charts/<dir>/            one chart per dir (dir name != chart name)
examples/                Argo CD Application manifests (reviewed by ops, not applied by CI)
examples/secrets/        commented-out Secret templates (never real values)
.github/workflows/release.yml
```

Example manifests are named `argocd-<application-name>.yaml`, with a `_us` suffix for the us cluster (`destination.name: beta`; eu uses `destination.server`). The `argocd-cfg-api-erpc*.yaml` pair is a snapshot of the live eRPC Applications. Neither sets `helm.releaseName`, so eRPC resource names follow the Application name, which is why those names must stay `cfg-api-erpc` (eu) and `cfg-api-erpc-us` (us): api-v3 reaches them at those hostnames in production.

Per-env Helm values for the public v4 stack live in the app repos, same pattern as `cfg-api-v3/environments/`:

- event-lake: `centrifuge/event-lake` `environments/<network>[-us][-s].yaml`
- public-api + handlers: `centrifuge/backend` `environments/<network>[-us][-s].yaml`

The v4 Argo examples are multi-source: chart from this repo, `valueFiles` from those GitHub repos. Chain lists and registry pins in the event-lake env files follow api-v3.

| Dir | `Chart.yaml` name | Helper prefix | What it deploys |
| --- | --- | --- | --- |
| `charts/api-v2` | `centrifuge-api-v2` | `centrifuge-api` | legacy stack (node/query subcharts). Frozen. |
| `charts/api-v3` | `centrifuge-api-v3` | `centrifuge-api` | Ponder indexer + query + cli + CNPG. Current production. Structural reference. |
| `charts/api-v4-event-lake` | `centrifuge-api-v4-event-lake` | same | Envio indexer producing to Redpanda + own CNPG |
| `charts/api-v4-public` | `centrifuge-api-v4-public` | same | `query` (PostGraphile) + `handlers` (Kafka consumer) + CNPG public-db |
| `charts/redpanda` | `redpanda` | `centrifuge-redpanda` | upstream Redpanda subchart + topic/schema bootstrap Jobs |
| `charts/erpc` | `erpc` | `erpc` | eRPC + Redis + CNPG EVM cache |

Chart dir name and chart name differ. Argo CD `chart:` uses the `Chart.yaml` name; paths use the dir name.

## v4 stack topology

```text
chains -> event-lake (Envio) -> Redpanda (Kafka 9093 + Schema Registry 8081)
       -> chain-event-handlers -> public-db (CNPG) -> public-api (PostGraphile)
```

Per region cluster (`eu` = main, `us` = `beta`), namespace `cfg-api`, Argo project `cfg-api`. Redpanda is shared. Event-lake and public-api are one release each per env stem (`main`, `main-us`, `test`, `test-s`, …).

| Release | Chart | Note |
| --- | --- | --- |
| `cfg-api-redpanda` | `redpanda` | shared by both networks, topics are network-prefixed |
| `cfg-api-v4-event-lake-<name>` | `centrifuge-api-v4-event-lake` | one indexer + one Postgres per env (`main`, `main-us`, `test`, …) |
| `cfg-api-v4-public-<name>` | `centrifuge-api-v4-public` | handlers + query + public-db per env |

Topics: `<network>.protocol-events.speculative` (compacted), `<network>.protocol-events.confirmed`, `<network>.protocol-events-dlq`. 1 partition, RF 3.

## Chart conventions (follow exactly)

1. `Chart.yaml`: `apiVersion: v2`, `type: application`, `appVersion` informational. Never bump `version` by hand, CI does it.
2. External dependencies are not committed. `Chart.lock` is committed; subchart `.tgz` archives are fetched at release time (`scripts/fetch-chart-dependencies.sh`) and gitignored. CNPG charts download from GitHub releases (not `cloudnative-pg.io`, which times out in Actions). For local work run `./scripts/fetch-chart-dependencies.sh` or `helm dependency update charts/<dir>`.
3. Helpers: chart-level `_helpers.tpl` defines `<prefix>.{name,fullname,chart,labels,selectorLabels}`. Each component gets `_helpers-<component>.tpl` with `<prefix>.<component>.*`. Component fullname is `<release>-<component>` unless the release name already contains the component name. Everything truncates at 63 chars.
4. No chart ever creates a Secret. Secrets are pre-deployed by ops and referenced by name through `global.*SecretName`. Non-secret env goes into ConfigMap `<release>-config` rendered from `global.env` as a `pre-install,pre-upgrade` hook.
5. CNPG is the `cluster` subchart v0.3.1 aliased `postgres`, `postgres.enabled: false` by default, configured under top-level `postgres:`. Apps read credentials from `<release>-postgres-app` (keys `uri`, `host`, `port`, `username`, `password`, `dbname`) via the `<prefix>.dbSecretName` helper. Never hardcode the host or db name.
6. `walStorage.enabled: true` on every database. CNPG rejects disabling it on a live Cluster, so never ship it off.
7. Storage class: `ceph-perf3` on the eu cluster, `perf3` on us. Parameterize, set per environment in `examples/`.
8. Deployments: `RollingUpdate` (`maxSurge: 1`, `maxUnavailable: 0`) for stateless components, `strategy: Recreate` for stateful singletons (`indexer`, `handlers`). `resources`, probes, `env`, `envFrom`, `volumes`, `nodeSelector`, `tolerations`, `affinity` are `{{- with }}` passthroughs from values.
9. Images: `image.repository` + `image.tag` (chart default `"latest"`) + `pullPolicy: IfNotPresent`. Production tags are pinned in Argo CD values, never in the chart.
10. Ingress: Traefik, disabled by default, annotations `kubernetes.io/tls-acme: "true"`, `traefik.ingress.kubernetes.io/router.entrypoints: "websecure"`, `nginx.ingress.kubernetes.io/ssl-redirect: "true"`.
11. Always set both `requests` and `limits` in default values.

## Component facts that constrain the templates

**event-lake indexer** (`ghcr.io/centrifuge/event-lake`, port 8080, `GET /health`):
Postgres via split vars `ENVIO_PG_HOST|PORT|USER|PASSWORD|DATABASE`, all `secretKeyRef` into the CNPG app secret. `ENVIO_PG_SCHEMA` is the indexer image tag (same pattern as api-v3 `DATABASE_SCHEMA`). Envio runs its own migrations. Network selection is env only (`CFG_NETWORK`, `SELECTED_NETWORKS`, `REGISTRY_VERSION_MAP`). `ENVIO_RPC_URL_<chainId>` is required per selected chain and is generated in the ConfigMap by the `erpcRpcEnv` helper from `erpc.urlTemplate` (`%s` = chain id), skipping keys already present in `global.env`. `REDPANDA_CLIENT_ID` must be unique per release (`envio-origination-<release>`) because hydration uses a temporary consumer group derived from it. `/health` turns 200 at entrypoint, well before the indexer is caught up.

**handlers** (`ghcr.io/centrifuge/chain-event-handlers`, port 3001, `GET /health`):
`replicaCount: 1` forever, the consumer group id IS `REDPANDA_CLIENT_ID`. Every start waits for `PUBLIC_API_HEALTH_URL`, truncates projection tables and replays Kafka from the beginning, which takes minutes. No TLS and no SASL in its Kafka client, hence plaintext in-cluster Redpanda. Does not run migrations. `PUBLIC_API_HEALTH_URL` must be built from the query fullname helper plus `query.service.port`, not hardcoded.

**public-api / query** (`ghcr.io/centrifuge/public-api`, port 5000, `GET /health`, GraphQL at `/graphql`):
Runs Drizzle migrations at boot, so keep `replicaCount: 1` and a generous `startupProbe.failureThreshold`. `POSTGRAPHILE_DATABASE_URL` from secret key `uri`.

**redpanda**: bootstrap Jobs are `post-install,post-upgrade` hooks, weight `0` (topics, rpk) then `1` (schemas, `cfg-cli events schemas update`, disabled until an event-lake image with cfg-cli is published). Both poll for readiness first because Helm returns before the StatefulSet is Ready, and both must be idempotent. `centrifuge-redpanda.name` is `redpanda-bootstrap`, never `redpanda`: the upstream Kafka Service selects on `app.kubernetes.io/name: redpanda` + instance with no component label, so a Job pod named `redpanda` would join the Kafka, Schema Registry and Admin endpoints while it runs.

## Release engineering

`.github/workflows/release.yml` on push to `main` (chart or release-script changes) or `workflow_dispatch`: bumps patch versions when chart templates change, fetches subchart dependencies, runs chart-releaser (`skip_existing: true`), then commits version bumps. Infra-only changes republish all charts without bumping. Use **Actions → Release Charts → Run workflow** to republish after a failed release.

- Do not bump `version` in a PR, the workflow does it.
- Do not put `[skip release]` in a normal commit, that skips the whole job.
- A published version is immutable. Fix forward with a new patch.

## Local checks (run before proposing a change)

```bash
./scripts/fetch-chart-dependencies.sh
helm lint charts/<dir>
helm template test charts/<dir> --set postgres.enabled=true | less
```

Check the rendered output for: correct `secretKeyRef` names and keys, unique `REDPANDA_CLIENT_ID`, ConfigMap holding one `ENVIO_RPC_URL_<chainId>` per selected chain, no `secretRef` when the optional secret name is empty, CNPG `Cluster` with `walStorage`, Ingress only when enabled, and selector labels that do not collide with subchart Services.

Available locally: `helm` v4, `yq` v4, `kubectl`. No cluster access is assumed. Never run `helm install`, `helm upgrade`, or `kubectl apply` against a live cluster.

## Hard rules

- No Secrets rendered by any chart, ever.
- `handlers` and `indexer`: `replicaCount: 1`, `strategy: Recreate`, no HPA.
- Never raise topic partitions above 1 (ordering) and keep speculative compacted.
- Redpanda Kafka, Schema Registry and Admin stay cluster-internal. No TLS, no SASL (app limitation). Only Console may get an Ingress, and it has no auth.
- No init containers or migration Jobs for public-db. `public-api` owns those migrations.
- Do not modify `charts/api-v2`, `charts/api-v3`, or `charts/erpc` unless the task says so.
- Do not apply the manifests in `examples/`. They are reviewed by ops.
- `PLAN-event-lake-public-stack.md` is the original build brief for the v4 charts. It is historical, the charts are the truth. Sections 7b and 8 still list open work.

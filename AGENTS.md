# AGENTS.md - cfg-api-helm

Helm charts for the Centrifuge API platform (repo `embrio-tech/centrifuge-helm`). Published to GitHub Pages at `https://embrio-tech.github.io/centrifuge-helm` and consumed by Argo CD.

There is no application code here. Only charts, Argo CD example manifests, and one release workflow.

## Layout

```text
charts/<dir>/            one chart per dir (dir name != chart name)
examples/                Argo CD Application manifests (reviewed by ops, not applied by CI)
examples/secrets/        commented-out Secret templates (never real values)
.github/workflows/release.yml
docs/API-V4-RELEASE.md   developer release: origination, handlers, public-api
```

Example manifests are named `argocd-<application-name>.yaml`, with a `_us` suffix for the us cluster (`destination.name: beta`; eu uses `destination.server`). The `argocd-cfg-api-erpc*.yaml` pair is a snapshot of the live eRPC Applications. Neither sets `helm.releaseName`, so eRPC resource names follow the Application name, which is why those names must stay `cfg-api-erpc` (eu) and `cfg-api-erpc-us` (us): api-v3 reaches them at those hostnames in production.

Per-environment desired state for the public v4 stack lives in `centrifuge/api-v4-gitops` `environments/<environment>/`. ApplicationSets pass Producer, Projection, Query, and routes fields as Helm values. Chain lists ride the Producer's merged env: a new Producer authors `SELECTED_NETWORKS` in `global.env` and the chart derives the list; the legacy top-level `selectedNetworks` list and separate `runtimeEnv` map are still accepted during the transition.

| Dir | `Chart.yaml` name | Helper prefix | What it deploys |
| --- | --- | --- | --- |
| `charts/api-v2` | `centrifuge-api-v2` | `centrifuge-api` | legacy stack (node/query subcharts). Frozen. |
| `charts/api-v3` | `centrifuge-api-v3` | `centrifuge-api` | Ponder indexer + query + cli + CNPG. Current production. Structural reference. |
| `charts/api-v4-database` | `centrifuge-api-v4-database` | same | Greenfield CNPG only (public or event-lake kind). Mandatory dedicated WAL. No backups. |
| `charts/api-v4-event-lake` | `centrifuge-api-v4-event-lake` | same | Producer-only origination. Requires `databaseSecretName`. No CNPG. |
| `charts/api-v4-projection` | `centrifuge-api-v4-projection` | same | Handlers only. Owns `pj_*` schema migration. |
| `charts/api-v4-query` | `centrifuge-api-v4-query` | same | Read-only public-api. No migrations. |
| `charts/api-v4-activation` | `centrifuge-api-v4-activation` | same | Fenced SQL activate/compensate Job. |
| `charts/api-v4-routes` | `centrifuge-api-v4-routes` | same | staging/production/rollback Services by Query ID. |
| `charts/api-v4-public` | `centrifuge-api-v4-public` | same | Legacy monolithic public+handlers+CNPG. Pinned on old Applications only until retirement. |
| `charts/redpanda` | `redpanda` | `centrifuge-redpanda` | upstream Redpanda subchart. No indexer generation ids |
| `charts/erpc` | `erpc` | `erpc` | eRPC + Redis + CNPG EVM cache |

Greenfield CNPG ownership is only `centrifuge-api-v4-database`. Workload charts must render zero `postgresql.cnpg.io/*` resources.

Chart dir name and chart name differ. Argo CD `chart:` uses the `Chart.yaml` name; paths use the dir name.

## v4 stack topology

```text
chains -> event-lake (Envio) -> Redpanda (Kafka 9093 + Schema Registry 8081)
       -> chain-event-handlers -> public-db (CNPG) -> public-api (PostGraphile)
```

Per region cluster (`eu` = `alpha`, `us` = `beta`), namespace `cfg-api`, Argo project `cfg-api`. Redpanda is shared. A live Environment is `(main|test)-(eu|us)`. It has one Producer, Projection, and Query (`cfg-api-v4-<environment>-<object-id>`) and two database Applications. Staging and production are routes in that Environment, not separate releases.

| Release | Chart | Note |
| --- | --- | --- |
| `cfg-api-redpanda` | `redpanda` | shared by both networks, topics are network-prefixed |
| `cfg-api-v4-<environment>-pr-*` | `centrifuge-api-v4-event-lake` | one Producer. Postgres is the event-lake database chart |
| `cfg-api-v4-<environment>-pj-*` | `centrifuge-api-v4-projection` | one Projection. Owns schema `pj_YYYYMMDD_NN` |
| `cfg-api-v4-<environment>-q-*` | `centrifuge-api-v4-query` | one Query. Read-only |
| `cfg-api-v4-database-{public\|event-lake}-<environment>` | `centrifuge-api-v4-database` | two Clusters per Environment |

`cfg-api-v4-event-lake-<stem>` and `cfg-api-v4-public-<stem>` (`main`, `main-s`, `test`, `test-s`, …) are the retiring Applications. Do not add values files for them.

Topics are scoped by network and indexer generation (`INDEX_GENERATION`: a Producer id `pr-YYYYMMDD-NN` or `id` plus 12 digits): `<network>.<generation>.protocol-events.speculative` (compacted), `<network>.<generation>.protocol-events.confirmed`, `<network>.<generation>.protocol-events-dlq`. 1 partition, RF 3. A new generation is a new topic triple; the unscoped `<network>.protocol-events.*` topics from before the cutover are left in place and no longer written.

## Chart conventions (follow exactly)

1. `Chart.yaml`: `apiVersion: v2`, `type: application`, `appVersion` informational. Never bump `version` by hand, CI does it.
2. External dependencies are not committed. `Chart.lock` is committed; subchart `.tgz` archives are fetched at release time (`scripts/fetch-chart-dependencies.sh`) and gitignored. CNPG charts download from GitHub releases (not `cloudnative-pg.io`, which times out in Actions). For local work run `./scripts/fetch-chart-dependencies.sh` or `helm dependency update charts/<dir>`.
3. Helpers: chart-level `_helpers.tpl` defines `<prefix>.{name,fullname,chart,labels,selectorLabels}`. Each component gets `_helpers-<component>.tpl` with `<prefix>.<component>.*`. Component fullname is `<release>-<component>` unless the release name already contains the component name. Everything truncates at 63 chars.
4. No chart ever creates a Secret. Secrets are pre-deployed by ops and referenced by name through `global.*SecretName`. Non-secret env goes into ConfigMap `<release>-config` rendered from `global.env` as a `pre-install,pre-upgrade` hook.
5. CNPG is the `cluster` subchart v0.3.1 aliased `postgres`, configured under top-level `postgres:`. Legacy charts keep `postgres.enabled: false` by default. Greenfield CNPG lives only in `centrifuge-api-v4-database`, which always renders the Cluster with `postgres.fullnameOverride` set by GitOps, superuser access off, and `Prune=false,Delete=false` on the Cluster. Apps read credentials from `<release>-postgres-app` (keys `uri`, `host`, `port`, `username`, `password`, `dbname`) via the `<prefix>.dbSecretName` helper. Never hardcode the host or db name.
6. `walStorage.enabled: true` on every database. CNPG rejects disabling it on a live Cluster, so never ship it off.
7. Storage class: `ceph-perf3` on the eu cluster, `perf3` on us. Parameterize, set per environment in `examples/`.
8. Deployments: `RollingUpdate` (`maxSurge: 1`, `maxUnavailable: 0`) for stateless components, `strategy: Recreate` for stateful singletons (`indexer`, `handlers`). `resources`, probes, `env`, `envFrom`, `volumes`, `nodeSelector`, `tolerations`, `affinity` are `{{- with }}` passthroughs from values.
9. Images: legacy charts take `image.repository` + `image.tag` (chart default `"latest"`) + `pullPolicy: Always` for api-v4-public. Greenfield v4 charts (database, projection, query, activation, routes, event-lake 0.2+) take `image.repository@image.digest` only; `image.displayTag` is just the `app.kubernetes.io/version` label. Other charts stay `IfNotPresent`. Production tags and digests are pinned in GitOps, never in the chart.
10. Ingress: Traefik, disabled by default, annotations `kubernetes.io/tls-acme: "true"`, `traefik.ingress.kubernetes.io/router.entrypoints: "websecure"`, `nginx.ingress.kubernetes.io/ssl-redirect: "true"`.
11. Always set both `requests` and `limits` in default values.
12. Greenfield v4 charts ship `values.schema.json` (required identity, patterns, enums) and `ci/*-values.yaml` fixtures, and `scripts/lint-chart.sh <dir>` must pass. Required values default to empty so a release without them fails the schema. Cross-field rules a schema cannot express go in a `validate` helper included from a template that renders nothing else.
13. Greenfield Pods: `automountServiceAccountToken: false`, `enableServiceLinks: false`, `seccompProfile: RuntimeDefault`, no privilege escalation, all capabilities dropped. The Node images (`USER node`) also run with `runAsNonRoot`, `runAsUser: 1000` and a read-only root filesystem with an `emptyDir` on `/tmp`. The event-lake image still runs as root. Pod template labels never carry `helm.sh/chart`, so a chart bump alone does not restart Pods. Env keys a chart derives from identity are refused in `global.env` / `env`.

## Component facts that constrain the templates

Service names follow `centrifuge/api-v4-gitops` `docs/GLOSSARY.md`: origination, handlers, public-api. The chart component keys are `indexer`, `handlers`, and `query`.

**origination**, chart component `indexer` (`ghcr.io/centrifuge/event-lake`, port 8080, `GET /health`, `GET /ready`):
Postgres via split vars `ENVIO_PG_HOST|PORT|USER|PASSWORD|DATABASE`, all `secretKeyRef` into the CNPG app secret. `INDEX_GENERATION` is the generation verbatim. The generation is a Producer id (`pr-YYYYMMDD-NN`, the Producer's own `id`) or `id` plus 12 digits. `ENVIO_PG_SCHEMA` is the generation with `-` replaced by `_` (`pr_YYYYMMDD_NN`; a legacy value is unchanged), and the image refuses to start on any other schema. A `pr-` generation needs an image that accepts Producer-id generations. A missing or malformed generation fails the render. Envio runs its own migrations. Network selection is env only (`CFG_NETWORK`, `SELECTED_NETWORKS`, `REGISTRY_INCLUDE`). `ENVIO_RPC_URL_<chainId>` is required per selected chain and is generated in the ConfigMap by the `erpcRpcEnv` helper from `erpc.urlTemplate` (`%s` = chain id), skipping keys already present in `global.env`. `REDPANDA_CLIENT_ID` must be unique per Producer (`envio-origination-<environment>-<producerId>` in 0.2+) because hydration uses a temporary consumer group derived from it. In 0.2+ `CFG_NETWORK`, `SELECTED_NETWORKS`, `INDEX_GENERATION`, `PRODUCER_ID` and `API_V4_ENVIRONMENT` come from top-level values (`network`, `selectedNetworks`, `generation`, `id`, `environment`), never `global.env`. A `pre-install,pre-upgrade` hook creates this release's topics and schema subjects from `CFG_NETWORK` and `INDEX_GENERATION` before the indexer rolls. It does not render when `indexer.enabled` is false. `/health` is 503 until Envio's `/healthz` answers once, so the startup probe stays active through registry materialization, codegen, and Envio's listen. It then stays 200 while the Envio child exists, including catch-up stalls. The entrypoint exits when the child exits. `/ready` stays 503 until Envio's `envio_progress_ready` gauge is 1 for every chain in `SELECTED_NETWORKS`; the entrypoint reads Envio's `/metrics` on `ENVIO_INDEXER_PORT` (9898) for that. Startup and liveness use `/health`; readiness uses `/ready`. The indexer Service sets `publishNotReadyAddresses` so the Projection gate can poll `/health` before the indexer is Ready. Liveness `failureThreshold` is 18 and `periodSeconds` is 10. Readiness does not restart the Pod. Registry data (heads and ABIs) now comes from `registry.manifest.json` baked into the image, never a runtime registry URL: the chart and the entrypoint both refuse `REGISTRY_URL`, `REGISTRY_URL_MAINNET` and `REGISTRY_URL_TESTNET`, while `REGISTRY_INCLUDE` and `REGISTRY_<revision>_*` (non-ABI) overrides stay allowed. The image also serves `GET /discovery` on 8080 (503 until the effective config is bound, then a schema-versioned snapshot).

**handlers**, chart `centrifuge-api-v4-projection` (`ghcr.io/centrifuge/chain-event-handlers`, port 3001, `GET /health`, `GET /ready`):
`replicaCount` is 0 or 1. The Projection chart accepts a `generation` that is a Producer id (`pr-YYYYMMDD-NN`) or `id` plus 12 digits and uses it verbatim as `INDEX_GENERATION`. The `generation` equals its Producer's generation (for a `pr-` Producer, that Producer's id), which GitOps sets and the chart does not check. The handlers image validates `INDEX_GENERATION` at start, and an image built before Producer-id generations refuses a `pr-` generation and the Pod never becomes Ready, so a handlers image paired with a `pr-` Producer must accept a `pr-` generation. The retiring `centrifuge-api-v4-public` validates `INDEX_GENERATION` as `id` plus 12 digits only. `REDPANDA_CLIENT_ID` is `handlers-<environment>-<generation>-<projectionId>`, and the live consumer group id is that value. Startup migrates `PUBLIC_SCHEMA` (Projection `schema`, `pj_YYYYMMDD_NN`) and replays Kafka from the beginning, which takes minutes. Startup and liveness stay on `/health`. Readiness is `/ready`, which stays 503 until replay finishes and the live consumer is running. `progressDeadlineSeconds` is 21600. No TLS and no SASL, hence plaintext in-cluster Redpanda. The chart does not render a migration Job. The Service sets `publishNotReadyAddresses` and selects only the Deployment Pod (`part-of`, which the hook Pods lack) so the Query gate can poll `/health` before replay finishes. A PreSync Job waits for the Producer `/health` before the Deployment rolls; for the staging gate object (`deploymentReport.enabled`) a PostSync Job holds the staging-ready report until the Producer `/ready`. The Deployment sets `PRODUCER_DISCOVERY_URL` (`http://cfg-api-v4-<environment>-<producerId>-indexer:8080/discovery`) so handlers read their Producer's generation-bound discovery snapshot; the key is reserved and cannot be overridden via `global.env`. Handlers do not read `PUBLIC_API_HEALTH_URL`.

The legacy `centrifuge-api-v4-public` chart still falls back to `handlers.image.tag` (`sha-` plus hex) for `PUBLIC_SCHEMA` when `projection.schema` is empty, and it still sets `PUBLIC_API_HEALTH_URL`. That URL is unused by current handlers.

**public-api**, chart `centrifuge-api-v4-query` (`ghcr.io/centrifuge/public-api`, port 5000, `GET /health` liveness, `GET /ready` startup/readiness, GraphQL at `/graphql`):
Does not migrate. It waits until the Projection schema exists, then introspects. A PreSync Job waits for the Projection `/health` before the Deployment rolls, so the preview is served while handlers still replay. `PUBLIC_SCHEMA` is that `pj_YYYYMMDD_NN` schema. `POSTGRAPHILE_DATABASE_URL` comes from secret key `uri`. Keep `replicaCount: 1`. `QUERY_READ_ONLY=false` is the local-dev migrate switch and must not be set on a release.

**redpanda**: the chart runs the cluster only. It does not take `INDEX_GENERATION` and does not create topics or schema subjects. Each event-lake release does that in a `pre-install,pre-upgrade` hook from its own `CFG_NETWORK` and `INDEX_GENERATION`, using `rpk` for the topics (1 partition, RF 3, speculative compacted) and that release's indexer image for `cfg-cli events schemas update -n -g`. `centrifuge-redpanda.name` stays `redpanda-bootstrap`, never `redpanda`: the upstream Kafka Service selects on `app.kubernetes.io/name: redpanda` + instance with no component label, so a pod named `redpanda` would join the Kafka, Schema Registry and Admin endpoints while it runs.

## Release engineering

Environment promotion for the v4 stack (origination, handlers, and public-api image digests, `INDEX_GENERATION`, staging, then production) is [docs/API-V4-RELEASE.md](docs/API-V4-RELEASE.md). It is written for the developer shipping the change. A new generation does not change the Redpanda release. The workflow below only publishes chart versions.

`.github/workflows/release.yml` on push to `main` (chart or release-script changes) or `workflow_dispatch`: bumps patch versions when chart templates change, fetches subchart `.tgz` into the runner workspace (not git), `helm package --dependency-update=false`, then `cr upload` / `cr index`. Infra-only changes do not bump; already-published versions are skipped. After a failed first publish, run **Actions → Release Charts → Run workflow** with `bump_version` so a new patch is actually uploaded. A published version is immutable.

- Do not bump `version` in a PR, the workflow does it.
- Do not put `[skip release]` in a normal commit, that skips the whole job.
- A published version is immutable. Fix forward with a new patch. CI skips GitHub release tags that already exist, so a failed index after upload cannot reuse that version.

## Local checks (run before proposing a change)

```bash
./scripts/fetch-chart-dependencies.sh
./scripts/lint-chart.sh <dir>        # helm lint --strict + kubeconform per ci/*-values.yaml
helm template test charts/<dir> -f charts/<dir>/ci/<fixture>-values.yaml | less
```

`.github/workflows/lint.yml` runs `lint-chart.sh` on every PR that touches a chart. kubeconform must be on `PATH`.

Check the rendered output for: correct `secretKeyRef` names and keys, unique `REDPANDA_CLIENT_ID`, ConfigMap holding one `ENVIO_RPC_URL_<chainId>` per selected chain, no `secretRef` when the optional secret name is empty, CNPG `Cluster` with `walStorage`, Ingress only when enabled, and selector labels that do not collide with subchart Services.

Available locally: `helm` v4, `yq` v4, `kubectl`. No cluster access is assumed. Never run `helm install`, `helm upgrade`, or `kubectl apply` against a live cluster.

## Hard rules

- No Secrets rendered by any chart, ever.
- `indexer`: `replicaCount: 1`, `strategy: Recreate`, no HPA. `handlers`: `strategy: Recreate`, no HPA, `replicaCount` may be 0.
- Never raise topic partitions above 1 (ordering) and keep speculative compacted.
- Redpanda Kafka, Schema Registry and Admin stay cluster-internal. No TLS, no SASL (app limitation). Only Console may get an Ingress, and it has no auth.
- No init containers or migration Jobs for public-db. Greenfield query does not migrate; handlers own Projection DDL and query waits for it before PostGraphile introspection.
- Do not modify `charts/api-v2`, `charts/api-v3`, or `charts/erpc` unless the task says so.
- Do not apply the manifests in `examples/`. They are reviewed by ops.
- `PLAN-event-lake-public-stack.md` is the original build brief for the v4 charts. It is historical, the charts are the truth. Sections 7b and 8 still list open work.

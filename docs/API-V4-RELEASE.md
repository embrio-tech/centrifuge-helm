# API v4 release

This runbook is for a developer shipping a change to origination, handlers,
public-api, or any combination of them. Topic infrastructure and live Argo CD
administration are outside its scope. This document names the required
prerequisites but does not describe those systems.

## Release model

The application path is:

```text
chains -> event-lake origination -> protocol-event topics
       -> chain-event-handlers -> public-db -> public-api
```

Origination and the public stack are separate Helm releases. Each release reads
one values file from an application repository:

| Release | Values file |
| --- | --- |
| `cfg-api-v4-event-lake-<stem>` | `centrifuge/event-lake` `environments/<stem>.yaml` |
| `cfg-api-v4-public-<stem>` | `centrifuge/backend` `environments/<stem>.yaml` |

A stem is `<network>[-us][-s]`:

- `main` or `test` selects the network.
- `-us` selects the US cluster. No `-us` selects EU.
- `-s` is staging. No `-s` is production.

For example, `main-us-s` is US mainnet staging.

The chart comes from this repository at the Argo Application's
`targetRevision`. The values file comes from the application repository at
`main`. Some staging Applications also carry inline Helm values. Inline values
override the file, so a values PR does not change a pin that the live
Application overrides.

Before preparing a release, check the effective values in the live Argo
Application. The manifests under `examples/` are snapshots for review, not the
deployment source. Do not edit or apply them as a release action.

A merge updates the desired values in git. It starts a rollout only when the
live Application syncs. The example Applications do not enable automated sync,
so do not treat merge as proof that a rollout started.

## Release pins

| Pin | Location | Purpose |
| --- | --- | --- |
| Origination image | event-lake `indexer.image.tag` | Selects `ghcr.io/centrifuge/event-lake` |
| Backend images | backend `handlers.image.tag` and `query.image.tag` | Select the handlers and public-api images |
| Projection schema | backend `handlers.image.tag` | Becomes `PUBLIC_SCHEMA` for both backend pods |
| Public SQL views | backend `publicViews.schema` when `postgres.enabled: true` | Selects the tagged schema exposed through `public` views |
| Ingestion generation | `INDEX_GENERATION` in both values files | Selects the Envio schema and protocol-event topics |
| Envio config hash | event-lake `indexSchemaHash` | Records the generated Envio config accepted by that generation |

Use immutable `sha-<hex>` image tags. The image workflows currently produce
seven-character tags such as `sha-6757123`. The chart accepts any non-empty
hex length after `sha-`, but release values use the workflow's exact tag.
Never pin `latest`.

The public chart derives `PUBLIC_SCHEMA` only from `handlers.image.tag`.
`query.image.tag` does not affect the schema name. Pin both backend images to
the same commit so public-api migrations, handlers, and the schema name form
one release.

On production releases, which own their databases (`postgres.enabled: true`),
set `publicViews.schema` to the same value as `handlers.image.tag`. The chart
refuses to render without it. All staging releases share their region's
production database, keep `postgres.enabled: false`, and do not run the
public-views job.

`INDEX_GENERATION` is `id` plus 12 digits, normally a UTC timestamp:
`idYYYYMMDDHHMM`. It is both `ENVIO_PG_SCHEMA` and the topic-name infix. The
event-lake and backend values for one stem must agree.

## Choose the release shape

| Change | Origination tag | Backend tags | New generation |
| --- | --- | --- | --- |
| Origination code, generated Envio config unchanged | Change | Keep | Not required |
| Origination config or schema changes | Change | Change if consumers changed | Required |
| Handlers, public-api, or public-db | Keep | Change both | Not required |
| New wire event or enrichment consumed by handlers | Change | Change both | Required when the generated Envio hash changes |
| Values only | Only if the image changes | Only if the image changes | Only if the generated Envio hash changes |

Under the current release policy, even a public-api-only change moves both
backend image tags. That creates a new `PUBLIC_SCHEMA` and causes a full
handlers replay. Deploying public-api independently would require a separate
compatibility policy for running a newer query image against an older handlers
schema.

## 1. Merge the application change and wait for images

Merging application code does not deploy it. It may publish images:

- Event-lake publishes when a `main` commit changes `apps/ingestion/**`,
  `packages/**`, `scripts/**`, the workspace or lock files, or the image
  workflow.
- Backend publishes both images when a `main` commit changes
  `apps/chain-event-handlers/**`, `apps/public-api/**`,
  `packages/public-db/**`, the workspace or lock files, or the image workflow.

Both workflows are path-filtered. An environment-only merge does not publish a
new image. Use the workflow's manual dispatch only when an image for the commit
is required and no path trigger ran.

Before using a tag:

1. Wait for the image workflow to finish.
2. Confirm the exact `sha-<7 hex>` tag exists for the intended commit.
3. Require the event-lake image boot check or both backend smoke checks to pass.

These checks prove that the containers start. They do not prove an indexer
caught up or handlers completed a replay.

## 2. Decide whether to rotate `INDEX_GENERATION`

`indexSchemaHash` is the sha256 of the generated Envio `config.yaml` plus
`schema.graphql` for one environment file. It is per file. Do not copy a hash
between regions merely because they use the same generation.

Rotate the generation when that file's generated hash changes. Common causes
are:

- `schema.graphql` or `config.template.yaml`
- registry pins, chain selection, start blocks, or contract patches
- generation scripts or protocol-events inputs that alter `config.yaml`

A handlers or public-api change does not rotate the generation. An origination
code change that renders the same config does not require rotation.

The existing hash check verifies that the recorded hash matches generated
config. It does not compare the branch to its base and therefore does not
enforce that a changed hash also gets a new generation. Review that condition
explicitly.

When rotation is required:

1. Build protocol-events as the event-lake
   `.github/workflows/index-schema-hash.yml` job does. In the event-lake repo:

   ```sh
   pnpm update-registry
   pnpm --filter @centrifuge/protocol-events run generate
   pnpm --filter @centrifuge/protocol-events run build
   ```

2. Assign a new `idYYYYMMDDHHMM` to each affected event-lake values file.
3. Rewrite and review the per-file hashes:

   ```sh
   node scripts/check-index-schema-hash.mjs --write
   ```

4. Set the same generation in the paired backend values file.
5. Sync the event-lake release that carries the new generation. Its
   pre-upgrade hook creates that release's topics and schema subjects from
   `CFG_NETWORK` and `INDEX_GENERATION` before the indexer rolls. The Redpanda
   release does not list generations. The producer disables automatic topic
   creation, so the hook has to succeed before publishing starts.

If the hash command cannot restore generated local files afterwards, run
`pnpm update-registry && pnpm generate` with the root `.env`.

## 3. Prepare staging

Use the staging stem for the network and region being tested. Do not promote a
staging result into a different region without a deliberate decision that the
untested region can move.

Update the effective values, including any live Application overrides.

Event-lake:

- `indexer.image.tag`
- `INDEX_GENERATION`, when changed
- `indexSchemaHash`, when changed

Backend:

- `query.image.tag`
- `handlers.image.tag`, equal to the query tag
- `INDEX_GENERATION`, equal to event-lake
- `publicViews.schema` unset because staging does not own the database

Do not copy complete YAML blocks between environments. In particular, do not
copy `enabled`, `dbSecretName`, `postgres`, storage classes, ingress, or
region-specific RPC settings.

### Staging database layout

Every staging release mounts its region's production Postgres cluster and uses
separate schemas:

- A staging origination process is safe only with a generation different from
  the running production generation in that database.
- A staging handlers process is safe only with a handlers tag different from
  the running production tag.
- `postgres.enabled` stays false.
- `publicViews.schema` stays unset so staging cannot switch production's
  public SQL views.

The advisory locks are database-local:

- Origination locks `envio-origination:<generation>`.
- Handlers lock `chain-event-handlers:<PUBLIC_SCHEMA>`.

A second process on the same key in the same database exits. It does not steal
the lock. Staging must therefore use a generation and handlers tag different
from the running production values. Before production acquires the staging
generation and tag, stop the staging processes and wait for their pods to
terminate.

## 4. Roll out and verify staging

Merge the staging values PRs in one coordinated window. Between the event-lake
and backend merges, the files can temporarily disagree. Do not sync the
affected Applications until both repositories hold the intended generation.

If the live Application has inline values for the image tags or generation,
update or remove those overrides before syncing. A file hidden by an inline
override is not a release.

For a combined origination and backend release, start origination first.
Waiting for origination `/ready` before starting handlers avoids exposing a
long, partially rebuilt projection. Handlers can follow a topic that is still
growing, so do not restart them solely because origination was catching up.
Every restart truncates their schema and replays again.

Verify the effective workload, not only git:

1. Argo reports the intended chart and values revision.
2. The running images match the intended immutable tags.
3. The workload environment contains the intended `INDEX_GENERATION`.
4. Origination `/ready` is 200. `/health` is not sufficient because it becomes
   200 before registry fetch, code generation, migrations, and catch-up finish.
5. Handlers `/ready` is 200. Handlers do not bind `/health` until public-api is
   healthy, and `/ready` remains 503 until replay finishes and the live
   consumer runs.
6. Public-api `/health` is 200 and its `schema` field equals the handlers tag.
7. When `postgres.enabled: true`, the public-views hook job succeeded for
   `publicViews.schema`.
8. Run the change-specific GraphQL or projection checks.

Public-api becomes healthy after migrations, before handlers finish replay.
During a production tag change, GraphQL can therefore serve an empty or
partially rebuilt tagged schema until handlers are ready. Handlers readiness,
not public-api health alone, is the completion signal.

## 5. Promote to production

Create production PRs that copy only the pins proven on the matching staging
stem:

- Event-lake: `indexer.image.tag`, `INDEX_GENERATION`, and the production
  file's own `indexSchemaHash`.
- Backend: `query.image.tag`, `handlers.image.tag`, `INDEX_GENERATION`, and
  `publicViews.schema` when production owns the database.

Do not copy staging's `indexSchemaHash` into another file. Generate and review
the production file's hash. Do not copy staging enablement or database
settings.

Before syncing production:

1. Confirm the images still exist. The event-lake hook creates the generation's topics on sync.
2. Confirm the production event-lake and backend files agree on the generation.
3. Confirm both backend image tags and `publicViews.schema` use the same
   backend tag.
4. Stop any staging origination process that publishes to the production
   generation.
5. On a shared database, stop staging handlers if they use the tag production
   is about to acquire, and wait for the advisory lock to be released.
6. Record the current production pins for rollback.

Sync origination first when it changed. Wait for `/ready`. Then sync the public
release. Production indexer and handlers use `Recreate`; handlers truncate the
selected tagged schema and replay from the beginning.

Repeat the staging verification checklist against production. Previous
generations and tagged schemas remain in place; cleanup is not part of a
release.

## Rollback

Rollback is another values change and another replay. It is not an instant
traffic switch.

- Origination without a generation change: restore the previous image tag.
- Origination with a generation change: restore the previous image tag,
  generation, and that environment's matching hash.
- Backend: restore both previous image tags and `publicViews.schema`. Restore
  the previous generation too if production changed it.

Stop the current origination writer before restarting the previous generation.
On backend rollback, handlers truncate the selected schema and replay, so
public-api can again serve partial data until handlers `/ready` is 200. Verify
the same probes and change-specific queries after rollback.

## Manual promotion and CI automation

Manual promotion currently provides a useful approval point, but the release
state is spread across two repositories and live Argo values. The main manual
failure modes are:

- image tags, generation, hash, and public-views schema do not move together
- a checked-in value is hidden by a live inline override
- staging reuses production lock keys or changes shared database settings
- production moves before the matching staging workload is ready
- a staging origination writer remains active on the production generation
- a production backend tag exposes a partial replay without that being
  understood as part of the rollout

Direct CI writes have different risks:

- committing to a values branch can become a deployment as soon as Argo syncs
- cross-repository changes are not atomic
- a hosted runner cannot see internal `/ready` endpoints without cluster
  credentials
- a generic copy step can move environment-specific settings
- retries can restart handlers and trigger another truncate and replay

The safe automation boundary today is validation plus pull-request creation:

- fail when `indexSchemaHash` changes without `INDEX_GENERATION`
- fail when paired event-lake and backend generations differ
- fail when backend image tags differ
- fail when `postgres.enabled: true` and `publicViews.schema` differs from the
  handlers tag
- fail unsafe staging lock-key reuse
- render the chart with the effective values before merge
- let a bot open a production PR that copies only approved pin fields for one
  stem

Do not let that automation merge or sync production. Full promotion automation
needs one authoritative release manifest, no unmanaged inline overrides,
cluster-visible readiness gates, and a per-environment
lock that prevents overlapping promotions.

## Chart changes

Application images and chart versions are separate pins. If an application
change requires a new chart template or value:

1. Release the chart first.
2. Update the staging Application `targetRevision`.
3. Prove the chart and image together in staging.
4. Update the matching production Application only after staging passes.

Do not mix an unrelated chart-version change into an image promotion.

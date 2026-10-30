# API v4 release

This runbook is for a developer shipping a change to origination, handlers,
public-api, or any combination of them. Topic infrastructure and live Argo CD
administration are outside its scope. This document names the required
prerequisites but does not describe those systems.

Service names follow `centrifuge/api-v4-gitops` `docs/GLOSSARY.md`:
origination is the event-lake process (chart component `indexer`), handlers is
`chain-event-handlers`, public-api is the GraphQL server (chart component
`query`).

## Release model

The application path is:

```text
chains -> origination -> protocol-event topics
       -> handlers -> public-db -> public-api
```

Desired state lives in `centrifuge/api-v4-gitops` under
`environments/<environment>/`. An Environment id is `(main|test)-(eu|us)`:
`main-eu`, `main-us`, `test-eu`, `test-us`. Staging and production are routes
inside that Environment, not separate values files.

**Deploy staging** compares the public GHCR `main` digests for `event-lake`,
`chain-event-handlers`, and `public-api` to the live Producer, Projection, and
Query. A changed digest mints new object ids:

- Event-lake digest: new Producer, new generation, new Projection, new Query.
- Handlers digest only: new Projection and Query on the current Producer.
- Public-api digest only: new Query on the current Projection.

A new Producer copies `runtimeEnv` and `history` from the previous one.
`INDEX_GENERATION` is `Producer.generation`. The Producer chart accepts a
Producer id (`pr-YYYYMMDD-NN`, the Producer's own `id`) or `id` plus 12 digits.
The generation is the Kafka topic infix verbatim, and the chart derives
`ENVIO_PG_SCHEMA` from it by replacing `-` with `_` (`pr_YYYYMMDD_NN`; a legacy
value is unchanged). The event-lake image refuses to start unless
`ENVIO_PG_SCHEMA` is that derived schema, and an image built before Producer-id
generations refuses a `pr-` generation. The Projection copies the generation.
`centrifuge-api-v4-projection` validates `generation` as `id` plus 12 digits,
and the retiring `centrifuge-api-v4-public` does the same for
`INDEX_GENERATION`, so no handlers chart consumes a Producer with a Producer-id
generation.

The event-lake and backend repositories do not carry per-environment Helm
values. Do not add `environments/*.yaml` back there.

Charts come from this repository. Gitops ApplicationSets pass object fields as
Helm values. A merge starts a rollout when the Application syncs. See
`centrifuge/api-v4-gitops` `docs/RUNBOOK.md` for adopt and promote.

## Release pins

| Pin | Location | Purpose |
| --- | --- | --- |
| Origination image | Producer `image.digest` | `ghcr.io/centrifuge/event-lake` |
| Handlers image | Projection `image.digest` | `ghcr.io/centrifuge/chain-event-handlers` |
| Public-api image | Query `image.digest` | `ghcr.io/centrifuge/public-api` |
| Generation | Producer `generation` | protocol-event topic infix; Envio schema with `-` replaced by `_` |
| Projection schema | Projection `schemas.schema` | `pj_YYYYMMDD_NN`, owned by that Projection |

Image workflows publish `sha-<7 hex>` tags. Gitops pins the digest, not `latest`.

## Choose the release shape

| Change | New Producer | New Projection | New Query |
| --- | --- | --- | --- |
| Event-lake image | Yes, new generation | Yes | Yes |
| Handlers image | No | Yes | Yes |
| Public-api image | No | No | Yes |

A higher tier always bumps every id below it in the same pull request. A
handlers-only change stays on the current generation.

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

These checks prove that the containers start. They do not prove origination
caught up or handlers completed a replay.

## 2. Generation follows the event-lake image

A new `INDEX_GENERATION` is a new Producer. Deploy staging assigns a new
generation when the event-lake image digest changes. It does not rewrite a
config hash. The accepted forms and the Projection constraint are in the
generation paragraph under "Release model" above.

A handlers or public-api image does not mint a Producer. Those changes stay on
the current generation.

When the new Producer Application syncs, its pre-upgrade hook creates that
generation's topics and schema subjects from `CFG_NETWORK` and
`INDEX_GENERATION` before origination rolls. The Redpanda release does not
list generations. Origination disables automatic topic creation, so the hook
has to succeed before publishing starts.

## 3. Prepare staging

Dispatch **Deploy staging** in `centrifuge/api-v4-gitops` for the network
(`main`, `test`, or both). The workflow opens one pull request. It does not
change `routes.yaml`.

Do not copy `runtimeEnv`, chain lists, or database settings between
Environments by hand. The workflow copies `runtimeEnv` and `history` only onto
a new Producer in the same Environment.

Staging and production share the regional databases. A Projection owns
`pj_YYYYMMDD_NN`. Advisory locks are database-local:

- Origination locks `envio-origination:<generation>`.
- Handlers lock `chain-event-handlers:<schema>`.

A second process on the same key exits. It does not steal the lock. Production
promotion must not start a second writer on a generation or schema that is
still locked.

## 4. Roll out and verify staging

Merge the gitops pull request. Object Applications auto-sync. The staging
hostname stays on the current `stagingQuery` until **Adopt staging**.

The Projection chart uses a PreSync Job to wait for its Producer `/health`
endpoint, so the Projection Deployment starts as soon as origination is up
instead of after every selected chain reaches head. The Query chart uses the
same PreSync gate against its Projection `/health`, so the preview is served
while handlers still replay. Every handlers restart truncates its schema and
replays.

The staging-ready report is not weakened: for a new Projection a PostSync Job
holds the success report until the Producer `/ready`, so **Adopt staging** still
waits for origination to finish indexing.

Verify the workload, not only git:

1. Argo reports the intended chart revision and object ids.
2. The running images match the pinned digests.
3. Origination has the Producer's `INDEX_GENERATION`.
4. Origination `/ready` is 200. `/health` turns 200 before catch-up finishes.
5. Handlers `/ready` is 200. `/ready` stays 503 until replay finishes and live
   Kafka lag is zero.
6. Public-api `/health` is 200.
7. Run the change-specific GraphQL or projection checks.

Public-api can serve a schema before handlers finish replay. Handlers readiness
is the completion signal for that Projection, and the gate object's Argo health
still requires it before **Adopt staging** reports success.

## 5. Promote to production

Use **Promote** in api-v4-gitops (`docs/RUNBOOK.md`). Production moves the
staging Query and SQL projection. It does not copy hashes between files.

Merging the promotion pull request syncs `cfg-api-v4-routes-<env>`. That Application runs the activation Job before it applies route resources.

Before that sync:

1. Confirm the images still exist. A new Producer's hook creates topics on sync.
2. Confirm the Projection's generation equals its Producer.
3. Record the current production and rollback pointers.

Handlers use `Recreate`. A new Projection replays from the beginning into an
empty schema. Previous generations and schemas stay until retirement.

## Rollback

Rollback is a routes and `activation.yaml` change back to the previous Projection
and Query (`docs/RUNBOOK.md`). Merging the promotion pull request syncs
`cfg-api-v4-routes-<env>`, which runs compensate before route resources. It does
not restore a config hash.

Stop the current origination writer before starting the previous generation
again. Handlers replay the selected schema, so public-api can serve partial
data until handlers `/ready` is 200.

## Promotion automation

Deploy staging opens a pull request from image digests. It does not merge or
sync production. Adopt staging moves `stagingQuery` after the readiness gate.
Promote moves production after review.

Failure modes to watch:

- production moves before the staging workload is ready
- a second origination writer stays on a generation production is about to use
- a handlers restart is treated as instant, while replay is still running

Do not automate production merge or sync from this chart repository. Readiness
gates live in api-v4-gitops.

## Chart changes

Application images and chart versions are separate pins. If an application
change requires a new chart template or value:

1. Release the chart first.
2. Update the staging Application `targetRevision`.
3. Prove the chart and image together in staging.
4. Update the matching production Application only after staging passes.

Do not mix an unrelated chart-version change into an image promotion.

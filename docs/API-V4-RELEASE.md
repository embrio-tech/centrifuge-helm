# api-v4 release

For a developer shipping a change to origination, handlers, public-api, or any combination of them.

Argo CD deploys what the value files name. A merge to `main` in event-lake or backend publishes images and does not change a running environment. Staging is a later pull request against the `-s` value files. Production is a pull request that copies the pins that already ran on staging.

## What is deployed

Two clusters. EU is the main cluster. US is `beta`. Origination and the public stack are one Helm release each per stem.

```text
chains -> event-lake (Envio) -> protocol-events topics
       -> chain-event-handlers -> public-db (CNPG) -> public-api (PostGraphile)
```

| Release | Chart | Values |
| --- | --- | --- |
| `cfg-api-v4-event-lake-<stem>` | `centrifuge-api-v4-event-lake` | `centrifuge/event-lake` `environments/<stem>.yaml` |
| `cfg-api-v4-public-<stem>` | `centrifuge-api-v4-public` | `centrifuge/backend` `environments/<stem>.yaml` |

Stems are `<network>[-us][-s]`: `main` or `test`, `-us` for the US cluster, `-s` for staging. No `-s` is production. `main-us-s` is US mainnet staging. One region does not have to move with the other.

The chart comes from this repo at the Application's `targetRevision`. The value file comes from the app repo at `main`. Argo rolls out whatever is merged there.

## The pins

These are separate. Moving one does not move the others.

| Pin | Where it is set | What it selects |
| --- | --- | --- |
| Origination image | event-lake `indexer.image.tag` | `ghcr.io/centrifuge/event-lake` |
| Handlers and public-api image | backend `handlers.image.tag` and `query.image.tag`, the same `sha-` | `ghcr.io/centrifuge/chain-event-handlers` and `ghcr.io/centrifuge/public-api` |
| Ingestion id | `INDEX_GENERATION` in both value files for that stem | The Envio schema, the topics origination writes, and the topics handlers read |
| Chart version | Application `targetRevision` | The Helm templates. Not the running image. Ops, not this flow. |

`INDEX_GENERATION` is `id` plus 12 digits (`id202610060845`). The files use `id` plus UTC `YYYYMMDDHHMM`. It is the Envio Postgres schema (`ENVIO_PG_SCHEMA`) and the topic infix `<network>.<id>.protocol-events.*`. A new id is a new set of topics. The previous id stays where it is.

The public chart sets `PUBLIC_SCHEMA` from `handlers.image.tag` on both the handlers pod and the query pod. That tag is the Postgres schema public-api migrates and handlers write. The chart rejects a handlers tag that is not `sha-` plus hex. Pin query to the same `sha-` so the migrations and the consumer are one commit.

## 1. Images exist before a value file names them

Event-lake `.github/workflows/docker-publish.yml` pushes `ghcr.io/centrifuge/event-lake:sha-<7 char>` on a push to `main`.

Backend `.github/workflows/docker-publish.yml` pushes `ghcr.io/centrifuge/chain-event-handlers:sha-<7 char>` and `ghcr.io/centrifuge/public-api:sha-<7 char>` on a push to `main`. Both tags are the same seven characters from that commit.

Take the tag from the workflow. `latest` is also pushed and is not a deploy pin.

## 2. Rotate the ingestion id when the index cannot reopen

`indexSchemaHash` on an event-lake value file is the sha256 of generated `config.yaml` plus `schema.graphql` for that file. Envio will not reopen an existing schema against a different config. Event-lake `.github/workflows/index-schema-hash.yml` fails the pull request until the stored hash matches. The check's failure text is the rule: `INDEX_GENERATION` changes together with `indexSchemaHash`.

The hash moves when the generated indexer config moves: `schema.graphql`, `config.template.yaml`, the generate scripts, registry pins, `SELECTED_NETWORKS`, contract patches, or protocol-events inputs that change the rendered config. A handlers or public-api image does not move it. An origination image that leaves the rendered config identical does not need a new id.

When it does move:

1. Pick a new id.
2. Set it on every event-lake value file whose hash changed, then rewrite the hash from the event-lake repo:

   ```sh
   node scripts/check-index-schema-hash.mjs --write
   ```

   The script fetches each file's registry and generates config. It needs the same protocol-events build the workflow uses.
3. Set the same id on the paired backend value file. Handlers read `<network>.<id>.protocol-events.*`. A mismatch replays the wrong topics.
4. Hand the id to ops before merging. The topics and schema subjects for a new id are created on the cluster, outside these two repos. An indexer that starts before they exist creates them itself with the wrong replication.

A handlers-only or public-api-only change skips this section. The new `sha-` is already a new `PUBLIC_SCHEMA`, and handlers replay the existing topics into it.

## 3. Pin staging

Edit the `-s` value files for the stem you are proving. Merge to `main` is what Argo rolls out.

Event-lake file:

- `indexer.image.tag` = the event-lake `sha-`
- `INDEX_GENERATION` and `indexSchemaHash` when step 2 ran

Backend file, same stem:

- `INDEX_GENERATION` equal to the event-lake file
- `query.image.tag` and `handlers.image.tag` = the same backend `sha-`

US staging (`main-us-s`, `test-us-s`) has its own Postgres, so the indexer and handlers run beside production. It publishes to the same cluster as US production. The same `INDEX_GENERATION` is the same topics, and a second indexer publishes onto them. Give staging its own id when the proof must not write the topics production is publishing.

The origination entrypoint holds `pg_try_advisory_lock` on `envio-origination:<id>` in the database it is connected to. That lock does not cross clusters or databases. Handlers hold `chain-event-handlers:<tag>` the same way. A second process on the same key in the same database exits.

EU staging (`main-s`, `test-s`) mounts the production database and does not create one.

- Leave `indexer.enabled: false` while the file would use an id the production indexer on that database already holds. A new id is a new Envio schema and a new lock key, so EU staging can run beside production only on an id production is not using.
- Leave `handlers.enabled: false` while `handlers.image.tag` is the tag production handlers already hold. Enabling it takes the lock and, if it wins, truncates the production schema on startup. A new tag is a new schema in that database.
- Query on EU staging reads `PUBLIC_SCHEMA` from the handlers tag in the file even when handlers are off. A tag handlers have not replayed serves an empty schema.

Handlers truncate the schema named by their tag and replay from the start of that id's topics, then follow the live consumer. `/ready` stays 503 until that finishes. `progressDeadlineSeconds` is 3600. They wait for public-api `/health` before replaying. Query stays at one replica and migrates `PUBLIC_SCHEMA` on boot.

If handlers started while the indexer was still filling the topic, restart them after indexer `/ready` is 200. Every start rebuilds from what is on the topic at that moment.

Indexer `/health` is 200 from entrypoint, before catch-up. `/ready` is 200 only when every chain in `SELECTED_NETWORKS` has `envio_progress_ready` at 1.

## 4. Promote to production

Staging is ready when:

- indexer `/ready` is 200
- handlers `/ready` is 200 after that replay
- public-api `/health` is 200

Copy the proven pins onto the production stem for that network and region. `main-us-s` goes to `main-us`, `main-s` goes to `main`, and the same for `test`.

- Event-lake: `indexer.image.tag`, and `INDEX_GENERATION` plus `indexSchemaHash` if they changed
- Backend: `query.image.tag` and `handlers.image.tag` together, and `INDEX_GENERATION` only when staging is on a new id that the event-lake production file names too

Production indexer and handlers use `Recreate`. Handlers replay again into the schema named by the new tag. Previous ids and previous `sha-` schemas stay.

## What does not move together

- Origination bugfix, rendered config unchanged: event-lake `indexer.image.tag` only. Keep the id. Envio reopens the schema. Do not start a second indexer on that id in the same database.
- Handlers or public-api only: both backend tags. Keep the id and the origination tag. The new tag is a new projection schema and a full replay of the current topics.
- New event shape: a new id when the hash moved, then the origination pin, then both backend tags. Handlers replay only what that id's topics contain.

## Manual pins vs CI

Promotion is a reviewed edit of git, and Argo deploys it because the value files track `main`. Automating that step means a workflow writing those files. The question is which writes are safe to make from CI, and which ones are an incident if the workflow is wrong.

Five views, on this stack only.

**SRE.** Every handlers start truncates `PUBLIC_SCHEMA` and replays. Query reads that same tag, so GraphQL moves to the new schema as soon as the public release syncs, and stays empty until `/ready`. A prod pin is a planned outage of that stem, measured in the replay, with `progressDeadlineSeconds` at 3600. EU staging is the production database. `handlers.enabled: true` on the production tag takes `chain-event-handlers:<tag>` and truncates production. `indexer.enabled: true` on the production id takes `envio-origination:<id>` and the production indexer loses the lock. Those two flags are not image pins. A workflow that "updates staging" by copying a US file onto an EU file copies them. A retry of that workflow truncates again.

**Kubernetes.** The two Applications sync separately. Nothing in the cluster orders origination before handlers. Indexer `/ready` is not on a public ingress. A GitHub-hosted runner cannot see it. `/health` is 200 from process start, so a workflow that polls health will promote a backfill. `/ready` stays 1 once Envio has reached the head and does not clear, so it proves catch-up only on the pod that just started.

**Release.** The pins sit in two repositories. A staging proof on US mainnet is four files if both images move (`main-us-s` in each repo). Forgetting the backend id replays the previous topics. Forgetting to keep `query.image.tag` equal to `handlers.image.tag` is allowed by the chart: only the handlers tag is `PUBLIC_SCHEMA`. Promoting `main-us-s` into `main.yaml` moves the EU production stem that never ran the image. The useful automation is a pull request that copies pin fields for one stem. Merging it stays a person, because merge is the deploy.

**IaC.** A new id needs topics that neither repo creates. Nothing in the two pull requests shows in review that they exist. The chart checks that fail the render (`INDEX_GENERATION` shape, handlers tag shape) run at sync, which is after merge.

**Helm.** Render-time refusal is the right layer for shapes: `INDEX_GENERATION` must match `id` plus 12 digits, handlers tag must match `sha-` plus hex. Event-lake CI already fails a value file whose `indexSchemaHash` does not match generated config. It does not fail a hash update that leaves the old id in place, which is the case Envio refuses to reopen. Duplicating those rules in a GitHub Action drifts from the templates. New checks belong in the chart or in the existing hash job, not in a third copy.

### What manual gets wrong

- The id differs between the event-lake file and the backend file. Handlers replay the wrong topics.
- `indexSchemaHash` is rewritten and `INDEX_GENERATION` is not. CI is green. Envio will not open the old schema.
- A new id is merged before its topics exist. The indexer creates them with the wrong replication.
- US staging keeps production's id, so the proof indexer publishes on production topics.
- An EU `-s` file is saved with `enabled: true` on the production id or the production handlers tag.
- Query and handlers tags diverge.
- Production is pinned from memory, without indexer `/ready`, handlers `/ready`, and public-api `/health` on that stem.
- Handlers are left up from before the indexer caught up, so the replay missed the tail.

### What CI automation gets wrong

- A job that commits to `main` deploys. There is no second step.
- A job that always rotates `INDEX_GENERATION` forces a full reindex and leaves the old topics behind. A job that never rotates double-publishes on the current topics, or crashloops Envio when the hash moved.
- A job that sets image tags cannot see `/ready` without a path into the cluster. Giving it that path means cluster credentials on every promotion.
- Cross-repo pulls are two merges. The check on the first is stale when the second lands. Between them the stems disagree.
- A job that rotates the id cannot create its topics from either repo. The merge lands before they exist.
- A generic "update every `-s` file" does not know that EU staging shares the production database. Copying `enabled` is the production incident above. Retries repeat it.
- Auto-promoting every production stem because one region's staging went ready ships an image the other region has not run.

### What to automate, and what to leave

Automate refusal, on the pull request, in the repo that holds the field.

- Keep the hash job and the chart's tag and id checks.
- Fail an event-lake value change that updates `indexSchemaHash` without changing `INDEX_GENERATION` relative to the base branch.
- Fail a backend value file whose `query.image.tag` and `handlers.image.tag` differ.
- Fail an EU `-s` file when `indexer.enabled` is true and `INDEX_GENERATION` equals the paired production file, or when `handlers.enabled` is true and `handlers.image.tag` equals the paired production file.

Leave the write to a person while EU staging mounts the production database and while a new id's topics are created outside the two repos. After that, a workflow may open the production pull request by copying pin fields for the one stem that was proved. It copies `indexer.image.tag`, `INDEX_GENERATION`, `indexSchemaHash`, `query.image.tag`, and `handlers.image.tag`. It does not copy `enabled`, `dbSecretName`, or `postgres`. It does not merge. The pull request states the three probe results. CI has not observed them.

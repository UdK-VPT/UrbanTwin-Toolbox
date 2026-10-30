# UrbanTwin-Toolbox Project Briefing for agents

Read this file first when returning to the project. Keep all project, component and
documentation instructions here; do not create nested instruction files. Keep
development compatible with Windows and production/testing compatible with Linux.

Agents must follow the guidelines in this file for every implementation and review.
This is the authoritative repository instruction file. Other guides, implementation
logs and existing code do not override these guidelines. Explicit user instructions
take precedence.

## Response style

Keep final answers concise: normally 5–15 sentences or at most five short bullets.

## Direction and design priorities

UrbanTwin-Toolbox is a 3DCityDB v5-based urban digital twin centered on
PostgreSQL/PostGIS. The `mirror` and `utt` workflows should remain primarily inside
PostgreSQL so the team can understand, discuss and maintain them together.

- Prefer the smallest readable set of functions, tables and columns that preserves
  correctness and clear responsibilities. Add objects only for concrete current uses.
- Always use clearly readable, explanatory names for tables, columns, schemas,
  views, routines, constraints and other database objects, including generated ones.
  Do not put hashes, opaque codes or generated numeric identifiers in object names.
  Resolve naming collisions with meaningful names or an explicit readable name.
- For each new feature, suggest and introduce the minimum number of tables and
  columns. Extend existing structures and tables wherever possible instead of
  building parallel structures. Keep changes to existing structures minimal and
  focused; justify new structures by concrete needs existing structures cannot serve.
- Keep metadata tables for temporal, provenance and lineage modelling to ten or
  fewer in total across the model wherever practical, rather than per feature.
  Keep columns focused and minimal, with no fixed column-count limit; these tables
  may have more than ten columns. Preserve correctness and do not hide complexity
  in JSON or overloaded columns to meet the table-count target. Make additions and
  their effect on this total explicit when proposing structural changes.
- Keep database structures understandable to contributors with PostgreSQL basics.
  Use clear names, concise comments and a few worked SQL examples. Do not hide
  complexity in opaque JSON, overloaded columns or oversized routines.
- Prefer PostgreSQL, PostGIS, constraints, views and suitable extensions over external
  workers. Add an external component only for a demonstrated database/extension gap,
  and keep it small and explainable.
- Use a unitemporal model: system time (`utt_txn tstzrange`) is the only general
  temporal axis for mirror and curated history. Keep original source dates as
  ordinary attributes; do not infer valid-time ranges or add a second time axis.
  Avoid redundant timestamps.
- Existing interfaces describe the current implementation. Check their callers before
  replacement or removal. This is a changing prototype: existing database contents
  need not be preserved, and fresh initialization is the implementation target. Do
  not write migration SQL or compatibility code for existing databases until the
  user explicitly starts that phase. Prefer focused edits to existing files over
  wholesale rewrites so contributor history remains readable.

## Repository and runtime

- `compose.yml` runs UTTDB and pgAdmin. UTTDB uses the locally built
  `utt/database:local` image from `custom-db-docker-image/`, based on 3DCityDB v5.
  The image provides `ogr_fdw`, `postgres_fdw`, `http` and PostGIS Raster.
- Upstream database and pgAdmin images are pinned by digest. Keep the Compose database
  digest synchronized with the Dockerfile default when updating it.
- On a fresh database, `900-utt-init.sh` processes `uttdb/init/` in filename order
  after upstream PostGIS/3DCityDB initialization. Editing init SQL does not update an
  existing database.
- Runtime settings and credentials belong in ignored `.env`, copied from
  `.env.example`. Images, build settings, container names, internal ports, mounts and
  service modes belong in `compose.yml`.
- Keep `uttdb/data/`, `pgadmin/data/`, `.env` files and original datasets out of Git.
  Original datasets belong in `uttdb/source-files/`, mounted read-only at
  `/source-files`, and require separate backups.
- Use LF for text and shell/PowerShell scripts; Windows batch files use CRLF.

## Documentation rules

- Keep five concise guides: `docs/welcome.md`, `docs/uttdb.md`,
  `docs/metadata-modelling.md`, `docs/pgadmin.md` and `docs/architecture.md`.
  `welcome.md` links the guides, `docs/glossary.md` and the workflow/object inventory
  in `docs/database-reference.md`; the root README contains the Compose quick start.
- Use standard Markdown, relative links and Mermaid for architecture diagrams.
- Document current implementation. Keep roadmaps and speculative functionality out
  of the implementation guides.
- Prefer readable structures and a few practical SQL examples. Keep detailed
  interfaces in SQL comments instead of duplicating them throughout the guides.
- Describe temporal history using system time consistently. Distinguish ordinary
  source-date attributes from the system-time axis; do not describe this model as
  bitemporal.
- Keep design decisions as actionable rules here. Keep `docs/metadata-modelling.md`
  human-facing: explain the current model, responsibilities and examples without
  duplicating agent instructions.
- Document object maintenance responsibilities and allowed human edits, distinguishing
  mixed configuration tables from system-maintained history. Identify administrative
  entry points, read-only interfaces and internal helpers/triggers, with their actual
  callers, roles and transaction requirements. Intended future frontend use does not
  itself authorize access, new wrappers or privilege changes.
- Documentation commands run from the repository root unless stated otherwise.

## Database rules

- Keep UTT-owned implementation objects out of `public`; use the project schemas
  according to their responsibilities.
- Put UTTDB cross-schema routines in `utt_pkg`. Prefix mirror routines `mirror_`.
  Reserve `curate_` for routines that perform curation; read-only historical readers
  use `<entity>_at(timestamp)`, `provenance_at(entity, timestamp)` and
  `relation_at(type, timestamp)` without that prefix. Internal curation helpers and
  trigger functions use `curation_` so they are distinct from workflow entry points.
- Add a PostgreSQL `COMMENT` to every UTT-owned function or procedure. State its
  purpose, caller, effects, result and a practical SQL example. A trigger-function
  example must show the operation that fires it.
- Use NOLOGIN group roles as the stable privilege surface. Give developers sandbox
  schemas instead of broad curated-schema write access.
- Add routines only for concrete integrity, privilege, transaction or reuse
  boundaries; prefer direct SQL, constraints and privileges when sufficient.
- Preserve published source metadata in its original language and wording. Leave
  absent values `NULL`; do not infer license rights. Registry `fees` and
  `access_constraints` retain service-level statements verbatim.
- Curated writes require explicit curation/diff workflows. Preserve narrow write
  privileges until a replacement boundary is designed.
- Keep changes small and independently usable. Document practical calls in
  [docs/uttdb.md](docs/uttdb.md) and routine comments.
- Use rollback-only database checks where practical. Distinguish repository changes
  from changes applied to a running database. Do not add migration files or plan live-data
  conversion until the user explicitly requests the migration phase.

## Source capture and acceptance rules

- Keep mirror usable independently of domain curation: registration, ingestion,
  acceptance, history, refresh and retirement must not require curation objects or
  routines. Curation depends on an initialized mirror with accepted inputs for its
  mappings; registration alone does not supply data. Keep this dependency one-way,
  while coordinating publication and curation through the documented locking boundary.
- Capture heterogeneous source data before optional domain curation. Preserve original
  attributes and geometry; harmonize only for a concrete domain and application.
  Treat CityGML/3DCityDB as an interoperability interface, not a mandatory copy of
  every research attribute. Do not add speculative domains or execution platforms.
- Keep source/import metadata in `mirror` and mapping/provenance metadata in `utt`.
  Reuse the five shared metadata tables: registry, import, source_columns,
  curation_mapping and curation_provenance. Do not add parallel file registries,
  review tables, permanent change sets, transformation catalogues or execution logs.
- Register dataset/layer identity as `(source_name, layer_name)`, not just an endpoint
  or path. Use immutable registry `row_id` references. Never delete or repurpose a
  referenced registration; retire it. Keep referenced imports and schemas available.
  Enforce one storage mode per identity and one registration for database-row sources.
- For each row source, use a read-only `_source` adapter, one pending `_staging`
  snapshot, one `_stored` history table and an ordinary read-only current view.
  Registry-controlled base names must be unique across registrations and readable.
  Normalize source/layer words without hashes or truncation, reject bases over
  48 bytes and reject collisions explicitly. Keep native provenance partition names
  stable across registry versions of the same logical file dataset.
  Current views must not duplicate storage or expose write access through base tables.
- Preserve source columns, types and values in staging; do not filter, curate or add
  technical version columns there. Keep revision evidence separately. Document
  unavoidable adapter conversions and resolve source/technical name collisions
  explicitly without discarding original fields.
- Require explicitly configured non-NULL unique stable keys before row ingestion;
  never use physical row positions. Compare full source state, including geometry.
  Any optional content hash must cover that state and exclude generated metadata.
  Preserve ordered composite-key columns and the canonical JSON-array-as-text `utt_key`
  representation. Accepted key definitions are immutable; reject and re-stage pending
  imports before changing their key definition.
- Use `mirror.import` for staging and accepted history, with at most one pending
  snapshot per dataset. Capture source location, registered coverage, revision and
  schema evidence with the snapshot. Only acceptance starts system-time history.
- Automatically accept structurally valid snapshots when thresholds pass unless
  manual review was requested; otherwise retain staging for review. Manual acceptance
  may override thresholds, never integrity checks, and must publish the inspected
  snapshot without refetching. Serialize publication per dataset and revalidate the
  change set against current accepted state before a delayed acceptance.
- Preserve row-count and per-column NULL-count safety checks using
  `change_threshold_percent` (default 1%); first imports have no count baseline.
  Thresholds are the size/count safeguard for suspicious full-snapshot updates.
  They do not certify correctness. Structural errors retain
  staging just as threshold failures do; failed source reads record failed attempts.
- Preserve the self-contained GeoTIFF adapter's 256 MiB input-file limit and in-memory
  decoding requirement. Use deterministic `rid` tile keys and complete tile inventories;
  validate grid, band metadata and valid-pixel counts. Changed grids require review,
  and accepted complete replacements may close removed tiles.
- Publish version changes, accepted-import evidence and registry summaries atomically,
  using one timestamp for all boundaries in an import. Failed/pending imports must
  not change accepted state. Keep accepted imports immutable, including no-op imports;
  unchanged source versions retain their creating import. Rejected/failed attempts
  cannot be creating imports. Record failures after publication rollback separately.
- Remove staging and clear its live relation reference after acceptance or rejection;
  keep it while pending. Reuse the same import row throughout, without metadata copies.
- Keep advertised revisions separate from evidence tied to accepted data. Store NULL
  without reliable association; later metadata responses cannot prove an earlier
  snapshot's revision. Registration/capture times do not date real-world changes.
- Treat every mirror row ingestion as the full snapshot of its registered source
  scope. On acceptance, close all current source versions whose stable keys are
  absent; do not require a completeness flag or support partial/delta imports.
  Threshold failures retain staging for review without changing accepted history.
  Explicit manual acceptance can approve a smaller or empty snapshot and close its
  missing objects. Read failures never publish absence. Closure records source
  disappearance, not real-world termination or automatic curated-entity retirement.
  Do not repurpose accepted keys or registered scope.
- Reuse identical source column-definition sets within each registration, including
  older matching sets; do not insert duplicate definitions for unchanged imports.
  Compare the full set of names, order, types/modifiers, collation and descriptions
  with ordinary SQL, without hashes or another table. Each import must retain its
  exact `structure_version` reference to `mirror.source_columns`. Serialize capture
  per registration to prevent duplicate sets under concurrent staging.
- Retain immutable schema definitions and comments so absent columns, historical
  NULLs, renames, units and meaning changes remain interpretable. Support additions
  and removals; use a new column or dataset for incompatible type/collation or meaning
  changes rather than rewriting history. Document normalization, units, CRS/elevation,
  NULL meanings and identifier scope. Prefer comments and existing code lists over
  additional registries; priorities are preferences, not accuracy/confidence scores.
  Preserve removed physical columns for history while excluding them from current
  views; additions leave historical rows NULL. Schema layout/comment changes must
  version incoming records as needed to retain correct creating-import/schema evidence,
  even when values match. Resolve dependent-view conflicts explicitly; do not cascade
  away dependencies to recreate a changed current view.
- Keep batch refresh as a top-level procedure outside explicit transaction blocks,
  committing each active dataset separately. Skip pending imports and recent successful
  acceptances (`skip_interval`, default one hour; NULL disables the freshness skip).
  Refresh existing registrations without discovering new layers. Preserve earlier
  commits on later failure; metadata HTTP/XML errors stop the batch, while source-read
  failures are recorded as failed imports.

## Native-file rules

- Keep external-file reference history directly in `mirror.registry`, with immutable
  row identity, path/namespace, format, size, checksum/algorithm, `utt_txn` and creating
  import. Do not require geometry, conversion, a foreign table or payload decoding.
  Give independently versioned files separate logical identities, not JSON file lists.
  Do not invent relational column schemas for opaque native files; retain format and
  available published structure metadata instead.
- Permit an initial unaccepted registration without an open history range. Refresh
  resolves current logical identity; imports/mappings reference exact registry rows.
  Stage file evidence through the same import lifecycle without overwriting accepted
  metadata. Identify the path's server/mount namespace; use `/source-files` in containers.
- Keep staged files unchanged and revalidate readability/checksums before acceptance;
  do not silently accept newer bytes at a reused path. Changed bytes or registered
  state create replacement versions; unchanged references create only an import.
  Modification times alone are not change evidence. Missing/unreadable files fail
  ingestion and never imply automatic withdrawal.
- Retain accepted native files unchanged at version-specific paths for historical
  byte access, with separate retention/backups. Checksums cannot restore lost bytes;
  database rollback cannot undo filesystem changes. Rejecting a manifest must not
  delete source files. Native time coordinates remain ordinary source metadata.
- Preserve the named `sha256-chain-1m-v1` file-checksum contract and bounded-memory
  1 MiB block processing; it is not conventional whole-file SHA256. Keep the exact
  algorithm in the routine comment and do not silently change it under the same name.
  Restrict administration of source files and symlinks to trusted DBAs.
- Curation of native contents requires an approved format-specific reader and exact
  accepted-file provenance. Keep filesystem helpers small; acceptance/history stay SQL.

## Temporal curation rules

Apply the rules below when changing history, mappings, provenance or relations.
The [metadata guide](docs/metadata-modelling.md) explains their behavior to users.

- Each version has immutable `row_id`, repeatable logical identity and mandatory
  `utt_txn tstzrange`. Use nonempty half-open ranges with finite openings and
  non-overlapping system time per logical identity enforced with GiST exclusion
  constraints. Current versions have unbounded endings. There is no generic source_valid.
- Keep original source dates as ordinary attributes; do not infer valid-time ranges
  or reject changed state because a source date moved backwards.
- Compare every managed attribute, including geometry and mapped dates. A changed
  state closes the former system-time version and inserts its replacement at one
  timestamp. Historical attributes are never overwritten.
- Active mapping groups must be equal or disjoint. Definitions are immutable except
  for activation. Approved SQL rule identities version behavior; never store SQL
  transformations or a JSON rule language in metadata. Lower numeric priorities win,
  followed by mapping ID and stable source key. Normalize group sets and reject empty
  or duplicate members. Changed columns, priority, source or behavior need new revisions.
- Validate mapped columns/types against catalogs and compatible units, code meanings,
  CRS and matching IDs; do not infer automatic CRS conversion. Exclude generated
  version metadata from managed state. Missing columns in the latest accepted schema
  make mappings ineligible, even if historical physical columns remain.
- Preserve the six Berlin rule contracts: usable geometry with nullable descriptive
  values, including block datum/plot beg as source_date and address aufn_dt as
  address_date. Direct rules cast named column pairs and require all group members;
  sum rules aggregate by explicit matching ID only from complete contributors.
  Additional transformations require new approved SQL rule identities.
  Preserve positional source/target column pairing when normalizing group sets;
  casts alone do not establish equivalent identifier meanings.
- Provenance records exact selected contributors, not every rejected candidate.
  Changed output records every group on a new target version, including carried
  groups. Changed origins alone append complete observations without versioning
  output. Unchanged source versions and selection create no new observations.
  Losing candidates and advertised revision changes alone must not version output.
  Keep the original accepted import for carried origins, including noncurrent inputs.
- Record one provenance contribution per source record/group, not per attribute, with
  exact mapping, named stable key (small JSONB composite keys are allowed), source
  version, accepted import, observation time and factual selection reason. Do not copy
  input values or rejected candidates. Write complete contributor sets atomically
  with strictly increasing observation times per target/group and prevent duplicates.
- Keep generic target_table/target_row_id references; do not add per-entity provenance
  columns. Validate mapping/table agreement, lock/check the target row and require
  observation time within its range. Protect target history from deletion/truncation.
  Use per-source provenance partitions for genuine source-history foreign keys and
  registry-version FKs for file origins; do not duplicate source data in partitions.
- Without eligible replacements, retain state and its exact former origins.
  Withdrawals/retirement require explicit domain semantics; missing sources are not
  automatic domain deletions. Group-boundary replacements must cover former groups
  completely, preserving historical definitions. Deactivate old and install replacement
  groups in one transaction, then re-curate; reject partial regrouping. New observations
  supersede overlapping groups without reinterpreting earlier ones. Splits, merges
  and cross-source identity changes also require explicit domain decisions.
- Spatial relations connect immutable endpoint versions whose system-time ranges
  overlap. Backfill missed historical pairs and insert only absent pairs; derive time
  from endpoints without another axis. Use endpoint `row_id` foreign keys, not
  repeatable logical IDs; logical relationship attributes may remain NULL or
  unconstrained where no unique version target exists. Keep technical source keys
  distinct from official relationship identifiers. Divide intersection area by the
  first endpoint's area (building for building/block and building/plot; plot for
  plot/block). Round intersection fractions to three decimals
  and retain only values above 0.02. Run relation curation explicitly after endpoint
  curation; entity writes do not update relations automatically.
- Provide read-only current views and as-of queries without additional history tables.
  As-of provenance selects the target version and latest complete group observations
  using historical mapping definitions, never today's activation. Keep multiple
  contributors separate from flat entity rows to avoid multiplying counts/areas.
  Use current-row partial, stable-key, spatial and appropriate historical indexes;
  check plans on representative data.
- Pipeline writes go through security-definer curation boundaries. Mapping edits,
  curation and relation writes share advisory transaction lock (70303,1). Curation
  also locks mirror.registry EXCLUSIVE while reading accepted inputs; this coarse
  publication boundary deliberately favors correctness over concurrent ingestion.

## Implementation locations and validation

- `901-setup-structures.sql`: schemas and extensions; `902-create-privilege-roles.sql`:
  group roles and developer sandboxes; `903-mirror-setup.sql`: ingestion/history;
  `912-utt-buildings.sql`: six entities, three relations and metadata tables;
  `913-curation.sql`: mapping validation, rules, provenance, curation and readers.
- Use [example/berlin.sql](example/berlin.sql) for the public six-layer workflow.
  Run SQL suites in `tests/` only against a disposable initialized database; remove
  generated fixtures afterward. Cover acceptance, file evidence, all six rules,
  fallback/aggregation/carried groups, group replacement, history/provenance integrity,
  source-date changes and historical relation backfill when changing those boundaries.
- Do not claim unseen source history, every rejected candidate, historical service
  metadata or byte-exact reproduction without retained files/snapshots. History starts
  with accepted observations; the database cannot recover unobserved remote changes.

## Local command

Copy `.env.example` to `.env`, review it, then run from the repository root:

```sh
docker compose --env-file .env up -d --build
```

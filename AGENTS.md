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

## Architecture and Development Principles

### Purpose and scope

UrbanTwin Toolbox (UTT) is a long-lived, PostgreSQL-native research data infrastructure for heterogeneous urban data. Its purpose is to enable scientific work, not to become an all-purpose data engineering platform.

Prioritize a reliable, understandable prototype and complete research workflows over expanding generic infrastructure. UTT should eventually require little attention from its maintainers so they can focus on research.

### Core principles

1. **PostgreSQL/PostGIS first.** Prefer server-side, set-based SQL for ingestion, transformation, spatial operations, aggregation and data management. Avoid transferring large datasets into Python or other applications for operations that can be performed efficiently in the database.

2. **Reuse before implementing.** Actively consider established open-source tools, libraries and PostgreSQL extensions before proposing custom functionality. Recommend adoption when an existing solution offers substantial benefits with reasonable integration and maintenance costs.

3. **Avoid dependency proliferation.** Prefer a small native implementation when an external tool would introduce disproportionate dependencies, deployment requirements or orchestration complexity for a limited subset of its functionality. Consider total lifecycle cost, not just implementation effort.

4. **Keep the core conservative.** UTT core infrastructure should be stable, transparent, testable and maintainable for years. Prefer readable tables, explicit metadata, conventional SQL and established standards over elaborate abstractions.

5. **Keep functional modules independent.** Functional containers (idioca-style boxes) may use any appropriate language, framework or scientific library. They should interact with UTT through defined interfaces, preserve input/output provenance and avoid requiring changes to the core for application-specific functionality.

6. **Minimize researcher-facing complexity.** Researchers should interact primarily with a unified administration interface and their scientific applications, not a collection of specialized infrastructure tools. Internal technical complexity must not become a prerequisite for using UTT.

7. **Design for sustained operation.** Core workflows must be repeatable, recoverable, testable and suitable for unattended server execution. Account for interrupted processing, updates, failures, concurrent access and maintainability beyond the original developer.

8. **Preserve replaceability.** Prefer established data formats, standards and explicit component boundaries. Custom implementations should not unnecessarily prevent later replacement by existing tools.

9. **Avoid speculative generalization.** Implement functionality in response to demonstrated research requirements. Prefer a complete working use case over an unused generic capability. Do not expand scope merely because AI-assisted development makes implementation inexpensive.

10. **Optimize for human maintainability.** AI-generated code must remain understandable, documented and testable. Development speed is not sufficient justification for architectural complexity.

### Build-versus-adopt decision

Before implementing a substantial new capability, evaluate:

- Is an established tool, library, standard or PostgreSQL extension already available?
- Does it solve most of the actual requirement, or would we use only a small fraction?
- What are its installation, configuration, orchestration, dependency and maintenance costs?
- Would a PostgreSQL-native implementation be substantially simpler over its entire lifecycle?
- Does either solution introduce additional concepts or tools that researchers must understand?
- Can the chosen implementation be maintained and replaced independently?

**Codex must proactively alert the developer when a mature, suitable existing solution could reasonably replace planned custom development.** Name the candidate, briefly explain its advantages and trade-offs, and recommend whether to adopt, integrate selectively or implement natively.

Do not automatically introduce dependencies, rewrite existing functionality or expand the architecture. Present significant alternatives before implementation and leave architectural decisions to the developer.

Raise a concise build-versus-adopt alert once during planning when introducing a new infrastructure capability, significant dependency or substantial custom implementation. Do not repeat the assessment for routine implementation tasks within the agreed architecture unless new information changes the decision.

### Complexity budget

Evaluate new features against three costs:

- **Operational complexity:** services, dependencies, deployments, configuration, monitoring and upgrades.
- **Conceptual complexity:** metadata, abstractions, special cases, interfaces and maintenance knowledge.
- **User complexity:** additional interfaces, procedures or expertise required from researchers.

A new feature should provide a meaningful benefit relative to these costs. PostgreSQL-native implementations are not automatically simple; their internal complexity must also be justified.

### Definition of success

UTT succeeds when researchers can integrate, update, trace and use urban data through coherent workflows without operating a collection of specialized infrastructure tools, and when a small research team can maintain the system over multiple years.

**Do not maximize what AI makes possible to build. Maximize what researchers can use and maintainers can sustainably operate.**

## Direction and design priorities

Mirror owns source history; curation owns replaceable snapshot tables and current
build identity. The rules below define the implemented architecture and boundaries
for subsequent changes.

UrbanTwin-Toolbox is a 3DCityDB v5-based urban digital twin centered on
PostgreSQL/PostGIS. The mirror and curation workflows should remain primarily inside
PostgreSQL so the team can understand, discuss and maintain them together.

- Prefer the smallest readable set of functions, tables and columns that preserves
  correctness and clear responsibilities. Add objects only for concrete current uses.
- Always use clearly readable, explanatory names for tables, columns, schemas,
  views, routines, constraints and other database objects, including generated ones.
  Do not put hashes, opaque codes or generated numeric identifiers in object names.
  Resolve naming collisions with meaningful names or an explicit readable name.
- For the project-schema architecture, develop and test only the default
  `curation` schema. Users may organize independent projects in meaningfully named
  schemas such as `curation_berlin` or `curation_stuttgart`, sharing core infrastructure
  and mirror sources. Do not implement extra project schemas, multi-project management
  or a named-schema initializer until requested.
- For rebuildable curation, give each
  functional recipe version a fixed default mirror snapshot `timestamptz`, with an
  explicit caller override for testing or later compatible data. Do not silently use
  now/latest or advance the default. Record the actual snapshot used with recipe/Git
  revision, region/parameters and build outcome; distinguish snapshot time from build
  time. Curated outputs are replaceable, without independent record history; optimize
  full snapshot/region reconstruction before adding incremental processing or caches.
  Implement curation routines as database SQL procedures (`CREATE PROCEDURE`, called
  with `CALL`). Each builds a snapshot dataset into an ordinary SQL table from mirror
  data selected at the requested timestamp, or from already curated tables representing
  the intended snapshot. Curated tables have no temporal modelling or system-time
  version ranges; the input snapshot identifies the build, not a row-history axis.
  Use readable SQL steps for preparation, matching/selection, validation and indexing.
  Tables cooperating as a system must share a meaningful prefix or suffix.
  Build replacements separately and install them atomically, without partial results.
  Publication interfaces and schema placement are undecided: they may later have a
  separate schema or live in curation. Do not require a publication schema or views.
  Implement only one functional curation version for the current demonstration; do
  not add version-management infrastructure. Keep established output columns and
  meanings, using typed NULLs for unavailable values without magic sentinels. Defer
  reason/error codes, per-attribute status columns and diagnostic structures. Invalid
  builds must fail while leaving the previous completed curated result intact.
- For snapshot curation, retain separate
  building–plot, building–block and plot–block relationship tables to represent n:m
  matches. Store one row per pair, enforce endpoint foreign keys and pair uniqueness,
  and keep overlap fractions on the relationship. Do not collapse these relationships
  into single endpoint references or arrays because most matches happen to be 1:1.
  Build them after their endpoint tables for the same snapshot dataset, with a shared
  meaningful prefix or suffix and no temporal history. Do not compute all historical
  endpoint combinations. Start with full reconstruction and measure representative
  spatial query plans before adding incremental processing or caches.
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
  temporal axis for mirror history. Native-file reference history uses the same
  system-time semantics under the file-specific name `mirror.registry.file_txn`;
  row-history tables retain `utt_txn`. Keep original source dates as
  ordinary attributes; do not infer valid-time ranges or add a second time axis.
  Avoid redundant timestamps.
- Existing interfaces describe the current implementation. Check their callers before
  replacement or removal. This is a changing prototype: existing database contents
  need not be preserved, and fresh initialization is the implementation target. Do
  not normally write migration SQL or compatibility code during development.
  Create a development migration only when explicitly requested by the user;
  each request authorizes that specific change, not future migrations.
  Prefer focused edits to existing files over
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
- Keep deferred low-priority fixes, small features and behavior proposals in root
  [BACKLOG.md](BACKLOG.md). Entries are not implementation authorization or overrides
  of these rules. Keep entries concise; remove resolved items and update the relevant
  current documentation and lasting rules when the work is completed.
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
- Put all mirror data, routines and triggers in `mirror`; routine names omit the
  redundant `mirror_` prefix. Keep shared administration helpers in `utt_pkg`.
  Put project recipes and their helpers in `curation`. Reserve `curate_` for SQL
  procedures that build curated tables; internal non-curating helpers use `curation_`.
  Use explicit functional dates on recipe procedure names; these meaningful version
  dates are permitted, unlike generated numeric identifiers in object names.
- Add a PostgreSQL `COMMENT` to every UTT-owned function or procedure. State its
  purpose, caller, effects, result and a practical SQL example. A trigger-function
  example must show the operation that fires it.
- Use exactly two generic NOLOGIN roles: `utt_admin` and `utt_developer`.
  Keep all privilege policy, account/sandbox provisioning, default privileges and
  future-object ownership policy in `902-create-privilege-roles.sql`. Do not add
  generic reader, pipeline or application roles. Give developers read-only shared
  access and personal sandboxes; define component permissions only when requested.
  Shared objects use `utt_admin` ownership; preserve extension ownership and narrow
  bootstrap-owned role-provisioning/event-trigger boundaries. Administrator research
  sandboxes use inherited `utt_admin` ownership to avoid membership cycles.
- Add routines only for concrete integrity, privilege, transaction or reuse
  boundaries; prefer direct SQL, constraints and privileges when sufficient.
- Preserve published source metadata in its original language and wording. Leave
  absent values `NULL`; do not infer license rights. Registry `fees` and
  `access_constraints` retain service-level statements verbatim.
- Curated writes require explicit snapshot-build procedures. Preserve narrow write
  privileges until a replacement boundary is designed.
- Keep changes small and independently usable. Document practical calls in
  [docs/uttdb.md](docs/uttdb.md) and routine comments.
- Use rollback-only database checks where practical. Distinguish repository changes
  from changes applied to a running database. Do not add migration files or plan live-data
  conversion unless explicitly requested by the user.

## Source capture and acceptance rules

- Prioritize an independently working and tested mirror/history workflow in the
  architecture. Reimplement curation only as a demonstration
  of the agreed snapshot-based, versioned recipe principle. Defer derived-source
  workflows, metadata handling, execution tracking and input lineage until mirror is
  validated and that later work is explicitly requested; do not add anticipatory
  infrastructure for it.
- A derived source is an ordinary source whose producer is a simulation, analysis
  or other processing tool, potentially fed by UTT data. Reuse supported foreign-table,
  file or other adapters and the normal registration/acceptance/history workflow.
  The term alone requires no new flag, storage mode, registry, table, adapter or
  execution subsystem; derived-source metadata and lineage design are deferred. Registration
  of outputs is explicit, not automatic for every disposable curation build.
- Keep mirror metadata and data in `mirror`, including registry, import and
  source_columns, and all mirror routines. Shared administration helpers live in
  `utt_pkg`; project procedures and generated snapshot tables live in `curation`.
  Core files 901–903 initialize and operate without optional `913-curation.sql`.
- Keep mirror usable independently of domain curation: registration, ingestion,
  acceptance, history, refresh and retirement must not require curation objects or
  routines. Curation depends on an initialized mirror with accepted inputs for its
  recipes; registration alone does not supply data. Keep this dependency one-way,
  while coordinating publication and curation through the documented locking boundary.
- Capture heterogeneous source data before optional domain curation. Preserve original
  attributes and geometry; harmonize only for a concrete domain and application.
  Treat CityGML/3DCityDB as an interoperability interface, not a mandatory copy of
  every research attribute. Do not add speculative domains or execution platforms.
- Keep source/import metadata in `mirror` and current build identity in
  `curation.dataset_build`. The metadata inventory is four tables: registry, import,
  source_columns and dataset_build. Do not restore generic mapping/provenance tables,
  source provenance partitions, permanent change sets or execution logs for this
  demonstration. New transformations belong in reviewed recipe SQL, not metadata.
- Register dataset/layer identity as `(source_name, layer_name)`, not just an endpoint
  or path. Use immutable registry `row_id` references. Never delete or repurpose a
  referenced registration; retire it. Keep referenced imports and schemas available.
  Enforce one storage mode per identity and one registration for database-row sources.
- For each row source, use a read-only `_source` adapter, one pending `_staging`
  snapshot, one `_stored` history table and an ordinary read-only current view.
  Registry-controlled base names must be unique across registrations and readable.
  Normalize source/layer words without hashes or truncation, reject bases over
  48 bytes and reject collisions explicitly.
  Current views must not duplicate storage or expose write access through base tables.
- Preserve source columns, types and values in staging; do not filter, curate or add
  technical version columns there. Keep revision evidence separately. Document
  unavoidable adapter conversions and resolve source/technical name collisions
  explicitly without discarding original fields.
- Require explicitly configured non-NULL unique stable keys before row ingestion;
  keys must use nonspatial identifiers. Reject geometry/geography/raster key columns
  before their JSON encoding, including direct array/domain wrappers.
  never use physical row positions. Compare full source state, including geometry.
  Any optional content hash must cover that state and exclude generated metadata.
  Compare accepted row state and protect history without whole-row JSON conversion:
  geometry casts to GeoJSON reject MultiSurface and can round coordinates. Preserve
  exact spatial state, including curves, Z/M and SRID, and raster pixel contents.
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
  row identity, path/namespace, format, size, checksum/algorithm, `file_txn` and creating
  import. Do not require geometry, conversion, a foreign table or payload decoding.
  Give independently versioned files separate logical identities, not JSON file lists.
  Do not invent relational column schemas for opaque native files; retain format and
  available published structure metadata instead.
- Permit native-file re-registration after retirement with a new registry row.
  Exclude retired registrations from active-file uniqueness and range-overlap checks,
  and select only non-retired registrations for ingestion, acceptance and rejection.
  Preserve old rows, checksums, file_txn ranges and import references. Retirement
  does not close an accepted range; archived ranges may overlap a later registration.
- Permit an initial unaccepted registration without an open history range. Refresh
  resolves current logical identity; imports reference exact registry rows.
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

## Snapshot curation rules

- Implement one functional Berlin recipe with six entity tables and three n:m tables,
  all using the meaningful `berlin_` prefix. Relationship tables additionally use
  `relation_`, for example `curation.berlin_relation_building_plot`. Preserve domain attributes and official
  ID conversions; snapshot-local `row_id` values may change on reconstruction.
- Read mirror versions at one requested timestamp and validate required columns
  against the accepted schema at that timestamp, not retained physical columns or
  today's view. Require accepted inputs; do not silently use latest or skip missing
  recipe columns. Preserve source dates and nullable descriptive values. Do not infer
  matching identifiers, unit conversion or CRS conversion.
- Recipes have fixed default `timestamptz` snapshots and explicit overrides. Use a
  new functional recipe version for intended feature/semantic changes; fixes,
  maintenance and performance improvements may update an existing version. Preserve
  older functional recipes when introducing later versions; Git records exact SQL.
- Build indexed temporary entity tables, then relationship tables from those same
  inputs. Restrict internal-step execution to DBA/owner and expose only the complete
  security-definer build procedure to administrators. Developers receive read-only
  output access and no build grant; applications require explicitly designed access.
- Serialize builds with advisory transaction lock (70303,1). Hold mirror.registry
  EXCLUSIVE throughout input selection: this blocks acceptance's initial row locks
  and schema changes while allowing plain reads, avoiding publication lock inversions.
  Core mirror must never acquire a dependency on project objects or project locks.
- Install the complete cooperating dataset and its build identity in one transaction.
  Preserve output object identities and dependent queries; failures at any stage
  leave the prior complete dataset and metadata intact. No internal commits. There
  is no temporal modelling, historical pair backfill or per-record provenance in
  curated outputs. Reconstruct earlier datasets from retained mirror history.
- Preserve separate building/block, building/plot and plot/block tables, one row
  per pair with endpoint foreign keys and pair uniqueness. Divide intersection area
  by the first endpoint's area, round to three decimals and retain fractions above
  0.02. Use spatial-index candidate probes, calculate each fraction once and refresh
  planner statistics; inspect representative plans without global planner overrides.
- Keep one current successful row per dataset in `curation.dataset_build`, recording
  recipe, optional caller-supplied Git revision, actual mirror snapshot, region and
  completion time. Use explicit columns for concrete parameters if added. Unknown
  Git revisions remain NULL; failed attempts create no execution history. Build
  identity is not the deferred derived-source lineage model.
- A NULL region selects the whole registered scope; explicit regions require a
  compatible source CRS. Retain whole intersecting geometries, including boundary
  crossers, and expand candidate regions for any future distance-based predicates.

## Implementation locations and validation

- `901-setup-structures.sql`: schemas and extensions; `902-create-privilege-roles.sql`:
  group roles and developer sandboxes; `903-mirror-setup.sql`: ingestion/history;
  `913-curation.sql`: all optional project tables, dataset_build, Berlin procedures,
  schema checks and atomic installation. Keep structures and routines together;
  do not restore a separate 912 curation setup file.
- Use [example/berlin.sql](example/berlin.sql) for the public six-layer workflow.
  Run SQL suites in `tests/` only against a disposable initialized database; remove
  generated fixtures afterward. Cover acceptance, file evidence, schema reuse, all six Berlin transformations,
  timestamp overrides, historical schema selection, n:m integrity, source dates,
  reproducible reconstruction and failed installation rollback. Validate core mirror
  without curation; measure representative entity/relationship plans separately.
- Do not claim unseen source history, every rejected candidate, historical service
  metadata or byte-exact reproduction without retained files/snapshots. History starts
  with accepted observations; the database cannot recover unobserved remote changes.

## Local command

Copy `.env.example` to `.env`, review it, then run from the repository root:

```sh
docker compose --env-file .env up -d --build
```

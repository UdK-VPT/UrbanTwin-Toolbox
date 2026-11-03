# Implementation revision: mirror history and snapshot curation

*Agreed architecture and implementation assignment — 2026-11-02.*

## 1. Schemas and responsibilities

| Schema | Responsibility |
|---|---|
| `citydb`, `citydb_pkg` | Externally managed 3DCityDB schemas; UTT does not control their design. |
| `utt_pkg` | Shared administration helpers, currently developer sandbox provisioning. |
| `mirror` | All mirror-related data and metadata: source registry, imports, source-column definitions, source adapters, staging, stored history, current views and all mirror routines. Routine names omit the redundant `mirror_` prefix. Not a workspace for project-specific processing logic. |
| `curation` | Project/user-specific curation procedures **and** their generated tables/views and working data. |

UTT provides reusable building blocks; users implement domain- and region-specific curation. Schema membership expresses *responsibility*, not SQL object type. Use qualified data references; `search_path` can simplify calls to commonly used routines when appropriate.

Keep `mirror.registry`, `mirror.import` and `mirror.source_columns` in place.
All mirror routines live in `mirror`, e.g. `mirror.store_layer()`. Shared
administration helpers live in `utt_pkg`; no `utt` schema is created. Project tables
and procedures belong together in `curation`, initialized by `913-curation.sql`.

`mirror` and shared `utt_pkg` administration must initialize and operate without
any curation schema, curation objects or project routines. Curation may depend on
these schemas and accepted mirror inputs; the core must not depend on curation.

### Multiple projects — agreed convention

Users may maintain independent projects in separate curation schemas, preferably
with meaningful names such as `curation_berlin` and `curation_stuttgart`. These
schemas can reuse the same `utt_pkg` administration helpers and registered `mirror` sources;
project routines, generated datasets and working data stay within their own schema.

For current development and tests, target only the default `curation` schema.
Do not add multi-project management, parameterized schema initialization or a second
curation schema now. A separate SQL initializer for an additional user-named curation
schema is future work, to be implemented only when requested.

## 2. Sources, mirror and history

### 2a. Mirror time — confirmed, no implementation change

Mirror history uses UTT **system/transaction time** (`utt_txn`); no bitemporal model.
Source-provided timestamps remain ordinary attributes. Existing full-snapshot
acceptance and missing-source-record closure semantics stay unchanged.

### 2b. Rebuildable curation — implemented for fresh initialization

Only `mirror` tracks authoritative source-record history. Curated datasets are
replaceable outputs of a versioned recipe for one requested snapshot and region;
they have no independent record-version history. Keep functional recipe versions
and build identity rather than every generated dataset. Favor straightforward bulk
reconstruction; measure before adding incremental processing or caches.

Curation routines are always database SQL procedures (`CREATE PROCEDURE`, invoked
with `CALL`). Each procedure builds a snapshot dataset into an ordinary SQL table
from mirror data selected for the requested system-time timestamp. Procedures may
also transform already curated tables into another curated table; cooperating
inputs must represent the intended snapshot. Curated tables have no temporal
modelling: no record-version history or system-time ranges. Their build snapshot
identifies the input selection, not another temporal axis on output rows.

The procedure is a materialized-dataset build recipe expressed as readable SQL steps.
It may prepare inputs, resolve sources, calculate spatial relationships, validate
results and build indexes. Build replacements separately and install them atomically
without partial results. Related curated tables that work together as a system must
share a meaningful prefix or suffix. Publication and any view interfaces remain
undecided (section 6).

Each recipe version must have a fixed default mirror snapshot timestamp, pinning
its intended data selection together with the logic. Callers may explicitly override
that timestamp to test other compatible snapshots or apply the recipe to later data.
The timestamp/default and build recording rules are specified in section 4.

### 2c. Derived sources — agreed terminology, no new ingestion mechanism

A **derived source** supplies results produced by a simulation, calculation,
analysis or research tool, potentially using UTT's own data as input. It is still an
ordinary source exposed through a foreign table, files or another supported adapter.
The term describes origin, not a new storage mode or ingestion workflow. Reuse the
same explicit registration, acceptance and mirror-history mechanisms as for external
sources; do not automatically register every disposable curation build.

This introduces no implementation work by itself. Do not add a derived-source flag,
registry, adapter, table or execution subsystem merely to represent the term.

### 2d. Derived-source metadata and lineage — deferred

Define derived-source metadata handling, execution records, methods/parameters and
input lineage later, after mirror and its history work and have been tested. The
term in 2c remains useful, but no derived-source workflow or metadata structures
belong to the current implementation scope. Detailed requirements remain undecided.

### Implementation priority — mirror first

1. Establish and test the independently usable mirror workflow and source history.
2. Reimplement only one functional curation version to demonstrate stepwise recipes
   rebuilding a dataset from a selected mirror snapshot, with the agreed timestamp
   default and explicit override. This is a demonstration, not a general curation
   or execution platform.
3. Address derived-source workflows and metadata only in a later assignment, after
   mirror validation. Do not add anticipatory execution or lineage infrastructure.

The assignment below turns these decisions into one coordinated implementation
revision. Implement against fresh initialization; no migration or live-data conversion.

## 3. Curated model and missing values — agreed, minimal demonstration

- **Additive schema:** once introduced, curated attributes remain present even if no data can currently populate them. Do not silently change the meaning of an established attribute; introduce a new one for a genuinely different meaning.
- Curation is a **reproducible transformation** of selected mirror records, not a second historical store. Generated curated datasets are replaceable and may be deleted and rebuilt.
- Keep unavailable values as **typed `NULL`**; do **not** put magic sentinels such
  as `999999999` into ordinary data columns. Missing-value reason codes, error-value
  conventions and detailed diagnostics are deferred; add no status columns or
  diagnostic metadata structures for the current demonstration.
- A failure that invalidates a build must fail the build and leave the previous
  completed curated result intact, rather than silently substituting NULLs for failed work.
- Implement only **one functional curation version** now. The versioning conventions
  in section 4 guide future changes; do not build multiple versions or a version
  management framework merely to demonstrate the principle.
- An old snapshot may legitimately lack values for attributes added later. Structural continuity does **not** imply historical completeness.

## 4. Curation versions and reconstruction

- Use functionally dated procedure names, e.g. `curation.curate_building_20261101`.
- **New intended features or semantics** (new mappings, sources, attributes, selection rules) warrant a new curation version. **Bug fixes, renames, refactoring, performance tuning and compatibility maintenance** may update an existing routine.
- Preserve older functional versions and their required interfaces/dependencies; reuse unchanged dependencies. Track exact SQL revisions in Git.
- Give each functional recipe version an explicit `timestamptz` snapshot parameter
  with a fixed, unambiguous default for its intended mirror snapshot. Do not default
  silently to `now()`/latest or change the pinned default when later data arrives.
  Permit an explicit timestamp override without changing the recipe's default.
- Record at least the procedure/version, Git revision, **actual mirror snapshot
  timestamp used** (including overrides), region/parameters and build outcome so
  outputs can be identified and reconstructed. Distinguish the input snapshot from
  the recipe's functional date and the wall-clock build time; passing an override
  does not guarantee compatibility with that snapshot.
- A procedure is expected to work with its **intended compatible mirror snapshot(s)**, not with every past or future state. No bidirectional compatibility guarantee between arbitrary curation and mirror versions. A newer procedure should retain established curated attributes and meanings, even where their values are unavailable.
- Rebuilding after bug fixes may correct previously produced results; exact reproduction of the *original implementation* requires the recorded Git revision and compatible dependencies/environment.

## 5. Spatial relationships and performance — agreed

- Keep separate relationship tables for building–plot, building–block and plot–block.
  These relationships support n:m cardinality even when most objects have only one
  match. Store one row per matched pair, with foreign keys to the curated endpoint
  tables, a uniqueness constraint on the pair and relationship attributes such as
  overlap fraction. Do not replace them with single endpoint references or arrays.
- Build relationships after their endpoint tables for the same snapshot dataset.
  Relationship and endpoint tables share the dataset's meaningful prefix or suffix;
  neither has temporal history.
- Do **not** maintain separately versioned historical spatial relationships. Compute relationships from geometries selected for the requested **system-time snapshot** and region.
- Filter mirror records by timestamp and spatial extent **before expensive spatial joins** wherever valid. Include geometries that extend across the bounding box; expand candidate areas when spatial predicates (e.g. distance joins) require it.
- Favor indexes and query-plan measurements (`EXPLAIN ANALYZE`) over assuming a particular SQL arrangement is fast.
- Prefer **stepwise, readable PostgreSQL/PostGIS curation procedures** over forcing all logic into giant views. Use staging, spatial matching, source-priority resolution, validation and replacement steps; avoid many expensive full-table `UPDATE`s where bulk construction would work better.
- Curated outputs are ordinary indexed **tables**. Build replacements separately and install them atomically to avoid partial results; this does not prescribe a publication interface.
- Start with full reconstruction and measure performance; add incremental updates or disposable caches/materializations only if justified. Such caches are **not** new authoritative history.

## 6. Publication — deferred

- Make no assumptions about publication, consumer interfaces or their schema placement
  for now. Publication may later have its own schema or live within a curation schema.
  Do not require a `publication` schema or stable publication views in this implementation.
- The open-source mirror and `utt_pkg` core must not depend on Berlin- or project-specific curation routines. Projects own their own curation logic and can reuse the same mirror and source infrastructure.

**Guiding principle:** *Preserve sources and their history in `mirror`; preserve maintainable, feature-versioned recipes in `curation`; rebuild curated datasets as needed. Publication remains undecided.*


## 7. Implementation assignment

Sections 1–6 define the agreed target. This section defines the implementation order
and completion checks; `AGENTS.md` remains the authoritative agent instruction file.
This revision replaces the old temporal-curation architecture, while preserving
mirror's accepted-history and ingestion contracts.

### 7a. Core schemas and independent mirror

- Update `901-setup-structures.sql`, `902-create-privilege-roles.sql` and
  `903-mirror-setup.sql`: all mirror routines, data and metadata live in `mirror`;
  routine names omit `mirror_`. Shared administration helpers live in `utt_pkg`. Review qualified calls, routine comments,
  privileges, triggers and initialization dependencies together.
- Core initialization and mirror operations must work without running project
  curation setup. Remove core references to curation metadata, provenance partitions
  and curation-only locks where they would require project objects. Preserve mirror's
  own staging/publication serialization and acceptance integrity.
- Retain existing adapters, stable-key checks, full-snapshot semantics, thresholds,
  schema-definition reuse, pending review, native-file evidence and batch-refresh
  behavior. This is not an ingestion redesign.
- Validate mirror independently before implementing the demonstration.

### 7b. One snapshot-curation demonstration

- Keep all project structures and procedures together in `913-curation.sql`,
  initializing the default `curation` schema. Keep the existing six Berlin entity outputs and three relationship types
  as one functional demonstration, using a common readable `berlin_` table prefix.
  Preserve established domain attributes and relationship overlap rules unless a
  change is necessary to remove temporal modelling.
- Replace entity diff/history workflows with stepwise SQL procedures building
  ordinary snapshot tables. Remove curated system-time ranges, history constraints,
  historical readers and per-record historical provenance machinery that no longer
  serve this model. Retain mapping configuration only where the demonstration
  actually needs it; do not recreate the old generic temporal-curation framework.
- Inspect callers before removing interfaces. Update examples, grants and tests
  together; provide no legacy wrappers or migrations for the old prototype.
- Use a fixed recipe snapshot default and explicit override. For a fresh Berlin
  import, the example must explicitly select one timestamp after all required
  sources are accepted and pass it consistently through the build. Never silently
  substitute latest data when the requested snapshot has no required inputs.
- Build and index entity outputs before relationship outputs. Enforce endpoint
  foreign keys and unique pairs, retaining genuine n:m matches. Test source-date
  attributes as ordinary values, with no curated time axis.
- Define a transaction boundary for a complete cooperating dataset: failed later
  steps must preserve the previous complete dataset and its build identity. Stepwise
  preparation must not install a mixture of old and new entity/relationship tables.
  Use database transactions and readable working tables rather than an execution
  framework; preserve practical direct `CALL` examples.

### 7c. Minimal build identity — implementation default

Use one small `curation.dataset_build` table with one current successful-build row
per named dataset, updated atomically with its output tables. Store explicit columns
for dataset name, recipe identity, Git revision, actual mirror snapshot, region and
concrete parameters used, plus completion time. Do not add generic JSON parameter
bags, failed-attempt history or an execution-log subsystem. Failed calls report their
error and retain the previous successful row. Store an unknown Git revision as NULL,
never an inferred claim of exact reproduction.

This is build identity for curated outputs, not the deferred derived-source lineage
model. Reuse it for cooperating tables rather than adding metadata per entity or
relationship. Account for metadata tables after removing obsolete structures: three
mirror metadata tables plus this table gives four; any retained mapping table adds
one. Check the actual resulting inventory and explain any further additions.

### 7d. Documentation and workflow

- Update `example/berlin.sql` to call the `mirror` entry points and `curation`
  procedures, keeping independently committed mirror steps. Document the separate
  transaction boundary for installing a complete curated dataset.
- Align `AGENTS.md` with the resulting implementation, replacing superseded temporal
  curation rules instead of leaving competing instructions. Preserve applicable
  mirror, security, source-metadata and naming rules.
- Update the existing guides, glossary and database reference to describe actual
  schemas, procedures, build identity, allowed edits and snapshot reconstruction.
  Keep publication and derived-source execution/lineage out of the implementation.

### 7e. Completion and validation

- Fresh initialization succeeds; core-only initialization and mirror acceptance work
  without `curation`. No unintended project dependencies remain in mirror or `utt_pkg`.
- Run relevant mirror, native-file and source-schema regression suites against a
  disposable database. Retain meaningful ingestion/history coverage.
- Replace superseded curation-history tests with snapshot tests: default and override,
  reproducible rebuild, changed mirror inputs at different timestamps, compatible
  chained curated inputs, typed NULLs, and failure preserving the complete prior
  dataset and build identity. Keep fixtures small and remove generated files.
- Verify all six Berlin outputs and three relationship types, including n:m cases,
  pair uniqueness, endpoint integrity and overlap fractions. Confirm curated tables
  have no system-time history and old historical pair backfill is absent.
- Inspect representative spatial query plans and measure entity and relationship
  stages separately. Record fixture sizes, timings and environment; do not claim a
  Berlin-wide speedup from small fixtures alone. Run a full remote Berlin benchmark
  only as a separately identified integration run, not a prerequisite for local tests.
- Check SQL comments, documentation links and repository whitespace. Report repository
  changes separately from anything applied to a running database.

### Out of scope

No migrations, live database recreation, multiple functional recipe versions,
additional project schemas, publication design, derived-source metadata/execution,
error-code model, incremental refresh framework or new authoritative history stores.


## 8. Implementation and validation record — 2026-11-02

The repository implements this revision for fresh initialization. Existing project
database contents have not been converted or replaced. Core files 901–903 work
without curation; optional file 913 installs one Berlin recipe and its ordinary
snapshot tables. No generic mapping table was retained. The metadata inventory is
four tables: three in mirror and `curation.dataset_build`.

Validation used a separately created disposable database on PostgreSQL 18.6,
PostGIS 3.6.4 / GEOS 3.14.1. Core-only setup used an empty upstream `citydb` namespace;
this checks UTT initialization and independence, not a full Compose/3DCityDB startup.
All six suites passed: core-independence, mirror, mirror-files, source-columns,
curation-berlin and spatial-relations. Coverage includes n:m pairs, snapshot overrides,
region boundaries, historical schema selection, pipeline restrictions, reproducible
rebuilds and rollback on a final installation constraint failure. All UTT-owned
routines have PostgreSQL comments. A two-session check verified that the exclusive
registry lock permits plain reads while blocking acceptance's initial row locks.

Indicative local measurements: building preparation on the one-building Berlin
fixture took 22 ms; the separate 3,000-building/3,000-plot grid's bounding-box query
used 3,000 parameterized spatial index probes and took 6.7 ms. The three relationship
steps together took 142 ms on that grid (3,000 plots, 3,000 buildings, one nonoverlapping
block). These are fixture measurements, not a Berlin-wide performance claim.
No remote Berlin ingestion benchmark or live deployment was performed.


### Naming and file consolidation — 2026-11-03

All 15 mirror routines now live in `mirror`, without their former `mirror_` prefix.
`utt_pkg` contains shared administration (`create_developer_sandbox`); `utt` is no
longer created. Curation structures from the former 912 file and all project
procedures are combined in `913-curation.sql`; the 912 file is removed. This changes
names and initialization organization, not ingestion or snapshot-build semantics.

The six disposable-database regression suites passed again after this naming change,
with core-only initialization followed by the single combined curation file. Routine
inventory: 15 in mirror, one in utt_pkg and nine in curation; all have comments.
The empty-registry top-level batch call also passed. Generated fixtures and the
separate test database were removed; the project database was not modified.

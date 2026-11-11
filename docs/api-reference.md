# API Reference

This reference covers UTT-owned database routines in the current initialization SQL, not upstream
PostgreSQL, PostGIS or 3DCityDB APIs. The public interfaces below are administrative workflow
entries; read interfaces are ordinary SQL relations rather than extra reader functions. Internal
routines appear separately, even where an administrator has execution rights. The optional
`curation` schema requires 913.

Signatures below preserve parameter names, modes, types and default expressions from files 902, 903
and 913. `FUNCTION` and `PROCEDURE` identify the declaration kind; invoke functions with `SELECT`
and procedures with `CALL`, not by executing these signature blocks as DDL. SQL examples assume
their named sources/files exist and that the preceding workflow prerequisites have been completed.

## Alphabetical routine index

- [curation.curate_berlin_20261101](#curationcurate_berlin_20261101) — public administration entry
- [curation.curate_berlin_address_20261101](#curationcurate_berlin_address_20261101) — internal
- [curation.curate_berlin_block_20261101](#curationcurate_berlin_block_20261101) — internal
- [curation.curate_berlin_building_20261101](#curationcurate_berlin_building_20261101) — internal
- [curation.curate_berlin_city_20261101](#curationcurate_berlin_city_20261101) — internal
- [curation.curate_berlin_district_20261101](#curationcurate_berlin_district_20261101) — internal
- [curation.curate_berlin_plot_20261101](#curationcurate_berlin_plot_20261101) — internal
- [curation.curate_berlin_relations_20261101](#curationcurate_berlin_relations_20261101) — internal
- [curation.curation_berlin_source](#curationcuration_berlin_source) — internal
- [mirror.accept_layer](#mirroraccept_layer) — public administration entry
- [mirror.file_evidence](#mirrorfile_evidence) — internal
- [mirror.layer_extent](#mirrorlayer_extent) — internal
- [mirror.object_base](#mirrorobject_base) — internal
- [mirror.protect_history](#mirrorprotect_history) — internal
- [mirror.protect_metadata](#mirrorprotect_metadata) — internal
- [mirror.read_geotiff](#mirrorread_geotiff) — internal
- [mirror.register_external_file](#mirrorregister_external_file) — public administration entry
- [mirror.register_file_source](#mirrorregister_file_source) — public administration entry
- [mirror.register_wfs_source](#mirrorregister_wfs_source) — public administration entry
- [mirror.reject_layer](#mirrorreject_layer) — public administration entry
- [mirror.store_layer](#mirrorstore_layer) — public administration entry
- [mirror.unregister_source](#mirrorunregister_source) — public administration entry
- [mirror.update_registered_sources](#mirrorupdate_registered_sources) — public administration entry
- [mirror.wfs_revision_dates](#mirrorwfs_revision_dates) — internal
- [utt_pkg.apply_shared_privileges](#utt_pkgapply_shared_privileges) — internal
- [utt_pkg.create_admin](#utt_pkgcreate_admin) — public administration entry
- [utt_pkg.create_developer](#utt_pkgcreate_developer) — public administration entry
- [utt_pkg.create_developer_sandbox](#utt_pkgcreate_developer_sandbox) — public administration entry
- [utt_pkg.deactivate_account](#utt_pkgdeactivate_account) — public administration entry

## Common execution contract

All public entries require `utt_admin` membership (or the bootstrap DBA). Provisioning also
explicitly checks `session_user` membership; changing only `current_user` does not substitute for a
real authorized session. Other mirror entries use invoker security and need the corresponding
database/schema/server/table rights supplied by the installed administrator role. Ordinary
developers cannot ingest, accept, refresh, retire or build. They read shared relations and own
personal sandboxes. The only developer-executable UTT helper is the bounded GeoTIFF reader used by
source views; it remains an adapter, not a source-management entry point.

Unless an entry explicitly states otherwise, it makes **no internal commit**. A standalone statement
commits under autocommit; within an explicit transaction its changes commit or roll back with the
caller. Errors do not partially publish accepted state. A caller must roll back an aborted explicit
transaction before continuing. Functions returning `void` have no status return: inspect
`mirror.import` for outcomes. `mirror.update_registered_sources` is the exception to
caller-controlled transactions: it commits each dataset and must run as a top-level `CALL`, outside
`BEGIN/COMMIT`.

## Shared administration: utt_pkg

### utt_pkg.create_admin

Create an individual administrator login without a sandbox.

```sql
PROCEDURE utt_pkg.create_admin(INOUT login_name text)
```

**Parameters.** `login_name` is an INOUT login identifier; it is also returned unchanged.

**Result.** A procedure output row containing `login_name text`; this is not a function returning
text.

**Caller and preconditions.** An administrator login session. Provisioning executes as the bootstrap
owner through a restricted security-definer boundary.

**Effects and transactions.** Creates a passwordless, nonsuperuser LOGIN without CREATEDB,
CREATEROLE or replication, and grants `utt_admin`. Atomic in the caller transaction.

**Validation and limitations.** Lowercase ASCII identifier starting with a letter
(`[a-z][a-z0-9_]*`), at most 63 bytes; duplicates fail. Authentication is configured separately, for
example with bootstrap psql `\password bob`.

```sql
CALL utt_pkg.create_admin('bob');
```

### utt_pkg.create_developer

Create an individual developer login and its empty collaborative sandbox atomically.

```sql
PROCEDURE utt_pkg.create_developer(INOUT login_name text, INOUT sandbox_schema text DEFAULT NULL)
```

**Parameters.** `login_name` is the INOUT login name. `sandbox_schema` is INOUT, defaults to NULL
and is overwritten with the provisioned schema name; supplying it does not choose a schema.

**Result.** An output row `(login_name text, sandbox_schema text)`.

**Caller and preconditions.** Administrator session; bootstrap-owned security-definer provisioning
boundary.

**Effects and transactions.** Creates a passwordless nonsuperuser login, then calls
`create_developer_sandbox` to grant membership, create ownership/membership links and configure
reads/defaults. Failure rolls back account and sandbox together; no internal commits.

**Validation and limitations.** Login naming follows the lowercase ASCII rule and `sandbox_<login>`
must fit 63 bytes. Existing accounts fail rather than being reused. Configure credentials
separately; new sandboxes contain no objects.

```sql
CALL utt_pkg.create_developer('alice');
```

### utt_pkg.create_developer_sandbox

Create or safely reuse a sandbox for an existing individual login.

```sql
FUNCTION utt_pkg.create_developer_sandbox(developer_role text)
RETURNS text
```

**Parameters.** `developer_role` is the existing non-superuser LOGIN name; no default.

**Result.** `text`: `sandbox_<developer_role>`.

**Caller and preconditions.** Administrator session; target role must exist and be a non-superuser
login. Security definer with restricted search path.

**Effects and transactions.** Grants `utt_developer`, creates/reuses the correctly owned schema,
grants peer usage/SELECT and owner-specific future table reads, and revokes PUBLIC default routine
execution for that login. Grants ordinary developer-role membership to `utt_admin` for
administrative ownership access. Administrator sandboxes instead belong to `utt_admin`, avoiding
membership cycles. Caller-controlled transaction.

**Validation and limitations.** Rejects invalid/overlength names and schemas owned by another role.
Reuse does not reset existing work. Owners can change permissions on their own objects; peer-read
defaults are collaboration defaults, not an ownership restriction.

```sql
SELECT utt_pkg.create_developer_sandbox('alice');
```

### utt_pkg.deactivate_account

Disable new connections for an individual UTT account.

```sql
PROCEDURE utt_pkg.deactivate_account(login_name text)
```

**Parameters.** `login_name` identifies an active non-superuser UTT login; no default.

**Result.** No result parameters or return value.

**Caller and preconditions.** Administrator session; bootstrap-owned security-definer routine.
Target must be a login with `utt_admin` or `utt_developer` membership.

**Effects and transactions.** Sets NOLOGIN, preserving roles, memberships and sandbox objects. No
internal commit.

**Validation and limitations.** Existing sessions stay connected. Superusers, unknown accounts,
already inactive accounts and non-UTT accounts are rejected. Does not delete a schema or terminate
sessions.

```sql
CALL utt_pkg.deactivate_account('alice');
```

## Source registration: mirror

### mirror.register_wfs_source

Discover and register every advertised layer of a WFS source.

```sql
FUNCTION mirror.register_wfs_source(p_server_name text,
  p_wfs_url text)
RETURNS SETOF regclass
```

**Parameters.** `p_server_name` supplies the source/foreign-server name; `p_wfs_url` supplies the
WFS endpoint. Neither has a default. These exact parameter names matter for named calls.

**Result.** `SETOF regclass`: the created source foreign-table names.

**Caller and preconditions.** Administrator with database/schema/foreign-server and registry-write
privileges. Database network access to service and metadata URLs; usable OGR WFS discovery.

**Effects and transactions.** Creates an OGR foreign server as needed, discovers layers in a
short-lived discovery schema, moves read-only source adapters to `mirror` and inserts row
registrations. Preserves published titles, abstracts and service-level fees/access constraints;
collects advertised revision dates and geographic bounds when available. No accepted rows;
`last_imported_at` remains NULL. One caller transaction; discovery schema is removed.

**Validation and limitations.** Repeated registration is not refresh. Invalid names, collisions,
metadata HTTP/XML errors and layer matching errors roll back the complete call, including newly
created server. Bases are readable normalized source/layer words, unique and at most 48 bytes; no
truncation/hashes. HTTP helper settings use 30-second request and 10-second connection timeouts.
Missing metadata stays NULL, and advertised revision is not accepted-data evidence.

```sql
SELECT * FROM mirror.register_wfs_source(
  p_server_name => 'berlin_alkis',
  p_wfs_url => 'https://gdi.berlin.de/services/wfs/alkis');
```

### mirror.register_file_source

Register local vector layers through OGR, or a self-contained GeoTIFF through the raster adapter.

```sql
FUNCTION mirror.register_file_source(source_name text, file_path text,
  driver text DEFAULT NULL, open_options text DEFAULT NULL)
RETURNS SETOF regclass
```

**Parameters.** `source_name` is the logical source/server name; `file_path` is a database-visible
path below `/source-files`. `driver` defaults to NULL for detection; `open_options` defaults to NULL
and passes driver-specific vector options.

**Result.** `SETOF regclass`: source foreign tables for vectors or the raster source view.

**Caller and preconditions.** Administrator; completed readable files and sidecars under the source
mount. OGR must support the vector driver; GeoTIFF must meet bounded reader requirements.

**Effects and transactions.** Creates source relations and file-type row registrations; scans
geometry/raster bounds into EPSG:4326, leaving NULL for empty/nonspatial/unknown-SRID data. Generic
file descriptive metadata is not extracted. Vector layers need explicit stable keys. GeoTIFF uses
the filename as `layer_name`, a base derived from `source_name` and configured tile key `rid`.
Validates raster decoding but stores no accepted rows/pixels. Atomic caller transaction; files
untouched.

**Validation and limitations.** `.tif`/`.tiff` without driver, or explicit `GTiff`, selects the
raster adapter: no open options, at most 256 MiB input and entire decoded image must fit memory.
Vector discovery errors, empty datasets, unreadable files and naming collisions fail registration.
Geometry exposure follows OGR types/conversions, not a promise of byte-identical original file
storage.

```sql
SELECT * FROM mirror.register_file_source(
  'buildings', '/source-files/buildings.gpkg');
SELECT * FROM mirror.register_file_source('heat', '/source-files/heat.tif');
```

### mirror.register_external_file

Register a single native file for reference history without decoding it.

```sql
FUNCTION mirror.register_external_file(source_name text, layer_name text,
  file_path text, file_format text)
RETURNS bigint
```

**Parameters.** `source_name`, `layer_name` identify the dataset. `file_path` is its trusted path
below `/source-files`; `file_format` is a nonblank supplied format label. All are required.

**Result.** `bigint`: the initial `mirror.registry.row_id`.

**Caller and preconditions.** Administrator; readable completed file, valid source/layer naming and
an available logical identity.

**Effects and transactions.** Validates naming/readability/checksum through `file_evidence`, inserts
an unaccepted `external_file` registration with namespace `database-container:/source-files`. No
payload, source relation, relational column definition or accepted history is created. Caller
transaction.

**Validation and limitations.** Cannot mix row and external-file storage for one identity. Active
file registration must be unique; a retired file registration may be followed by a new one. A
nonblank format is required, but no format parser validates content. Invoke `store_layer` next to
capture accepted evidence.

```sql
SELECT mirror.register_external_file(
  'climate', 'temperature', '/source-files/climate/temperature-v1.nc', 'NetCDF');
```

## Capture and publication: mirror

### mirror.store_layer

Capture one full source snapshot or one native-file manifest and attempt publication.

```sql
FUNCTION mirror.store_layer(source_name text, layer_name text,
  review boolean DEFAULT false, file_path text DEFAULT NULL, file_format text DEFAULT NULL)
RETURNS void
```

**Parameters.** `source_name`, `layer_name` select an active registration. `review` defaults to
false and must be non-NULL. `file_path` and `file_format` default to NULL; they override only the
next native-file manifest, falling back to the accepted/registered reference. They are invalid for
row sources.

**Result.** `void`. Inspect import status and diagnostics; a successful SQL statement may have
recorded a failed or staged attempt.

**Caller and preconditions.** Administrator; active current/unaccepted registration, no pending
staged import. Row ingestion needs explicitly configured ordered nonspatial stable keys. Every row
capture must cover the registered full scope.

**Effects and transactions.** Locks the registration row, creates an import attempt and one ordinary
staging table. Captures location, coverage, keys and exact row-column definitions, reusing any
identical older structure set. Reads row source once, or fingerprints a native file into a manifest.
Structural and threshold diagnostics are retained. Automatically invokes `accept_layer(...,true)`
only if validation/thresholds pass and review is false. No internal commit; persist diagnostics by
committing the caller statement/transaction.

**Validation and limitations.** Read/capture exceptions roll back the capture subtransaction, record
status `failed`, clear staging reference and issue WARNING. Validation problems or count changes
above default 1% retain status `staged`; first row imports lack a count baseline. Row/NULL count
thresholds compare common columns against current accepted history; zero old count makes any
increase exceed the threshold. Raster grid/band changes require review and valid-pixel counts are
checked. Stable keys must be unique/non-NULL, without duplicate column names or spatial types/direct
wrappers. Technical source-name collisions need explicit adapter renaming. Automatic publication
exceptions leave staging and diagnostic text. Partial/delta captures are unsupported.

```sql
SELECT mirror.store_layer('berlin_alkis', 'alkis:bezirk', review => true);
SELECT import_id, status, staging_table, validation_errors, threshold_failures
FROM mirror.import ORDER BY import_id DESC LIMIT 5;
```

### mirror.accept_layer

Publish the existing inspected staging cache atomically.

```sql
FUNCTION mirror.accept_layer(source_name text,layer_name text,
  automatic boolean DEFAULT false)
RETURNS void
```

**Parameters.** `source_name`, `layer_name` select the active registration with a staged import.
`automatic` defaults to false; true is reserved for validated automatic calls from `store_layer`.

**Result.** `void`; accepted import evidence and data are the result.

**Caller and preconditions.** Administrator; pending cache and captured schema/keys must be intact.
Native file must still be readable with exactly the staged size/checksum.

**Effects and transactions.** Locks registration/import/staging, revalidates and compares against
current accepted state. One timestamp closes changed/missing row versions and opens replacements,
updates accepted import evidence and registry summaries. Creates/extends `_stored`, indexes and
current view as needed. Compares native typed row output with C collation and exact spatial values
rather than whole-row GeoJSON. Unchanged versions keep their creating import; no-ops still record
accepted imports. Native changes replace registry reference versions; initial acceptance fills the
first registration. Drops staging and clears its reference. Caller transaction; exceptions roll back
publication and retain staging.

**Validation and limitations.** Manual acceptance bypasses count thresholds, never
key/layout/type/raster/file integrity. Accepted key definitions are immutable, including ordered
composite-key representation. Captured staging layout must match its exact column set; incompatible
type/collation changes require a new column or dataset. Missing keys close current versions even for
an empty approved vector snapshot; rasters require nonempty in-database tiles. Native manifests
require exactly one unchanged file and valid format/namespace. Current-view removal/reordering uses
RESTRICT, so unresolved dependencies fail publication. `automatic=true` additionally rejects
manual-review imports or recorded diagnostics; it is not a user override.

```sql
SELECT mirror.accept_layer('berlin_alkis', 'alkis:bezirk');
```

### mirror.reject_layer

Discard a pending capture without changing accepted state.

```sql
FUNCTION mirror.reject_layer(source_name text,layer_name text)
RETURNS void
```

**Parameters.** `source_name`, `layer_name`: active source/layer identity; no defaults.

**Result.** `void`.

**Caller and preconditions.** Administrator; non-retired current/unaccepted registration and one
staged import.

**Effects and transactions.** Locks registration and pending import, drops its staging table, marks
that same import rejected and clears its staging reference. Preserves accepted history and original
files. No internal commit.

**Validation and limitations.** Fails if the active registration or pending import is absent. A
later current Berlin build still sees rejection as the latest import: a new successful
capture/acceptance is needed for readiness. Rejection is not retirement or withdrawal.

```sql
SELECT mirror.reject_layer('berlin_alkis', 'alkis:bezirk');
```

## Refresh and retirement: mirror

### mirror.update_registered_sources

Refresh existing active registrations in deterministic source/layer order.

```sql
PROCEDURE mirror.update_registered_sources(review boolean DEFAULT false,
  source_type text DEFAULT NULL,skip_interval interval DEFAULT interval '1 hour')
```

**Parameters.** `review` defaults to false and must be non-NULL. `source_type` defaults to NULL for
both types; otherwise only `wfs` or `file` is valid. `skip_interval` defaults to one hour; NULL
disables freshness skipping and negative values are rejected.

**Result.** No output parameters or return value; inspect imports/notices.

**Caller and preconditions.** Administrator with mirror registration/capture privileges. Run as a
top-level `CALL` with autocommit; not inside an explicit transaction or a call chain that disallows
transaction control.

**Effects and transactions.** Locks each selected registration, refreshes WFS advertised revisions
once per source, skips pending imports/recent acceptances, otherwise invokes `store_layer`. COMMIT
after each selected dataset, including skip cases. Supports row and external-file registrations
without discovering layers. Earlier commits survive later errors.

**Validation and limitations.** HTTP/XML metadata errors stop the batch; source-read errors handled
by `store_layer` remain failed imports and processing can continue. Freshness uses successful
acceptance (`last_imported_at`), not last attempted capture. Advertised revisions are not copied
into accepted `data_revision_at`. New native versions must already be at the registered path or
staged explicitly via `store_layer` overrides.

```sql
CALL mirror.update_registered_sources(review => true, source_type => 'wfs',
                                      skip_interval => NULL);
```

### mirror.unregister_source

Retire a source or selected layer while preserving its records and relations.

```sql
FUNCTION mirror.unregister_source(source_name text,layer_name text DEFAULT NULL)
RETURNS void
```

**Parameters.** `source_name` selects the source. `layer_name` defaults to NULL for all active
layers, or selects one exact layer.

**Result.** `void`.

**Caller and preconditions.** Administrator; at least one active current/unaccepted matching
registration and no pending imports among selected rows.

**Effects and transactions.** Locks selected registrations and sets `retired=true`. Stops batch
refresh without deleting history, imports, adapters or source files. No object/file range closure
and no internal commit.

**Validation and limitations.** No active match or any pending import raises an exception and rolls
back the operation. Resolve staging first. Row-source identities cannot be registered again; native
files permit a new registration after retirement. Retired native ranges retain their bounds and may
overlap a later registration.

```sql
SELECT mirror.unregister_source('berlin_alkis', 'alkis:bezirk');
```

## Optional Berlin build: curation

### curation.curate_berlin_20261101

Reconstruct and atomically install the complete Berlin snapshot dataset.

```sql
PROCEDURE curation.curate_berlin_20261101(snapshot_at timestamptz DEFAULT NULL,
    region public.geometry DEFAULT NULL,git_revision text DEFAULT NULL)
```

**Parameters.** `snapshot_at timestamptz DEFAULT NULL`: omitted/NULL resolves once to current time
after locking; explicit values select accepted history. `region public.geometry DEFAULT NULL`: full
scope if NULL, otherwise whole features intersecting this region. `git_revision text DEFAULT NULL`:
caller-supplied revision, unknown stays NULL.

**Result.** No output parameters or return value. Six entity tables, three n:m tables and one
current `dataset_build` row are installed.

**Caller and preconditions.** Administrator execution privilege; 913 initialized, six Berlin row
registrations with compatible accepted inputs. For NULL snapshot, all required sources must be
active and each latest import accepted. Explicit snapshots need accepted imports at/before the
requested time, independently of later failure/pending/rejection/retirement.

**Effects and transactions.** Security definer with restricted search path and UTC. Takes advisory
transaction lock `(70303,1)` and EXCLUSIVE `mirror.registry` lock, validates readiness and resolves
current snapshot, then calls six entity steps and relationship construction. Installs with
transactional DELETE/INSERT, preserving output object identities/dependent queries and updating
`dataset_build` atomically. No internal commits; standalone CALL is atomic, outer transactions
control final commit. Failure preserves the previous committed complete dataset and build identity.

**Validation and limitations.** Snapshot must be finite and not future at validation. Region must be
valid/nonempty with positive explicit SRID compatible with inputs; no CRS conversion. Required
columns are checked against the accepted structure at that snapshot, not retained physical columns.
Bad casts, official-ID duplicates, geometry/relationship constraints or missing inputs fail the
build. No generic mapping, output record history, failure log or per-record lineage is added. Row
IDs are snapshot-local; Git revision is not automatically discovered. Relationship fractions are
intersection area / first-endpoint area, rounded to three decimals, retained above 0.02.

```sql
CALL curation.curate_berlin_20261101();
-- Historical example: choose a timestamp with all required accepted inputs.
CALL curation.curate_berlin_20261101(
  snapshot_at => TIMESTAMPTZ '2026-11-09 00:00:00+00',
  region => NULL, git_revision => NULL);
SELECT * FROM curation.dataset_build;
```

The required `(source_name, layer_name)` pairs are `berlin_alkis/alkis:land`,
`berlin_alkis/alkis:bezirk`, `berlin_alkis/alkis:flurstuecke`,
`berlin_alkis_gebaeude/alkis_gebaeude:gebaeude`, `berlin_bloecke/bloecke:rbs_bloecke` and
`berlin_adressen/adressen_rbs:adressen_rbs`. Entity outputs have prefix `berlin_` and suffixes
`city`, `district`, `block`, `plot`, `building`, `address`. Relationship suffixes are
`relation_building_block`, `relation_building_plot` and `relation_plot_block`. All belong to
`curation` and are queried directly.

## Shared scheduler visibility

`mirror.scheduled_jobs` is an ordinary read-only view for `utt_admin` and
`utt_developer`, with columns `jobid bigint`, `jobname name`, `schedule text`,
`command text`, `database text`, `username text` and `active boolean`. It projects
pg_cron's job catalogue for the current database, across job owners. It does not
cache results or expose write access. Example:

```sql
SELECT * FROM mirror.scheduled_jobs ORDER BY jobid;
```

Administrators manage their own jobs using upstream `cron.schedule`, `cron.alter_job`
and `cron.unschedule`; developers receive no scheduler execution privileges. Visibility
does not override upstream mutation/identity checks. The cron extension and its tables
retain bootstrap ownership. There are no UTT scheduler functions or configuration tables;
see the [scheduling workflow](user-guide.md#scheduling-refresh-with-pg_cron) for practical
calls, worker configuration and the disposable smoke test. Job SQL is shared information
through the view; never include credentials. Run history remains in the upstream
`cron.job_run_details` table under its per-owner policy.

## Internal routines for maintainers

These are implementation boundaries, not a second public workflow. Administrators normally execute
them only through their listed callers. Except `read_geotiff`, developers have no execution grants.
Trigger functions return PostgreSQL trigger results and cannot be invoked as ordinary SELECT
helpers. None commits internally. Examples of trigger firing operations below describe the boundary;
rejected writes are intentionally not runnable successful workflow examples.

### curation.curate_berlin_address_20261101

```sql
PROCEDURE curation.curate_berlin_address_20261101(snapshot_at timestamptz DEFAULT TIMESTAMPTZ '2026-11-01 00:00:00+00',
    region public.geometry DEFAULT NULL)
```

**Caller.** Public Berlin procedure in its build transaction.

`snapshot_at timestamptz` has an internal default of `2026-11-01 00:00:00+00`; `region
public.geometry DEFAULT NULL`. No result parameters. The public caller always passes its resolved
snapshot/region, so this internal default does not define public build behavior. Reads accepted rows
via `curation_berlin_source`, filters non-NULL/nonempty positive-SRID geometry and optional
intersections, orders by `utt_key`, recreates temporary `berlin_address_working` with output
constraints/indexes and analyzes it. ON COMMIT DROP; no output installation or commit. In the
orchestrator transaction, for a compatible accepted snapshot: `CALL
curation.curate_berlin_address_20261101(now(),NULL);`.

### curation.curate_berlin_block_20261101

```sql
PROCEDURE curation.curate_berlin_block_20261101(snapshot_at timestamptz DEFAULT TIMESTAMPTZ '2026-11-01 00:00:00+00',
    region public.geometry DEFAULT NULL)
```

**Caller.** Public Berlin procedure in its build transaction.

`snapshot_at timestamptz` has an internal default of `2026-11-01 00:00:00+00`; `region
public.geometry DEFAULT NULL`. No result parameters. The public caller always passes its resolved
snapshot/region, so this internal default does not define public build behavior. Reads accepted rows
via `curation_berlin_source`, filters non-NULL/nonempty positive-SRID geometry and optional
intersections, orders by `utt_key`, recreates temporary `berlin_block_working` with output
constraints/indexes and analyzes it. ON COMMIT DROP; no output installation or commit. In the
orchestrator transaction, for a compatible accepted snapshot: `CALL
curation.curate_berlin_block_20261101(now(),NULL);`.

### curation.curate_berlin_building_20261101

```sql
PROCEDURE curation.curate_berlin_building_20261101(snapshot_at timestamptz DEFAULT TIMESTAMPTZ '2026-11-01 00:00:00+00',
    region public.geometry DEFAULT NULL)
```

**Caller.** Public Berlin procedure in its build transaction.

`snapshot_at timestamptz` has an internal default of `2026-11-01 00:00:00+00`; `region
public.geometry DEFAULT NULL`. No result parameters. The public caller always passes its resolved
snapshot/region, so this internal default does not define public build behavior. Reads accepted rows
via `curation_berlin_source`, filters non-NULL/nonempty positive-SRID geometry and optional
intersections, orders by `utt_key`, recreates temporary `berlin_building_working` with output
constraints/indexes and analyzes it. ON COMMIT DROP; no output installation or commit. In the
orchestrator transaction, for a compatible accepted snapshot: `CALL
curation.curate_berlin_building_20261101(now(),NULL);`.

### curation.curate_berlin_city_20261101

```sql
PROCEDURE curation.curate_berlin_city_20261101(snapshot_at timestamptz DEFAULT TIMESTAMPTZ '2026-11-01 00:00:00+00',
    region public.geometry DEFAULT NULL)
```

**Caller.** Public Berlin procedure in its build transaction.

`snapshot_at timestamptz` has an internal default of `2026-11-01 00:00:00+00`; `region
public.geometry DEFAULT NULL`. No result parameters. The public caller always passes its resolved
snapshot/region, so this internal default does not define public build behavior. Reads accepted rows
via `curation_berlin_source`, filters non-NULL/nonempty positive-SRID geometry and optional
intersections, orders by `utt_key`, recreates temporary `berlin_city_working` with output
constraints/indexes and analyzes it. ON COMMIT DROP; no output installation or commit. In the
orchestrator transaction, for a compatible accepted snapshot: `CALL
curation.curate_berlin_city_20261101(now(),NULL);`.

### curation.curate_berlin_district_20261101

```sql
PROCEDURE curation.curate_berlin_district_20261101(snapshot_at timestamptz DEFAULT TIMESTAMPTZ '2026-11-01 00:00:00+00',
    region public.geometry DEFAULT NULL)
```

**Caller.** Public Berlin procedure in its build transaction.

`snapshot_at timestamptz` has an internal default of `2026-11-01 00:00:00+00`; `region
public.geometry DEFAULT NULL`. No result parameters. The public caller always passes its resolved
snapshot/region, so this internal default does not define public build behavior. Reads accepted rows
via `curation_berlin_source`, filters non-NULL/nonempty positive-SRID geometry and optional
intersections, orders by `utt_key`, recreates temporary `berlin_district_working` with output
constraints/indexes and analyzes it. ON COMMIT DROP; no output installation or commit. In the
orchestrator transaction, for a compatible accepted snapshot: `CALL
curation.curate_berlin_district_20261101(now(),NULL);`.

### curation.curate_berlin_plot_20261101

```sql
PROCEDURE curation.curate_berlin_plot_20261101(snapshot_at timestamptz DEFAULT TIMESTAMPTZ '2026-11-01 00:00:00+00',
    region public.geometry DEFAULT NULL)
```

**Caller.** Public Berlin procedure in its build transaction.

`snapshot_at timestamptz` has an internal default of `2026-11-01 00:00:00+00`; `region
public.geometry DEFAULT NULL`. No result parameters. The public caller always passes its resolved
snapshot/region, so this internal default does not define public build behavior. Reads accepted rows
via `curation_berlin_source`, filters non-NULL/nonempty positive-SRID geometry and optional
intersections, orders by `utt_key`, recreates temporary `berlin_plot_working` with output
constraints/indexes and analyzes it. ON COMMIT DROP; no output installation or commit. In the
orchestrator transaction, for a compatible accepted snapshot: `CALL
curation.curate_berlin_plot_20261101(now(),NULL);`.

### curation.curate_berlin_relations_20261101

```sql
PROCEDURE curation.curate_berlin_relations_20261101()
```

**Caller.** Public Berlin procedure after all six entity working tables exist in the same
transaction.

No parameters or returned values. Creates three temporary `_working` relation tables from this
build's endpoint tables, enforcing non-NULL endpoint IDs/fractions and pair primary keys. Endpoint
foreign keys and fraction-range checks are enforced on the installed output tables. Spatial-index
candidate probes precede intersections; divide intersection by first-endpoint area, round once to
three decimals and retain >0.02. Uses statistics prepared by the entity steps; the orchestrator
analyzes installed outputs. Does not install output or commit. Not an independently usable build
API. In the orchestrator transaction: `CALL curation.curate_berlin_relations_20261101();`.

### curation.curation_berlin_source

```sql
FUNCTION curation.curation_berlin_source(source_name text,layer_name text,
    snapshot_at timestamptz,required_columns text[])
RETURNS regclass
```

**Caller.** Berlin entity procedures.

`source_name`, `layer_name`, `snapshot_at timestamptz`, `required_columns text[]` have no defaults.
Returns stored relation `regclass` after finding the latest accepted import at/before snapshot and
checking required names in that exact structure. Raises for missing accepted state or columns; does
not write, infer types or require today's registration to be active. Example: `SELECT
curation.curation_berlin_source('berlin_alkis','alkis:land',now(),ARRAY['lan','namlan','geom']);`.

### mirror.file_evidence

```sql
FUNCTION mirror.file_evidence(file_path text)
RETURNS TABLE(file_size bigint, file_checksum text)
```

**Caller.** Native-file registration, staging and acceptance; security-definer file-reading
boundary.

`file_path text` must identify a readable regular file below `/source-files`; rejects dot segments,
backslashes, repeated slashes and trailing slash. Returns `(file_size bigint, file_checksum text)`.
Reads in 1 MiB blocks and checks byte count plus final size/modification evidence for changes during
reading. `sha256-chain-1m-v1`: initial digest is empty bytes; for each block set digest =
SHA256(digest || block), then return hex(SHA256(digest)). For an empty file this is SHA256(empty
bytes). It is not conventional whole-file SHA256 for nonempty files. Writes nothing and does not
parse payloads. Example: `SELECT * FROM
mirror.file_evidence('/source-files/climate/temperature-v1.nc');`.

### mirror.layer_extent

```sql
FUNCTION mirror.layer_extent(layer_table regclass)
RETURNS public.geometry
```

**Caller.** File registration and row acceptance.

`layer_table regclass` selects an existing relation. Returns `public.geometry` geographic envelope
in EPSG:4326 across geometry values or raster hulls; NULL for empty/nonspatial input or any nonempty
geometry with unknown SRID. Other transform errors propagate; raster bounds include NoData cells.
Reads the relation, writes nothing; transformations concern summary bounds, not stored source
geometry. Example: `SELECT mirror.layer_extent('mirror.berlin_alkis_alkis_bezirk'::regclass);`.

### mirror.object_base

```sql
FUNCTION mirror.object_base(source_name text, layer_name text DEFAULT NULL)
RETURNS text
```

**Caller.** Registration and native-file staging.

`source_name` is required; optional `layer_name` defaults to NULL. Returns normalized lowercase
readable `text` with punctuation replaced by underscores and edge underscores removed. Rejects
NULL/blank source names, empty normalized results and bases over 48 bytes. Does not write or resolve
collisions; registry/catalogue checks do that. Example: `SELECT
mirror.object_base('berlin_alkis','alkis:land');`.

### mirror.protect_history

```sql
FUNCTION mirror.protect_history()
RETURNS trigger
```

**Caller.** `protect_history` row trigger and `protect_history_truncate` statement trigger on
generated `_stored` tables, installed by acceptance.

No declared SQL arguments; row-trigger configuration passes registration ID through `TG_ARGV`.
Returns `trigger`/NEW for allowed changes. Verifies creating accepted-import ownership and rejects
deletion, source/identity rewrites, truncation and invalid range changes; permits only current-range
closure on update. Compares native output with exact spatial state. Example rejected operation:
`DELETE FROM mirror.berlin_alkis_alkis_bezirk_stored;`.

### mirror.protect_metadata

```sql
FUNCTION mirror.protect_metadata()
RETURNS trigger
```

**Caller.** Row and statement triggers on `mirror.registry`, `mirror.import` and
`mirror.source_columns`.

No SQL arguments; returns `trigger` with allowed NEW/OLD row. Rejects truncation, accepted-import
rewrites/deletion, column-definition rewrites and referenced registry identity/accepted-file
evidence changes; permits controlled closures, summaries and retirement. Uses native row output to
avoid GeoJSON conversion. Fires within the triggering statement and aborts invalid writes. Example
rejected operation: `UPDATE mirror.import SET data_revision_at=now() WHERE status='accepted';`.

### mirror.read_geotiff

```sql
FUNCTION mirror.read_geotiff(file_path text)
RETURNS TABLE (rid bigint, rast public.raster)
```

**Caller.** File registration and lazy raster source views; explicit developer grant supports
source-view reads.

`file_path text` must be a trusted file below `/source-files` without dot segments. Returns `(rid
bigint, rast public.raster)` tiles up to 256×256 pixels using output ordinality as `rid`.
Tile numbers are not a geographic identity guarantee across grid changes. NoData metadata
preservation has a reported unresolved issue; validate declarations/statistics against input.
Security definer enables only GTiff locally; reads through PostgreSQL file functions, limits input
to 256 MiB and validates decoded dimensions/bands. It does not explicitly require a known raster
SRID. Entire decoded raster must fit memory. Does not persist tiles. Preserve file/symlink trust
boundary. Example: `SELECT rid, public.ST_Metadata(rast) FROM
mirror.read_geotiff('/source-files/heat.tif');`.

### mirror.wfs_revision_dates

```sql
FUNCTION mirror.wfs_revision_dates(wfs_url text, capabilities xml DEFAULT NULL)
RETURNS TABLE (layer_name text, source_revision_at timestamptz)
```

**Caller.** WFS registration and batch refresh.

`wfs_url` is required; `capabilities xml DEFAULT NULL` supplies an already fetched capabilities
document, otherwise the helper fetches one. Returns `(layer_name text, source_revision_at
timestamptz)` from linked ISO metadata. Network/XML errors propagate; absent revision evidence
remains NULL. Writes nothing. HTTP timeout 30 seconds, connection timeout 10 seconds; UTC. These are
advertised metadata dates, not accepted-state revisions. Example: `SELECT * FROM
mirror.wfs_revision_dates('https://gdi.berlin.de/services/wfs/alkis');`.

### utt_pkg.apply_shared_privileges

```sql
FUNCTION utt_pkg.apply_shared_privileges()
RETURNS event_trigger
```

**Caller.** PostgreSQL `utt_shared_privileges` event trigger at `ddl_command_end`; bootstrap-owned
security definer.

No arguments; returns `event_trigger`. Assigns shared ownership to `utt_admin`, developer schema
usage/table/sequence SELECT, revokes PUBLIC/developer routine execution and grants admin execution;
specifically allows developer GeoTIFF reader execution. Handles shared schemas, eligible foreign
servers and admin-owned sandboxes. Skips extension members and bootstrap-owned provisioning
boundaries. Fires for the DDL tags enumerated in 902; modifying this hook requires
bootstrap-superuser authority. Example firing event: `CREATE TABLE mirror.example (id integer);`
(creates a real shared object).

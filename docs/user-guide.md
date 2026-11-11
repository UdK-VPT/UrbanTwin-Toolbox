# User Guide

This manual describes the current fresh-initialization workflow. Commands run from
the repository root. SQL source-management and build operations require the bootstrap
DBA or an individual `utt_admin` member; developer sessions can read accepted data
and create research objects in their sandboxes.

## Contents

1. [Introduction and prerequisites](#introduction-and-prerequisites)
2. [Installation and configuration](#installation-and-configuration)
3. [Connecting to UTTDB](#connecting-to-uttdb)
4. [Schemas, accounts and permissions](#schemas-accounts-and-permissions)
5. [Registering a WFS source](#registering-a-wfs-source)
6. [Configuring object identity](#configuring-object-identity)
7. [Ingesting and inspecting data](#ingesting-and-inspecting-data)
8. [Accepting or rejecting staging](#accepting-or-rejecting-staging)
9. [Current and historical queries](#current-and-historical-queries)
10. [Updating and retiring sources](#updating-and-retiring-sources)
11. [Local vector files and GeoTIFFs](#local-vector-files-and-geotiffs)
12. [Native files without conversion](#native-files-without-conversion)
13. [Project curation and Berlin](#project-curation-and-berlin)
14. [Persistence, administration and troubleshooting](#persistence-administration-and-troubleshooting)

## Introduction and prerequisites

UTT separates source capture from project interpretation. Mirror preserves the
attributes and geometry exposed by a source adapter—a reader connecting PostgreSQL
to an external service or file—together with accepted system-time history. Optional
curation reconstructs application-specific tables from that history.
Registration makes a source readable; ingestion captures it; acceptance publishes it.
These are separate steps so a questionable delivery can be inspected before it changes
what researchers see.

You need Docker with the Compose plugin, sufficient disk space for PostgreSQL history
and source files, and a SQL client (psql or the supplied pgAdmin). Basic SQL and
PostgreSQL knowledge are assumed. Building the image needs network access to its
pinned upstream dependencies. WFS operations also require network access from the
database container to the service and its metadata endpoints. No Python worker is
required for normal ingestion or curation.

The examples below use the Berlin district layer as a concrete row-source workflow.
They contact a real external service. Source names identify your registration, while
layer names are the exact names advertised by the source.

## Installation and configuration

Copy `.env.example` to `.env` using `cp .env.example .env` on Linux or
`Copy-Item .env.example .env` in PowerShell. Edit `.env` before starting the stack.

| Setting | Meaning |
|---|---|
| `UTTDB_POSTGRES_DB`, `UTTDB_POSTGRES_USER`, `UTTDB_POSTGRES_PASSWORD` | Initial database and bootstrap login credentials. The template uses `uttdb` and `postgres`; replace the example password. |
| `UTTDB_POSTGRES_PORT` | Host PostgreSQL port, normally 5432. Container connections use 5432. |
| `SRID`, `HEIGHT_EPSG`, `SRS_NAME` | Upstream 3DCityDB initialization settings. The template selects EPSG:25833; they do not automatically transform mirror data. |
| `PGADMIN_DEFAULT_EMAIL`, `PGADMIN_DEFAULT_PASSWORD`, `PGADMIN_PORT` | Initial pgAdmin account and host HTTP port, normally 5050. |

Keep instance credentials in the ignored `.env`; image versions, builds and mounts
belong in `compose.yml`. The Compose database fallback CRS differs from the template,
so use the reviewed `.env` consistently rather than relying on omitted values.

```sh
docker compose up -d --build
docker compose ps
docker compose logs -f uttdb
```

UTTDB builds as `utt/database:local` from the pinned 3DCityDB image and adds OGR and
HTTP extensions. On an empty database directory, upstream PostGIS/3DCityDB setup runs
first; `900-utt-init.sh` then processes `uttdb/init/` in filename order. Files 901–903
initialize infrastructure, privileges and mirror; 913 adds the Berlin demonstration.
The standard Compose mount includes all of them. Mirror itself has no curation dependency.

Wait for initialization to finish and check logs for SQL errors. Changing init SQL
or initialization environment variables does not update an existing database. This
manual does not prescribe a live-data migration.

## Connecting to UTTDB

From a host with psql installed, use the configured host port and database:

```sh
psql -X -h localhost -p 5432 -U postgres -d uttdb
```

Enter the password when prompted. Substitute your reviewed `.env` values. For the
unchanged template, psql is also available inside the database container:

```sh
docker compose exec uttdb psql -X -U postgres -d uttdb
```

### Using pgAdmin

pgAdmin provides browser-based PostgreSQL administration and SQL access. It starts
alongside UTTDB in the Compose stack, so you can follow this manual without installing
a separate SQL client.

1. Open [localhost:5050](http://localhost:5050), or the `PGADMIN_PORT` configured in `.env`.
2. Sign in with `PGADMIN_DEFAULT_EMAIL` and `PGADMIN_DEFAULT_PASSWORD`.
3. Expand the preconfigured UTTDB server and enter `UTTDB_POSTGRES_PASSWORD`.
4. Select the database and open Tools → Query Tool to execute this manual's SQL examples.

The browser login and database login are separate accounts. The supplied
[server registration](../pgadmin/servers.json) connects to `uttdb:5432` within the
Compose network, using database `uttdb` and login `postgres`. Edit the registration
in pgAdmin if your database or login differs. Host port changes do not change the
container's internal port.

pgAdmin accounts, preferences and saved connections persist in ignored `pgadmin/data/`.
The initial credentials and server registration seed fresh state; changing configuration
may require updating an existing pgAdmin setup manually. Stop the stack before
intentionally deleting that directory: deletion resets pgAdmin accounts, preferences
and saved connections. PostgreSQL data is stored separately in `uttdb/data/`.

### Executing the examples

Keep autocommit enabled for the sequential examples. If an explicit transaction
fails, issue `ROLLBACK` before retrying. A successful `SELECT` returning void does
not by itself mean an import was accepted: inspect `mirror.import` as shown below.

## Schemas, accounts and permissions


| Schema | Purpose |
| --- | --- |
| `citydb` | 3DCityDB's 3D city model |
| `citydb_pkg` | 3DCityDB routines |
| `mirror` | All source data, metadata, ingestion routines and accepted history |
| `utt_pkg` | Shared administration helpers, including developer sandbox provisioning |
| `curation` | Project SQL procedures, snapshot tables and current build identity |

[Initialization SQL](../uttdb/init/) defines exactly two NOLOGIN privilege roles:
`utt_admin` for trusted administration and `utt_developer` for researchers and developers.
Each human uses an individual login. Developers read tables/views in `mirror`,
`curation`, `utt_pkg`, `citydb` and `citydb_pkg`, and write only in their own sandbox.
Shared sequences cannot be advanced by developers. Mutating routines are admin-only;
the bounded, read-only `mirror.read_geotiff(text)` reader also permits developer
queries against registered raster source views. No generic service roles are created.

All privilege policy, provisioning and the future-object DDL hook live in `902`.
Shared objects are owned by `utt_admin`; the hook covers individual administrator
DDL and adapters moved into shared schemas. Creator-specific default privileges
provide developer table reads and revoke default public routine execution.
Existing 3DCityDB tables/routines retain their definitions but receive administrative
ownership; extension members retain their upstream ownership. Ordinary administrators
are not superusers. They inherit server-file read permissions for trusted source
administration. Bootstrap-owned provisioning routines and the DDL hook are narrow
privileged boundaries; their definitions and event-trigger lifecycle require the
bootstrap superuser. No metadata tables or auditing columns are added.

### Human accounts and sandboxes

Connect as the installation login configured by `UTTDB_POSTGRES_USER` to provision
the first administrator; `902` grants that bootstrap login `utt_admin` membership.
Subsequent provisioning calls run from individual administrator sessions:

```sql
CALL utt_pkg.create_admin('bob');
CALL utt_pkg.create_developer('alice'); -- returns login_name and sandbox_schema
SELECT utt_pkg.create_developer_sandbox('alice'); -- safely repeat existing setup
```

Accounts are created without passwords. Configure authentication through deployment
administration; for password authentication, use the bootstrap login's psql
`\password alice` command. Do not place passwords in initialization files or tables.
Deactivation prevents new logins; existing sessions remain connected. Sandbox deletion
is a separate explicit administrator operation, such as
`DROP SCHEMA sandbox_alice CASCADE`; it does not delete the account.

Developer names must be lowercase ASCII identifiers beginning with a letter;
`sandbox_<login>` must fit PostgreSQL's 63-byte identifier limit. Names are rejected
rather than normalized or truncated. Duplicate account creation fails. Sandbox
provisioning reuses only the expected owner's schema and preserves existing work.
A new developer sandbox contains no objects. Its owner can create and remove objects;
all developers automatically receive reads on new owner-created tables and views.
Administrators inherit ownership rights through membership in developer login roles.
An administrator may explicitly request a sandbox too; it uses inherited `utt_admin`
ownership to avoid PostgreSQL's prohibition on circular role membership.

Sandbox owners can deliberately revoke peer reads or grant additional access to their
own objects: native ownership permits this. Defaults establish the collaboration
policy, rather than restricting an owner's ability to change it. Normal shared-object
DDL needs no follow-up grants. Privileged operators must not disable the policy hook
or override shared ownership/ACLs. External application permissions require explicit
component-specific deployment configuration.


Create a first individual administrator using the bootstrap connection, configure
its authentication, then use that login for source administration. To disable an
account later, run `CALL utt_pkg.deactivate_account('alice');` as an administrator;
it retains data and memberships and does not terminate existing sessions.

A developer can create research results, for example:

```sql
-- In alice's own login session, after provisioning:
CREATE TABLE sandbox_alice.research_notes (note text);
```

Shared history is protected even from accidental administrator writes by integrity
triggers. Use the documented administration entries instead of editing import or
history records. There is no generic application-user role; application access
requires separately designed deployment permissions.

## Registering a WFS source

Registration discovers the service's advertised layers and creates read-only OGR
foreign tables plus registry entries. It does not create accepted feature history.
Choose a short, distinct source name and register once:

```sql
SELECT * FROM mirror.register_wfs_source(
  'berlin_alkis', 'https://gdi.berlin.de/services/wfs/alkis');
SELECT row_id, source_name, layer_name, table_base, stable_key, last_imported_at
FROM mirror.registry WHERE source_name = 'berlin_alkis' ORDER BY layer_name;
```

The function returns source relation names as `regclass` values. WFS titles,
abstracts, fees and access statements retain their published language; missing
metadata stays NULL and license rights are not inferred. An HTTP/XML failure,
layer mismatch or naming collision rolls back registration. Repeating registration
is not the update operation.

Each row dataset is identified by `(source_name, layer_name)` and has one immutable
registry `row_id`. Its readable `table_base` determines `<base>_source` (adapter),
`<base>_staging` (pending cache), `<base>_stored` (accepted history), and `<base>`
(current view). Names normalize source/layer words without hashes or truncation;
empty bases, collisions and bases over 48 bytes fail. Inspect actual registry names
rather than constructing them in applications. Native files use a different storage
mode introduced later.

## Configuring object identity

Before ingestion, identify source columns that uniquely and persistently identify
an object within this dataset. A row number or physical row position is unsuitable:
its value can change between downloads. Configure an ordered array of nonspatial,
non-NULL unique key columns:

```sql
UPDATE mirror.registry SET stable_key = ARRAY['name']
WHERE source_name = 'berlin_alkis' AND layer_name = 'alkis:bezirk';
```

For a genuine composite identifier use an ordered array such as
`ARRAY['district_code','object_number']` when those columns exist in your source.
Geometry, geography and raster identifiers (including direct array/domain wrappers)
are rejected. The technical `utt_key` preserves the ordered source key as a JSON
array serialized to text; original identifier columns remain available.

Once any history is accepted, its key definition cannot change. If a pending import
captured the wrong key, reject it before changing the configuration and re-staging.
A changed identity convention or registered scope requires a distinct dataset.
Do not repurpose registrations or accepted keys.

DBAs may configure `change_threshold_percent` (default 1) and declared `coverage`
before acceptance. Coverage is descriptive registered geographic/thematic scope,
not a query filter. Every ingestion must supply that entire scope. Published
`source_owner` wording may be supplied if known; absent ownership remains NULL.

## Ingesting and inspecting data

The adapter still reads the remote source. To capture a local, reviewable snapshot,
call `store_layer`. This first example explicitly requests review:

```sql
SELECT mirror.store_layer('berlin_alkis', 'alkis:bezirk', review => true);
SELECT i.import_id, i.status, i.staging_table, i.validation_errors,
       i.threshold_failures, i.accepted_at
FROM mirror.import i JOIN mirror.registry r ON r.row_id = i.registry_row_id
WHERE r.source_name = 'berlin_alkis' AND r.layer_name = 'alkis:bezirk'
ORDER BY i.import_id DESC;
```

Read the indicated staging table to inspect the actual cached delivery:

```sql
SELECT * FROM mirror.berlin_alkis_alkis_bezirk_staging LIMIT 20;
```

Staging is an ordinary retained table with the source columns and types, without
technical history columns. There is at most one pending import per dataset.
`mirror.import` records the source location, coverage, captured key and reusable
structure definition alongside validation results.

Without `review => true`, structurally valid snapshots are accepted automatically
when safety thresholds pass. Compare counts of rows and NULLs in common columns
against the current accepted state. A change exceeds the threshold when its absolute
count difference is greater than the old count times the configured percentage;
when the old count is zero, any increase exceeds it. First imports have no count
baseline. These checks detect suspicious delivery sizes, not scientific correctness.

Missing/duplicate keys, reserved source names (`row_id`, `utt_txn`, `import_id`,
`utt_key`), incompatible types or invalid raster structure prevent publication.
Reserved-name conflicts require explicit adapter renaming. Threshold failures and
structural problems retain staging with status `staged`. Source-read failures record
`failed`, clear the staging reference and preserve accepted state; warnings may be
returned rather than a SQL exception. Automatic publication errors also leave a
staged attempt with diagnostic text. Always inspect status before continuing.

## Accepting or rejecting staging

After inspecting the cached rows, choose one operation:

```sql
SELECT mirror.accept_layer('berlin_alkis', 'alkis:bezirk');
-- Alternatively, instead of accepting:
-- SELECT mirror.reject_layer('berlin_alkis', 'alkis:bezirk');
```

Acceptance revalidates the inspected cache without downloading row data again.
Manual acceptance can approve threshold changes but cannot bypass integrity checks.
It compares the delivery with current accepted state, closes changed or absent keys,
and inserts replacement versions at one acceptance timestamp. State, import evidence
and registry summaries publish atomically. A failed manual acceptance rolls back
publication and retains staging; after an explicit transaction error, roll back first.
Rejection drops staging and marks the same attempt rejected. Neither choice deletes
original source files. Acceptance and rejection clear the live staging-table reference.

Every row delivery is a full snapshot. Accepting fewer or zero rows can close current
objects missing from that snapshot; count thresholds hold suspicious reductions for
review, and manual acceptance can approve them. Empty raster deliveries fail integrity
validation. Failed reads never publish absence. Partial/delta ingestion is unsupported.
Disappearance from a source does not prove demolition or real-world termination.

A no-op acceptance still records an immutable accepted import. Unchanged versions keep
their creating import; changed source attributes, exact geometry/raster state, source
dates or structure evidence can produce new versions. Do not edit accepted records.

## Current and historical queries

After acceptance the ordinary current view exposes current source columns:

```sql
SELECT * FROM mirror.berlin_alkis_alkis_bezirk;
```

It reads the `_stored` history table and duplicates no data. Developers can query
both the view and history but cannot write shared data. Direct source-adapter reads
are live external reads, not accepted observations; OGR server access is administrative.
The GeoTIFF source reader has a specific developer execution grant.

To inspect version evidence and reconstruct an observed state:

```sql
SELECT row_id, utt_key, utt_txn, import_id
FROM mirror.berlin_alkis_alkis_bezirk_stored ORDER BY row_id;

-- Choose an acceptance timestamp actually available in this database.
SELECT h.* FROM mirror.berlin_alkis_alkis_bezirk_stored h
WHERE h.utt_txn @> (
  SELECT max(i.accepted_at) FROM mirror.import i
  JOIN mirror.registry r ON r.row_id = i.registry_row_id
  WHERE r.source_name = 'berlin_alkis' AND r.layer_name = 'alkis:bezirk'
    AND i.status = 'accepted');
```

For a fixed historical query replace the subquery with a real `TIMESTAMPTZ` literal.
Ranges are `[start,end)`: the opening instant is included; the closing instant is
excluded; current versions have an unbounded end. System time records when UTT
accepted a state, not when the source or the real world changed. History begins at
first acceptance and cannot reconstruct changes between observations. Source dates
remain ordinary attributes, even if their values move backwards.

For historical interpretation, join `h.import_id` to `mirror.import`, then use its
`registry_row_id` and `structure_version` to inspect `mirror.source_columns`.
Definitions retain column order, type/modifier/collation and comments, reusing any
identical earlier set. Additions leave historical values NULL; removals retain the
physical history column while excluding it from the current view. Structure evidence
distinguishes an absent column from a supplied NULL. Incompatible type/collation or
meaning changes require a new column or dataset. View removal/reordering may be
blocked by dependencies: resolve them explicitly; UTT does not cascade-drop them.

## Updating and retiring sources

For one dataset, call `store_layer` again after resolving pending review. It captures
the next full snapshot and follows the same checks. To refresh existing registrations
as a batch, use a top-level procedure call with autocommit:

```sql
CALL mirror.update_registered_sources();
-- Force freshness checks off and retain each captured delivery for review:
CALL mirror.update_registered_sources(review => true, skip_interval => NULL);
```

Do not enclose the batch in `BEGIN/COMMIT`. It commits each active dataset separately,
skips pending imports, and by default skips acceptances newer than one hour. Earlier
commits survive a later error. `source_type => 'wfs'` or `'file'` limits the batch;
NULL includes both. It does not discover new layers. Metadata HTTP/XML errors stop
the batch; source-read failures are recorded as failed attempts.

WFS `registry.source_revision_at` is the latest advertised revision, possibly newer
than accepted data. `import.data_revision_at` stays NULL unless reliably tied to
captured bytes; current adapters do not establish that association. Neither is an
inferred real-world validity date.

When a dataset should no longer refresh, resolve pending imports and retire it:

```sql
SELECT mirror.unregister_source('berlin_alkis', 'alkis:bezirk');
-- Omitting layer_name retires all active layers of the named source.
```

Retirement preserves registry entries, imports, adapters, current data and history;
it does not close object ranges. Referenced registrations must not be deleted or
repurposed. A row-source identity remains registered even after retirement. Native
files additionally support a new registration after retirement, as described below.

### Scheduling refresh with pg_cron

The database image includes pg_cron 1.6.8. Compose preloads it and selects the
configured UTT database for its catalogue from the first server startup; fresh
initialization creates the extension in that database. It installs no jobs. Background-worker execution requires no
scheduler password and makes no changes to database authentication. Compose limits
concurrent jobs to two and uses UTC schedules; they share PostgreSQL's worker budget
with other database features. Superuser jobs are disabled: connect as your individual
nonsuperuser administrator login to manage and execute jobs.

To opt into a daily refresh at 03:00 UTC, run as that administrator:

```sql
SELECT cron.schedule('mirror-daily-refresh', '0 3 * * *',
                     'CALL mirror.update_registered_sources();');
SELECT * FROM mirror.scheduled_jobs ORDER BY jobid;
```

The scheduled command must be that single top-level `CALL`: do not prepend `SET`,
wrap it in `BEGIN/COMMIT` or combine it with other statements. The refresh procedure
commits datasets internally. Its existing skip/review/failure behavior still applies;
a successful scheduler run is not proof that every source was accepted. Check
`mirror.import` as well. Each job executes with its scheduling login's permissions;
deactivation or removal of those permissions can stop later runs. Schedule under
your individual login, not `SET ROLE utt_admin` (the group role cannot log in).

Both administrators and developers can query `mirror.scheduled_jobs`. It is an
ordinary, deliberately non-updatable view of this database's job configuration,
including SQL text and execution login. Re-run SELECT or refresh pgAdmin's query
results to see changes; no synchronization writes are needed. Do not embed credentials
in job commands. Developers cannot schedule, alter or remove jobs. Administrators
can see the shared configuration, but standard mutation functions still apply their
job-ownership rules; shared visibility does not authorize editing another login's jobs.

Inspect your own execution history and change or stop your job through standard APIs:

```sql
SELECT jobid, status, return_message, start_time, end_time
FROM cron.job_run_details ORDER BY start_time DESC LIMIT 20;

SELECT cron.alter_job(jobid, schedule => '0 4 * * *')
FROM cron.job WHERE jobname='mirror-daily-refresh' AND username=current_user;

SELECT cron.alter_job(jobid, active => false)
FROM cron.job WHERE jobname='mirror-daily-refresh' AND username=current_user;
-- Enable again by passing active => true. Disable before removing a running job.
SELECT cron.unschedule('mirror-daily-refresh');
```

Disabling prevents subsequent launches; it is not a guarantee that an already running
command has stopped. Unscheduling removes the definition, not its run history or
committed database effects. History is subject to pg_cron's per-owner row policy;
the bootstrap DBA can inspect all runs. There is no automatic history-retention job.
The bootstrap DBA can explicitly prune `cron.job_run_details` according to deployment
retention requirements. All these are upstream pg_cron interfaces, not UTT wrappers.

Check startup and configuration with:

```sql
SHOW shared_preload_libraries;
SHOW cron.database_name;
SHOW cron.use_background_workers;
SHOW cron.max_running_jobs;
SELECT extversion FROM pg_extension WHERE extname='pg_cron';
```

The image pins source release 1.6.8; pg_cron reports its SQL extension version as
`1.6` in `pg_extension`, which does not include the source patch number.

The preload list and scheduler settings live in Compose's `postgres -c` arguments.
The pinned upstream image requires no additional preload libraries. If another
preload-dependent extension is added, extend the explicit list in Compose; the list
overrides any `shared_preload_libraries` value in PostgreSQL configuration files.
Other file-based settings are unaffected unless explicitly overridden by a startup
argument. The upstream entrypoint forwards these options to both its temporary
socket-only initialization server and the final server, so no extra restart or
`ALTER SYSTEM` configuration is needed. `900-utt-init.sh` only loads UTT init files.

`cron.database_name` uses the same `.env` value and Compose fallback as `POSTGRES_DB`.
Keep the database name consistent for an initialized instance: changing `.env` does
not rename or create an existing database. Recreate the container to apply changed
Compose startup arguments; simply restarting an existing container does not update
its command. Editing init files does not install the extension into existing state.
This integration targets fresh deployment and contains no live-database migration.

For a no-network smoke test, use an **empty disposable initialized UTTDB**, connect
psql as its bootstrap DBA through standard `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`
and authentication settings, then run from the repository root:

```sh
python3 tests/pg-cron-smoke.py --disposable
```

It commits fixtures across sessions, schedules short-lived jobs under a nonsuperuser
administrator, verifies internal COMMIT and a real refresh of a local SQL fixture,
checks developer visibility/denied writes, and removes its jobs and fixtures.
It refuses a database containing registrations or jobs. It is not a rollback-only
suite and must not run against a research instance. A container build, fresh startup,
this test and a restart/configuration check are required before staging deployment;
source inspection alone does not establish deployment readiness.

## Local vector files and GeoTIFFs

Place original files below `uttdb/source-files/` before registering them. Compose
mounts this folder read-only at `/source-files` inside PostgreSQL. SQL paths use the
container path, even on Windows. Preserve vector sidecars and ensure the database
OS user can read files and traverse directories on Linux. Finish uploading first.

```sql
SELECT * FROM mirror.register_file_source(
  'buildings', '/source-files/buildings.gpkg');
SELECT source_name, layer_name, table_base, stable_key FROM mirror.registry
WHERE source_name = 'buildings';
```

OGR discovers vector layers; GDAL detects the driver unless supplied. Set each
layer's stable key, then use `store_layer`, inspect its import, and accept or reject
exactly as with WFS. File registration scans bounds but does not accept source rows.
Published metadata remains NULL because generic file metadata extraction is absent.
A CSV adapter can use explicit options:

```sql
SELECT * FROM mirror.register_file_source(
  'points', '/source-files/points.csv', 'CSV',
  'X_POSSIBLE_NAMES=longitude Y_POSSIBLE_NAMES=latitude');
```

For a self-contained GeoTIFF:

```sql
SELECT * FROM mirror.register_file_source('heat', '/source-files/heat.tif');
SELECT mirror.store_layer('heat', 'heat.tif', review => true);
-- Inspect the import and its raster cache before:
SELECT mirror.accept_layer('heat', 'heat.tif');
```

A `.tif`/`.tiff` without an explicit driver, or explicit `GTiff`, uses UTT's raster
reader. It decodes the entire file in memory and emits tiles up to 256×256 pixels,
with bands and georeferencing. Input is limited to 256 MiB; decoded
pixels must also fit memory. No `open_options` are supported for this adapter.
The layer name is the filename; `rid` numbers tiles in the reader's output order.
These numbers do not establish geographic tile identity across changed grids.
Registration validates decoding and creates a lazy view, persisting no pixels until
acceptance. Repeated live reads decode the file again.
NoData metadata preservation has a reported unresolved issue; check NoData declarations
and raster statistics against the original file before using accepted pixels in analysis.

Raster checks compare complete tile inventories, grid/band metadata and valid-pixel
counts. Changed grids require review. An approved complete replacement can close
removed tiles, while invalid or empty tiles remain unacceptable. Larger rasters,
external-band payloads and specialized formats may instead remain native files;
reference tracking does not make their contents SQL-queryable.

## Native files without conversion

For NetCDF or another format that should remain outside PostgreSQL, register one
independently versioned file per logical dataset/layer:

```sql
SELECT mirror.register_external_file(
  'climate', 'temperature', '/source-files/climate/temperature-v1.nc', 'NetCDF');
SELECT mirror.store_layer('climate', 'temperature', review => true);
SELECT import_id, status, staging_table, validation_errors FROM mirror.import
ORDER BY import_id DESC LIMIT 5;
SELECT * FROM mirror.climate_temperature_staging;
SELECT mirror.accept_layer('climate', 'temperature');
```

Registration validates readability and returns a registry ID, but starts no accepted
history. There is no parser, required geometry, relational source schema, `_stored`
table or current view. Staging contains a one-file manifest recording its path, format,
namespace, size and checksum rather than its contents. Acceptance re-reads the file
and verifies its size and checksum. Changed bytes invalidate the staged evidence:
reject and stage again rather than accepting newer bytes silently.

Keep accepted bytes unchanged at version-specific paths. To propose a replacement,
use the normal workflow with a path override for the next manifest:

```sql
SELECT mirror.store_layer('climate', 'temperature', review => true,
  file_path => '/source-files/climate/temperature-v2.nc');
-- Inspect the manifest and import before publishing:
SELECT mirror.accept_layer('climate', 'temperature');
SELECT row_id, source_url, path_namespace, file_format, file_size,
       file_checksum, checksum_algorithm, file_txn, import_id, retired
FROM mirror.registry
WHERE source_name = 'climate' AND layer_name = 'temperature' ORDER BY row_id;
```

Changed path, format or content creates a replacement registry version; unchanged
references record only an import. The initial accepted version fills the original
registration. `path_namespace` identifies `database-container:/source-files`.
Historical queries filter `file_txn @> <timestamp>`; active current selection also
requires `NOT retired` and an unbounded range (or NULL for an unaccepted registration).

The checksum contract is `sha256-chain-1m-v1`: start with an empty byte string, hash
the preceding digest concatenated with each successive 1 MiB block, then hash the
final digest and encode it as hexadecimal. It also defines an empty-file result.
This bounded-memory fingerprint is not conventional whole-file SHA256. Modification
times alone do not establish equality. Only trusted DBAs should manage source files
and symlinks.

A retired native-file identity may be registered again, producing a new registry
row. Archived ranges are not closed by retirement and may overlap later registrations;
historical queries can therefore return both archived and later references. Use
`row_id` and `retired` to distinguish them. Imports retain exact registration references.
Neither missing files nor read errors imply withdrawal. Rejection never deletes bytes.

Registry history cannot restore overwritten or missing files. Retain original bytes
and backups separately; database rollback cannot undo filesystem changes. Native
time coordinates remain source metadata. Native-file registration tracks references
and evidence without parsing or curating their contents.

## Project curation and Berlin

Curation is optional SQL that interprets accepted mirror data for a specific project.
The provided Berlin recipe is the implemented project-specific demonstration.
Its outputs are replaceable ordinary snapshot tables, without independent record history.

The [Berlin SQL example](../example/berlin.sql) registers four WFS services, configures
stable keys and ingests these six layers:

| Source | Layer | Key | Entity |
|---|---|---|---|
| `berlin_alkis` | `alkis:land` | `lan` | City |
| `berlin_alkis` | `alkis:bezirk` | `name` | District |
| `berlin_alkis` | `alkis:flurstuecke` | `fsko` | Plot |
| `berlin_alkis_gebaeude` | `alkis_gebaeude:gebaeude` | `uuid` | Building |
| `berlin_bloecke` | `bloecke:rbs_bloecke` | `blknr` | Block |
| `berlin_adressen` | `adressen_rbs:adressen_rbs` | `adr_ident` | Address |

Run it as a DBA from the repository root with a configured psql connection:

```sh
psql -X -v ON_ERROR_STOP=1 -f example/berlin.sql
```

The full script contacts public services and downloads large datasets. Each mirror
step commits separately; do not wrap the script in an outer transaction. Resolve
staged/failed imports before the final build. After an explicit failed step, roll
back and retry that step rather than re-registering successful sources.

Once all six active sources have accepted latest imports, the public entry point is:

```sql
CALL curation.curate_berlin_20261101();
SELECT * FROM curation.dataset_build;
SELECT * FROM curation.berlin_building LIMIT 20;
SELECT * FROM curation.berlin_relation_building_plot LIMIT 20;
```

Omitting `snapshot_at`, or supplying NULL, selects one current mirror timestamp after
locking. The procedure validates readiness and builds all outputs atomically. A latest
staged, failed or rejected attempt blocks a current build; resolve the source workflow,
including a fresh successful import after rejection if necessary. Callers do not
supply lock operations or coordinate the entity steps themselves.

For historical reconstruction choose a finite timestamp at or before build time,
after the required source acceptances and with the recipe's required columns:

```sql
CALL curation.curate_berlin_20261101(
  snapshot_at => TIMESTAMPTZ '2026-11-09 00:00:00+00',
  region => NULL, git_revision => NULL);
```

The date above is illustrative; use one represented in your database. Explicit
snapshots can reconstruct accepted history despite later failed/pending imports or
retirement. `git_revision` is optional caller-supplied build identity, not inferred.
A NULL region includes the entire registered scope. A supplied valid, nonempty region
must use a compatible source CRS; no transformation is inferred. Intersecting objects
are kept whole, including boundary crossers. Missing required columns, incompatible
casts/CRS or invalid output constraints fail the build and preserve previous committed
outputs and build metadata. Standalone `CALL` is atomic; an outer transaction may
control commit, and there are no internal commits.

The outputs are `curation.berlin_city`, `berlin_district`, `berlin_block`, `berlin_plot`,
`berlin_building`, `berlin_address`, and `berlin_relation_building_block`,
`berlin_relation_building_plot`, `berlin_relation_plot_block` in the same schema.
Official IDs retain domain meaning; snapshot-local `row_id` values can change on rebuild.
Do not persist cross-build references to those row IDs. Unavailable enrichment fields
remain typed NULL. Block `datum` and plot `beg` map to `source_date`; address `aufn_dt`
maps to `address_date`, all ordinary source attributes.

Each relationship stores one unique endpoint pair, foreign keys and overlap fraction.
Intersection area is divided by the first endpoint's area (building or plot), rounded
to three decimals and retained above 0.02. Matches can be many-to-many (n:m): a building
can overlap several plots, and a plot can overlap several buildings. Each pair remains
a separate row. These relations use only entities from the same build.

`dataset_build` stores one current successful identity: recipe, optional Git revision,
actual mirror snapshot, region and completion time. It is not an execution log or
complete per-record provenance. Reconstruct older outputs from retained mirror history
and SQL revisions; rebuilding replaces today's curated tables.

## Persistence, administration and troubleshooting

| Location | Contents and responsibility |
|---|---|
| `uttdb/data/` | PostgreSQL state; back up using database-appropriate procedures. |
| `uttdb/source-files/` | Original datasets, sidecars and historical native bytes; retain and back up independently. |
| `pgadmin/data/` | pgAdmin accounts, saved connections and preferences. |
| `.env` | Instance credentials/settings; ignored by Git and managed separately. |

`docker compose down` preserves bind mounts. Stop the stack before deliberately
resetting data directories; removing `uttdb/data/` destroys database state and triggers
fresh initialization next time. Do not remove source files as part of a database reset.
Changing pgAdmin bootstrap settings does not necessarily change an existing account.
This repository does not supply an automated backup/restore service.

| Symptom | Check and next step |
|---|---|
| Startup or connection fails | Inspect `docker compose ps` and `docker compose logs uttdb`; check ports, `.env`, initialization errors and directory permissions. |
| pgAdmin cannot reach PostgreSQL | Use Compose hostname `uttdb`, port 5432 and the configured database/login. |
| Registration reports a collision | Inspect registry and catalogue names; choose a shorter distinct name. Do not delete referenced metadata. |
| Ingestion returns with no new accepted rows | Inspect the latest import status and diagnostic arrays; void return is not acceptance evidence. |
| Another ingestion is refused | Inspect and accept/reject the existing staged import first. |
| Manual acceptance fails | Repair configuration where permitted or reject and re-stage; integrity errors cannot be overridden. |
| Schema update is blocked by a view dependency | Resolve dependent queries explicitly before retrying acceptance; retained history is preserved. |
| Native-file checksum changed | Finish upload, reject stale evidence and stage again; retain accepted paths unchanged. |
| Batch reports invalid transaction termination | Run the batch as a top-level `CALL` with autocommit, outside explicit transactions. |
| Current Berlin build says inputs are unready | Inspect the six latest imports and active registrations; complete acceptance or re-ingest after rejection/failure. |
| Historical query/build is empty or fails | Check acceptance times, exact historical column definitions and whether the requested state was ever observed. |

The SQL regression scripts target disposable databases; do not run them against a
research instance merely to check documentation. A representative invocation is
`psql -X -v ON_ERROR_STOP=1 -f tests/mirror.sql` with connection settings supplied.
`mirror.sql` checks publication and full snapshots; `mirror-geometries.sql` checks
exact spatial state; `source-columns.sql` checks structure reuse. `mirror-files.sql`
and `mirror-file-retirement.sql` need the small fixtures generated by
`python3 tests/create-mirror-fixtures.py` (or `python` on Windows) under the mounted
source directory; remove
only those generated fixtures afterwards. `curation-berlin.sql` checks snapshot
contracts, readiness and rollback; `spatial-relations.sql` checks relationship integrity
and a 3,000-row index plan; `privileges.sql` requires the bootstrap login and checks
account/DDL boundaries. These scripts roll back fixture database changes.
`core-independence.sql` runs after 901–903, before optional 913, with upstream `citydb`
and extensions present. No full Berlin download is needed for those fixture checks.

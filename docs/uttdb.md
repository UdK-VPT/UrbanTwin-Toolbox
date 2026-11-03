# UTTDB

UTTDB uses 3DCityDB v5 on PostgreSQL/PostGIS. The [database image](../custom-db-docker-image/Dockerfile)
provides `ogr_fdw`, `postgres_fdw`, `http` and PostGIS Raster.
Configure credentials, port and coordinate system in `.env` before first startup.
Image versions and build settings live in `compose.yml`.

## Schemas and access

| Schema | Purpose |
| --- | --- |
| `citydb` | 3DCityDB's 3D city model |
| `mirror` | All source data, metadata, ingestion routines and accepted history |
| `utt_pkg` | Shared administration helpers, including developer sandbox provisioning |
| `curation` | Project SQL procedures, snapshot tables and current build identity |

[Initialization SQL](../uttdb/init/) creates extensions and NOLOGIN group roles:
`uttdb_dba`, `uttdb_reader`, `uttdb_developer`, `uttdb_pipeline`,
`uttdb_app_reader` and `uttdb_app_writer`. A DBA provisions developer sandboxes with
`SELECT utt_pkg.create_developer_sandbox('existing_login');`. Developers receive read
access and work in their sandbox; pipeline users execute the Berlin build procedure
without direct curated-table writes. App writers receive no curation entry point.

Core files `901`–`903` initialize mirror and infrastructure without `curation`.
`913-curation.sql` adds the optional Berlin demonstration: six ordinary entity tables and
three n:m relationship tables, all prefixed `curation.berlin_`. Each entity has a
snapshot-local `row_id` and unique official identity. Relationship rows reference
endpoint `row_id` values with foreign keys and unique pairs. These IDs may be
reassigned on rebuild; do not treat them as durable cross-build identifiers.
Source keys and official identifiers retain their separate meanings.

Geometry columns have GiST indexes, including the block centroid. Curated tables
have no system-time ranges or historical readers. To obtain an older dataset,
rebuild from retained mirror history with an explicit snapshot timestamp.

## Mirror workflow

Run registration, staging and acceptance as a DBA. Registration records a dataset
in `mirror.registry`; it does not accept its contents. Row-based WFS/vector/GeoTIFF
sources use registry-controlled names: `<base>_source` is the read-only adapter,
`<base>_staging` is the pending cache, `<base>_stored` holds accepted history, and
`<base>` is a read-only current view. Registration generates readable source/layer bases without hashes. Empty,
overlength or colliding names are rejected rather than silently shortened or suffixed.
Inspect the registry for actual names; use shorter, distinct source names if needed.

```sql
SELECT * FROM mirror.register_wfs_source(
  'berlin_alkis', 'https://gdi.berlin.de/services/wfs/alkis');
UPDATE mirror.registry SET stable_key = ARRAY['name']
WHERE source_name = 'berlin_alkis' AND layer_name = 'alkis:bezirk';
SELECT mirror.store_layer('berlin_alkis', 'alkis:bezirk');
SELECT source_name, layer_name, table_base, stored_table, last_imported_at
FROM mirror.registry WHERE storage_mode = 'rows';
```

Declare non-NULL, unique stable source keys before row ingestion. Composite keys
are supported through ordered column-name arrays; do not use physical row positions.
Keys are captured with each import and cannot change after acceptance; changing a
pending key definition requires rejection and re-staging. GeoTIFF registration
supplies the adapter's deterministic tile key `rid` and declares a complete tile
inventory: manual approval of a changed grid can therefore close removed tiles.

Local vector datasets still use OGR. Self-contained GeoTIFFs can instead become
in-database raster tiles; this adapter reads at most 256 MiB and decodes in memory.
Use native-file registration below when the original format should stay outside
PostgreSQL. Original files belong in `uttdb/source-files/`, mounted read-only at
`/source-files`; preserve sidecars and grant the database OS user read access.

```sql
SELECT * FROM mirror.register_file_source(
  'buildings', '/source-files/buildings.gpkg');
-- Inspect discovered layers, then configure stable_key before storing them.
SELECT * FROM mirror.register_file_source(
  'heat', '/source-files/heat.tif');
```

Staging reads the source once and creates a `mirror.import` attempt. Validation
checks stable keys and column types; reserved `row_id`, `utt_txn`, `import_id` or
`utt_key` source names require explicit renaming in the adapter. Row counts and
per-column NULL counts must stay within `change_threshold_percent` (default 1%).
These thresholds hold suspiciously different snapshots for review. Raster checks also compare tile
grids, band metadata and valid-pixel counts. First imports have no count baseline.

A structurally valid snapshot is automatically accepted when thresholds pass and
review was not requested. Threshold failures and structural validation errors retain
the same staging cache; failed source reads record a failed attempt without changing accepted data. Fix
validation problems or reject the cache and stage again. Manual acceptance can
bypass thresholds but still rechecks keys, captured structure and raster integrity.

```sql
SELECT mirror.store_layer('berlin_alkis', 'alkis:bezirk', review => true);
SELECT import_id, registry_row_id, status, staging_table,
       validation_errors, threshold_failures
FROM mirror.import WHERE status = 'staged';
-- Inspect the indicated mirror staging table, then choose one:
SELECT mirror.accept_layer('berlin_alkis', 'alkis:bezirk');
-- SELECT mirror.reject_layer('berlin_alkis', 'alkis:bezirk');
```

Acceptance compares all source attributes, including geometry and source dates.
Changed objects close the previous `utt_txn` and open a replacement at one database
timestamp. Unchanged objects keep their identities; an unchanged successful import
still creates an immutable accepted-import record. `utt_key` is a canonical JSON
array serialized as text for the configured source key; it is technical metadata,
not a substitute for preserving source columns. Accepted versions reference their
creating `import_id`. History and current views reject ordinary pipeline writes.

Every row ingestion is treated as the full snapshot of its registered source scope.
Acceptance closes current mirror versions whose stable keys are missing from that
snapshot. This includes automatically accepted updates within the count thresholds.
An unusually small or empty update stays staged for review; rejection leaves current
state untouched, while explicit acceptance closes the missing versions. Failed reads
never publish absence. Historical rows remain stored, and source disappearance does
not describe real-world demolition; a later snapshot rebuild reflects source absence.

Partial/delta ingestion is unsupported. Registered `coverage` describes the dataset
scope and is captured per import, along with source location; it cannot be overridden
per attempt. Changing an accepted dataset's scope requires a distinct registration.
`source_owner` retains supplied published wording and otherwise stays NULL.
Retirement via `unregister_source()` stops refresh while preserving registry,
imports, history and original files; it does not itself withdraw source objects.

`mirror.source_columns` stores column order, exposed types and available comments
once per distinct structure for a registration. Each import records its
`structure_version`: identical structures reuse existing definitions, including an
older matching set if the source returns to it. Additions retain old rows with NULL
in the new columns;
removals retain the old physical columns but omit them from the current view. A
changed column layout or documented meaning versions incoming objects so their
creating imports identify the correct structure. Incompatible type/collation changes
are held for explicit review: use a new column or distinct dataset, rather than rewriting historical values.
A removed/reordered current view cannot be recreated while dependent objects block
it; resolve those dependencies explicitly. Historical column meaning and units must
be documented, not inferred from values or silently repurposed names.

### Native files without database conversion

NetCDF and other specialist formats can remain files. Their registrations and
accepted reference versions live directly in `mirror.registry`; there is no separate
file-tracking table and no required geometry, foreign table or PostGIS conversion.
Register independently versioned files as separate logical dataset/layer identities.

```sql
SELECT mirror.register_external_file(
  'climate', 'temperature', '/source-files/climate/temperature-v1.nc', 'NetCDF');
SELECT mirror.store_layer('climate', 'temperature');
-- Stage a replacement without changing the accepted registry row:
SELECT mirror.store_layer('climate', 'temperature', review => true,
  file_path => '/source-files/climate/temperature-v2.nc');
SELECT mirror.accept_layer('climate', 'temperature');
SELECT row_id, source_url, file_format, file_size, file_checksum, utt_txn
FROM mirror.registry
WHERE source_name = 'climate' AND layer_name = 'temperature'
  AND utt_txn @> TIMESTAMPTZ '2026-10-28 12:00:00+00';
```

The pending staging table is a one-file manifest. Acceptance re-reads the file and
checks its size and checksum before publishing. A changed path, format or content
creates another immutable registry version; a no-op only records an import.
`path_namespace` identifies the database container's `/source-files` mount.
The bounded-memory `sha256-chain-1m-v1` checksum hashes fixed 1 MiB blocks in sequence;
its precise algorithm is documented on `file_evidence()`. It is not a normal
whole-file SHA256 checksum. Native temporal coordinates stay in the original file;
`utt_txn` records UTT's acceptance history only.

Keep accepted files unchanged at version-specific paths when historical byte
retrieval matters. Registry history preserves paths and checksums, not file payloads;
a missing/overwritten file cannot be recovered from PostgreSQL. File retention and
backups remain separate. Failed reads do not withdraw a file. Only trusted DBAs
should administer files and symlinks below the source mount.

### Refresh and revision evidence

```sql
-- Top-level CALL with autocommit; not inside BEGIN/COMMIT.
CALL mirror.update_registered_sources();
CALL mirror.update_registered_sources(review => true, skip_interval => NULL);
```

Batch refresh commits each active dataset separately, skips pending imports and
recent successful acceptances, and supports both row-based and native-file sources.
It does not discover new layers. WFS `source_revision_at` remains the latest
advertised dataset revision and may be newer than accepted data. HTTP/XML metadata
errors stop the batch; failed source reads are recorded as failed imports.

Accepted `mirror.import.data_revision_at` remains NULL unless an adapter can reliably
associate a revision with the captured bytes. Current WFS/file adapters cannot prove
that association; advertised revisions are not copied into accepted evidence.
Curation reads exact accepted source versions and import identities. It does not
use advertised revisions to infer valid time. Ordinary mapped source dates can
change independently of advertised dataset metadata.

[example/berlin.sql](../example/berlin.sql) registers sources and accepts the six
Berlin layers, committing each mirror step independently. It then explicitly pins
one timestamp after those acceptances and builds the complete curated dataset in
one transaction. Run without an outer transaction; roll back a failed step and
retry it, preserving earlier mirror commits.

## Snapshot curation

The one functional Berlin recipe preserves the established ID conversions, nullable
descriptive values, boolean conversion and representative block point. Block `datum`
and plot `beg` become `source_date`; address `aufn_dt` becomes `address_date`.
These are ordinary attributes. Unavailable enrichment attributes remain typed NULL.

```sql
BEGIN;
CALL curation.curate_berlin_20261101(
  snapshot_at => TIMESTAMPTZ '2026-11-02 12:00:00+00',
  region => NULL,
  git_revision => NULL);
COMMIT;
SELECT * FROM curation.dataset_build;
SELECT * FROM curation.berlin_building;
SELECT * FROM curation.berlin_relation_building_plot;
```

Choose an actual compatible snapshot after the required source acceptances.
The fixed default is `2026-11-01 00:00:00+00`; it never advances to latest data.
New imports require an explicit override. A NULL region selects the whole registered
scope; a supplied geometry must use the source CRS, without automatic conversion.
Intersecting geometries are retained whole, including those crossing the boundary.
Missing required accepted inputs or recipe columns fail the build clearly.

The public procedure calls six entity procedures to prepare indexed temporary tables,
then a relationship procedure over those curated tables. These internal steps run
with the same snapshot/region and have no pipeline execution grants. The complete
replacement and `dataset_build` row commit together; failed preparation or installation
preserves the previous dataset. Concurrent builds serialize through an advisory lock;
an exclusive registry lock prevents source publication during input selection.

Relationship tables preserve all n:m matches. Intersection area is divided by the
first endpoint's area (building for building/block and building/plot, plot for
plot/block), rounded to three decimals and retained only above 0.02. Spatial indexes
narrow candidates before intersection calculation. There are no historical endpoint
combinations or independently versioned relationships.

`dataset_build` is system-maintained and has one current successful row per dataset:
recipe, caller-supplied Git revision (NULL if unknown), actual mirror snapshot, region
and completion time. It is not an execution log or per-record lineage catalogue.
Keep SQL revisions and compatible source history to reconstruct results. A failed
call reports its SQL error and leaves the prior successful build identity intact.

## Persistence

`uttdb/data/` holds PostgreSQL state; `uttdb/source-files/` holds original datasets.
Both are ignored by Git and need separate backups. Keep dataset sidecars together,
finish uploads before importing, and allow the PostgreSQL container user to read
files and traverse directories on Linux.

Init SQL runs only for a fresh database directory. Editing it does not migrate an
existing database. Stop the stack before deleting `uttdb/data/`; deletion resets
UTTDB on next startup. Preserve `uttdb/source-files/` independently.

Rollback-only mirror checks are in [tests/mirror.sql](../tests/mirror.sql).
Run them against a disposable freshly initialized database with
`psql -X -v ON_ERROR_STOP=1 -f tests/mirror.sql`. Native-file and OGR checks in
[tests/mirror-files.sql](../tests/mirror-files.sql) describe their small ignored
fixtures. They require the same `/source-files` mount as the database.

Snapshot checks are [tests/curation-berlin.sql](../tests/curation-berlin.sql): six
transformations, reproducible rebuilds, timestamp overrides, historical schemas,
n:m relations, privilege boundaries and failed installation rollback.
[source-columns.sql](../tests/source-columns.sql) independently checks schema reuse.
[spatial-relations.sql](../tests/spatial-relations.sql) checks fractions, empty and
zero-area geometries, pair uniqueness, reruns and a 3,000-row spatial-index plan.
All checks run against a disposable database and roll back their data. Remove the
generated native-file fixtures after testing.

For a core-only initialization check, load files `901`–`903` and run
[core-independence.sql](../tests/core-independence.sql) before loading `913-curation.sql`.
The core check requires the upstream `citydb` namespace and installed extensions,
but no project curation objects.

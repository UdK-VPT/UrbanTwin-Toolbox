# UTTDB

UTTDB uses 3DCityDB v5 on PostgreSQL/PostGIS. The [database image](../custom-db-docker-image/Dockerfile)
provides `ogr_fdw`, `postgres_fdw`, `http` and PostGIS Raster.
Configure credentials, port and coordinate system in `.env` before first startup.
Image versions and build settings live in `compose.yml`.

## Schemas and access

| Schema | Purpose |
| --- | --- |
| `citydb` | 3DCityDB's 3D city model |
| `mirror` | Source registry, import/schema evidence and accepted source history |
| `utt` | Curated domain versions, mappings, selected provenance and spatial relations |
| `utt_pkg` | SQL ingestion, curation and inspection routines |

[Initialization SQL](../uttdb/init/) creates schemas, extensions and NOLOGIN group
roles: `uttdb_dba`, `uttdb_reader`, `uttdb_developer`, `uttdb_pipeline`,
`uttdb_app_reader` and `uttdb_app_writer`. Give individual logins appropriate group
membership. Developers use sandbox schemas, provisioned by a DBA with
`SELECT utt_pkg.create_developer_sandbox('existing_login');`.
Routine comments in pgAdmin document usage and permissions.

[912-utt-buildings.sql](../uttdb/init/912-utt-buildings.sql) creates empty city,
district, block, plot, building and address tables. Each uses immutable `row_id`,
repeatable logical IDs and `utt_txn` system-time history. Source dates remain
ordinary attributes. Everyday readers use `utt.<entity>_current`;
`utt_pkg.<entity>_at(timestamp)` reads earlier versions. Pipeline roles invoke
curation routines and have no direct domain or provenance writes.

The three relation tables—`utt.relation_bldg_block`, `utt.relation_bldg_plot` and
`utt.relation_plot_block`—connect immutable endpoint versions. Their temporal
context comes from the endpoints rather than independent time ranges. There is no
curated postcode entity or postcode relation table. The tables hold all versions; their ordinary read-only views select current versions
without copying data and reflect committed changes automatically. The
[database reference](database-reference.md) lists every table/view pair and its
maintenance responsibility. See the [metadata model](metadata-modelling.md) for
versioning and selection behavior and the [glossary](glossary.md) for terminology.

Every geometry column has a GiST index, including `block.centroid`. The version-aware
relation tables use `row_id` foreign keys. Stable IDs retained as attributes elsewhere
are not foreign keys because their temporal targets can contain multiple versions of
one logical object. Unknown relationships may remain NULL.
`building.source_fid` is a technical source key rather than a stable relationship
target; logical relationship attributes use official identifiers.
Identifiers without a corresponding UTT table remain unconstrained.

## Mirror workflow

Run registration, staging and acceptance as a DBA. Registration records a dataset
in `mirror.registry`; it does not accept its contents. Row-based WFS/vector/GeoTIFF
sources use registry-controlled names: `<base>_source` is the read-only adapter,
`<base>_staging` is the pending cache, `<base>_stored` holds accepted history, and
`<base>` is a read-only current view. Registration generates readable source/layer bases without hashes. Empty,
overlength or colliding names are rejected rather than silently shortened or suffixed.
Inspect the registry for actual names; use shorter, distinct source names if needed.

```sql
SELECT * FROM utt_pkg.mirror_register_wfs_source(
  'berlin_alkis', 'https://gdi.berlin.de/services/wfs/alkis');
UPDATE mirror.registry SET stable_key = ARRAY['name']
WHERE source_name = 'berlin_alkis' AND layer_name = 'alkis:bezirk';
SELECT utt_pkg.mirror_store_layer('berlin_alkis', 'alkis:bezirk');
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
SELECT * FROM utt_pkg.mirror_register_file_source(
  'buildings', '/source-files/buildings.gpkg');
-- Inspect discovered layers, then configure stable_key before storing them.
SELECT * FROM utt_pkg.mirror_register_file_source(
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
SELECT utt_pkg.mirror_store_layer('berlin_alkis', 'alkis:bezirk', review => true);
SELECT import_id, registry_row_id, status, staging_table,
       validation_errors, threshold_failures
FROM mirror.import WHERE status = 'staged';
-- Inspect the indicated mirror staging table, then choose one:
SELECT utt_pkg.mirror_accept_layer('berlin_alkis', 'alkis:bezirk');
-- SELECT utt_pkg.mirror_reject_layer('berlin_alkis', 'alkis:bezirk');
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
not automatically retire curated entities.

Partial/delta ingestion is unsupported. Registered `coverage` describes the dataset
scope and is captured per import, along with source location; it cannot be overridden
per attempt. Changing an accepted dataset's scope requires a distinct registration.
`source_owner` retains supplied published wording and otherwise stays NULL.
Retirement via `mirror_unregister_source()` stops refresh while preserving registry,
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
SELECT utt_pkg.mirror_register_external_file(
  'climate', 'temperature', '/source-files/climate/temperature-v1.nc', 'NetCDF');
SELECT utt_pkg.mirror_store_layer('climate', 'temperature');
-- Stage a replacement without changing the accepted registry row:
SELECT utt_pkg.mirror_store_layer('climate', 'temperature', review => true,
  file_path => '/source-files/climate/temperature-v2.nc');
SELECT utt_pkg.mirror_accept_layer('climate', 'temperature');
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
its precise algorithm is documented on `mirror_file_evidence()`. It is not a normal
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
CALL utt_pkg.mirror_update_registered_sources();
CALL utt_pkg.mirror_update_registered_sources(review => true, skip_interval => NULL);
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

[example/berlin.sql](../example/berlin.sql) registers the public Berlin WFS sources,
configures six stable keys, accepts their data and runs all six domain routines and
three relation types. Curation resolves current mirror views through the registry,
so retained source history is never mistaken for duplicate current source records.

## Domain mappings and curation

Define mappings after accepting source history. The Berlin example installs one
initial mapping per entity using the versioned `berlin_<entity>_v1` rules. These
retain the existing ID conversions, boolean conversion, representative block point
and source geometry. Block/plot `source_date` and address `address_date` retain
source dates as ordinary state. The building rule includes `source_fid` as state;
changes to any mapped attribute create a version. Extra enrichment attributes stay
NULL until explicitly mapped.

For another source exposing an official city ID, a geometry and a name, a direct
mapping can be configured with ordinary SQL:

```sql
INSERT INTO utt.curation_mapping (
  registry_row_id, target_entity, target_columns, source_columns,
  source_id_column, rule_name, priority
)
SELECT row_id, 'city', ARRAY['geom','name'], ARRAY['geom','namlan'],
       'lan', 'direct_city_v1', 100
FROM mirror.registry
WHERE source_name = 'berlin_alkis' AND layer_name = 'alkis:land';
SELECT utt_pkg.curate_city();
```

Direct rules pair source/target columns by position; group sets are normalized while
preserving pairing. Matching IDs must have the same documented domain meaning;
column casts do not establish that equivalence. Each active group must be disjoint
from, or exactly match, other groups for that entity. Never map generated identity
or system-time columns. Lower priorities win, followed by mapping ID and source key.
Different groups may have different sources. Direct rules require all group members
to be non-NULL; the concrete Berlin rules allow nullable descriptive attributes.
`sum_<entity>_v1` rules aggregate numeric group members by `source_id_column` and
record every contributing source row. Verify units and matching assumptions before
activating a mapping; metadata cannot supply executable transformation SQL.

Only `active` may be updated. Change a source, priority, rule or column group by
inserting a new revision; deactivate the former revision in the same transaction.
Change group boundaries by deactivating former mappings and installing replacements
in one transaction, then re-curate. Eligible replacements must cover all columns in
every affected former group. Incomplete replacement is rejected.
Referenced definitions and provenance remain available after deactivation.

Run entity routines explicitly, then calculate the three relation types:

```sql
SELECT utt_pkg.curate_city();
SELECT utt_pkg.curate_district();
SELECT utt_pkg.curate_block();
SELECT utt_pkg.curate_plot();
SELECT utt_pkg.curate_building();
SELECT utt_pkg.curate_address();
SELECT utt_pkg.curate_relation('building_block');
SELECT utt_pkg.curate_relation('building_plot');
SELECT utt_pkg.curate_relation('plot_block');
```

Relation calls return the number of inserted pairs and leave existing pairs
untouched, including on historical backfill. Their fraction is intersection area
divided by the first entity's area (building for the first two relations, plot for
the third), rounded to three decimals and retained only above 0.02.

Each entity call returns its inserted-version count. Unchanged output returns 0,
including when changed selected origins require new provenance observations. If
all candidates are ineligible, existing content and origins remain in place.
Source withdrawal and retirement do not automatically retire domain entities.
Curation serializes mapping/domain changes and temporarily blocks mirror publication
with a coarse table lock; keep manual transactions around curation short.

### Inspecting selected origins

```sql
SELECT * FROM utt.building_current;
SELECT * FROM utt_pkg.building_at(TIMESTAMPTZ '2026-10-28 12:00:00+00');
SELECT p.*, m.target_columns, m.rule_name
FROM utt_pkg.provenance_at('building', clock_timestamp()) p
JOIN utt.curation_mapping m USING (mapping_id);
SELECT * FROM utt.relation_bldg_plot_current;
SELECT * FROM utt_pkg.relation_at(
  'building_plot', TIMESTAMPTZ '2026-10-28 12:00:00+00');
```

Provenance identifies its output with `target_table regclass` (for example
`'utt.building'::regclass`) and `target_row_id`, without entity-specific columns.
The target reference is validated by a trigger rather than a target foreign key.
To inspect all recorded observations for one version:

```sql
SELECT * FROM utt.curation_provenance
WHERE target_table = 'utt.building'::regclass AND target_row_id = 1;
```

Use the as-of function for the selected contributor set at a particular time; the
physical provenance table includes superseded observations. Contributors can be
multiple rows per group, so joining them directly to entities can multiply counts
or areas. The [metadata model](metadata-modelling.md#curation-and-selected-origins)
explains replacement observations, carried origins and reference integrity.
Native payload curation needs an approved reader; direct mappings can use registered
file metadata without parsing the payload.

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

Domain checks are [tests/curation.sql](../tests/curation.sql) (selection/provenance),
[tests/curation-berlin.sql](../tests/curation-berlin.sql) (six concrete rules and
historical relations), and [tests/curation-files.sql](../tests/curation-files.sql)
(native-file metadata origins). Run them with `psql -X -v ON_ERROR_STOP=1 -f ...`
against a disposable initialized database. The file checks use the same generated
fixtures as the mirror file checks. All SQL checks roll back their test data.

[source-columns.sql](../tests/source-columns.sql) checks distinct structure reuse,
returning to an older structure, curation provenance and renamed reader permissions.

# UTTDB

UTTDB uses 3DCityDB v5 on PostgreSQL/PostGIS. The [database image](../custom-db-docker-image/Dockerfile)
adds `ogr_fdw` and `http`; the upstream image supplies `postgres_fdw`.
Configure credentials, port and coordinate system in `.env` before first startup.
Image versions and build settings live in `compose.yml`.

## Schemas and access

| Schema | Purpose |
| --- | --- |
| `citydb` | 3DCityDB's 3D city model |
| `mirror` | Registered GIS sources and their local copies |
| `utt` | Temporally curated project data and derived spatial relations |
| `utt_pkg` | Project functions and procedures |

[Initialization SQL](../uttdb/init/) creates schemas, extensions and NOLOGIN group
roles: `uttdb_dba`, `uttdb_reader`, `uttdb_developer`, `uttdb_pipeline`,
`uttdb_app_reader` and `uttdb_app_writer`. Give individual logins appropriate group
membership. Developers use sandbox schemas, provisioned by a DBA with
`SELECT utt_pkg.create_developer_sandbox('existing_login');`.
Routine comments in pgAdmin document usage and permissions.

[912-utt-buildings.sql](../uttdb/init/912-utt-buildings.sql) creates empty `utt.address`,
`utt.block`, `utt.building`, `utt.city`, `utt.district` and `utt.plot`
tables on fresh initialization. These adapt selected EnergyMap structures to the
UTT temporal model while retaining applicable columns, comments and indexes.
Source data and EnergyMap processing routines are not imported. For inspection:
`SELECT * FROM utt.building LIMIT 10;`.

`utt.city`, `utt.district`, `utt.block`, `utt.plot`, `utt.building` and `utt.address`
implement the current temporal model with an immutable `row_id`, a reusable source
identifier, optional `source_valid`, mandatory `utt_txn`, and non-overlap constraints
on both time axes. See [Temporal curation](temporal-model.md) for the shared model
and update decision.

The city table keeps only the curated state used today: `id`, `name` and `geom`,
plus its temporal and internal identity columns. Unused legacy fields without a
defined curation mapping are not retained.

The same init file creates `utt.relation_bldg_block`, `utt.relation_bldg_plot` and
`utt.relation_plot_block`. Each references the immutable `row_id` values of its two
endpoint versions and stores their relative intersection. They have no independent
time ranges: the endpoint versions provide their temporal context. The former
`mostly_in_*` columns are not retained; callers can select the relation with the
largest intersection when they need that result. Postcode relation tables are not
present because there is no curated postcode entity.

Every geometry column has a GiST index, including `block.centroid`. The version-aware
relation tables use `row_id` foreign keys. Stable IDs retained as attributes elsewhere
are not foreign keys because their temporal targets can contain multiple versions of
one logical object. Unknown relationships may remain NULL.
The legacy `address.bldg_fid` remains unconstrained because `building.fid` is a
technical source key rather than a stable relationship target.
Identifiers without a corresponding UTT table remain unconstrained.

Calculate one relation type at a time after curating its endpoints:

```sql
SELECT utt_pkg.curate_relation('building_block');
SELECT utt_pkg.curate_relation('building_plot');
SELECT utt_pkg.curate_relation('plot_block');
```

The fraction is intersection area divided by the first entity's area—building for
the first two relations and plot for the third—rounded to three decimals. Fractions
at or below 0.02 are omitted. The function processes current endpoint versions and
leaves existing pairs untouched, so reruns add only relations involving newly
curated versions. It returns the number of inserted pairs.

## Mirror workflow

Run these examples as DBA. Registration discovers layers and creates read-only
foreign tables (or GeoTIFF source views) plus `mirror.registry` entries; it does
not persist source data.

`mirror.registry.extent` holds each layer's bounding geometry in EPSG:4326, with
a GiST index for spatial discovery. WFS registration reads advertised geographic
bounds without downloading features; file registration scans geometries or raster
tile footprints. Publication recalculates the extent from the accepted data in
the same transaction. Pending review candidates do not change it. Empty/nonspatial
data, missing advertised bounds or unknown SRIDs leave it NULL; raster bounds
include NoData cells. This is a bounding box, not an exact coverage footprint.

```sql
SELECT source_name, layer_name
FROM mirror.registry
WHERE public.ST_Intersects(extent, public.ST_MakeEnvelope(13.0, 52.3, 13.8, 52.7, 4326));
```

```sql
SELECT * FROM utt_pkg.mirror_register_wfs_source(
  'berlin_alkis', 'https://gdi.berlin.de/services/wfs/alkis'
);
SELECT utt_pkg.mirror_store_layer('berlin_alkis', 'alkis:bezirk');
```

Local vector files go in `uttdb/source-files/`, mounted read-only at `/source-files`:

```sql
SELECT * FROM utt_pkg.mirror_register_file_source(
  'buildings', '/source-files/buildings.gpkg'
);
```

Self-contained GeoTIFFs use the same workflow. Registration recognizes `.tif` or
`.tiff` (or explicit `driver => 'GTiff'`), validates the raster, and creates a
DBA-only source view. The layer name is the filename; the table base is the source
name, limited to 56 bytes. Vector GeoPackages retain their existing OGR workflow;
raster GeoPackages and raster subdataset discovery are not supported yet.

```sql
SELECT * FROM utt_pkg.mirror_register_file_source(
  'heat', '/source-files/q_total_RM_Paper.tif'
);
SELECT utt_pkg.mirror_store_layer('heat', 'q_total_RM_Paper.tif');
SELECT rid, public.ST_Metadata(rast) FROM mirror.heat_stored LIMIT 5;
```

PostGIS Raster is enabled during initialization. A narrowly granted
`utt_pkg.mirror_read_geotiff` security-definer helper reads trusted `/source-files`
paths, locally enables the GTiff decoder, and returns tiles up to 256×256 pixels.
All bands, NoData values and georeferencing are retained; edge tiles are unpadded.
Stored tables contain `rid` and `rast`, a tile primary key, and a GiST footprint
index. Their pixels are **inside PostgreSQL**: only registration/source-view reads
and refresh need the original file. Reads of `_stored` do not.

This minimal loader reads and decodes the whole file in database backend memory
before tiling. Files larger than 256 MiB are rejected; decoded pixel data must also
fit available memory, so compressed size is not a memory estimate. Use smaller
sources for now. GeoTIFFs must include their georeferencing internally; sidecar
files and raster open options are not supported. The helper owner needs server-file
read permission (the initialization administrator has it); callers need only the
DBA role. Keep source files and any symlinks under trusted DBA administration.

Refresh registered WFS/file layers with a standalone call and autocommit enabled:

```sql
CALL utt_pkg.mirror_update_registered_sources();
```

The batch skips imports less than one hour old and commits each completed layer.
Use `skip_interval => NULL` to refresh regardless of age. A failure stops the batch
but preserves earlier commits. Refresh does not discover new layers.

The registry keeps three distinct timestamps together: `registered_at` for local
registration, `last_imported_at` for successful publication, and `source_revision_at`
for the latest dataset revision ("Stand") reported by the source. WFS registration
follows each layer's first linked MetadataURL and reads the ISO 19139 dataset
citation's `revision` date. Shared URLs are fetched once per source check. Creation,
publication, metadata-record and thesaurus dates are not used as substitutes.
Date-only revisions become midnight UTC; absent links, unsupported metadata or
missing revision dates produce NULL. File registration leaves this field NULL.

Batch refresh checks WFS revision metadata even when feature imports are skipped,
without advancing `last_imported_at`. HTTP/XML/date parsing failures stop the call.
The revision therefore describes the latest checked source, and can be newer than
the stored copy; it is not proof of feature validity or a timestamp of the stored
snapshot. Direct layer storage/acceptance does not fetch metadata. Curation must
choose explicitly whether an advertised dataset revision is a suitable valid-time
approximation for the data being curated.

Storage first creates a `_review` candidate. Automatic publication checks row and
per-column NULL counts against the previous copy (within 1%; no baseline on first
import). These checks are heuristics, not completeness guarantees. Publication
preserves `_stored` table identity, maintains geometry indexes and advances
`last_imported_at` atomically. Schema changes require explicit migration.

For rasters, automatic publication also requires unchanged tile grids (including
extent, resolution, rotation and SRID), band counts, pixel types and NoData values.
Per-band valid-pixel counts must remain within 1%; zero must stay zero. These checks
do not assess the meaning or accuracy of pixel values. Changed grids or larger
count differences require `review => true` followed by explicit acceptance, using
the same functions shown below. Acceptance requires nonempty in-database tiles.

For manual review:

```sql
SELECT utt_pkg.mirror_store_layer('berlin_alkis', 'alkis:bezirk', review => true);
-- Inspect mirror."alkis:bezirk_review", then explicitly approve:
SELECT utt_pkg.mirror_accept_layer('berlin_alkis', 'alkis:bezirk');
```

Existing candidates block another import until accepted or explicitly removed.
`utt_pkg.mirror_unregister_source('source_name')` removes a source's managed tables
and registry entries, but keeps original files; dependencies block removal.

[example/berlin.sql](../example/berlin.sql) registers the Berlin WFS and local-file
sources, stores the land, district, block, plot, building and address layers used by
curation, then runs their six curation routines. It requires the local files named in the script.

## Initial city curation

After storing `alkis:land`, curate Berlin from the accepted local copy:

```sql
SELECT utt_pkg.curate_city();
```

The layer supplies `lan` (11), `namlan` (Berlin) and geometry, but no feature-level
validity timestamp. The routine therefore reads `source_revision_at` from the exact
`berlin_alkis` / `alkis:land` registry entry and refuses to curate when no finite
source revision is available. Callers cannot provide a substitute date. The source
revision starts `source_valid`; database insertion starts `utt_txn`, and both
ranges remain open-ended. The registry revision is source metadata and can be newer
than the stored snapshot when a source check was committed without an import.

The routine fills `utt.city.id`, `name`, `geom`, `source_valid` and `utt_txn`;
PostgreSQL assigns an immutable `row_id`. It compares name and geometry before
versioning. A newer advertised revision with unchanged content returns 0 and leaves
the existing source-valid range untouched. When content changed, the routine closes
the current `utt_txn` at the database change time and inserts a new version. If the
revision is newer, it also closes the current `source_valid` at that revision; if the
revision is unchanged, both system-time versions retain the same source-valid range.
The old and new range boundaries are identical where a range is closed. An initial
insert or content change returns 1; changed content with an older revision raises an
error.
The routine is available to DBA/pipeline roles and requires exactly one source row.
Its definition initializes without registered sources.

## Initial building curation

After storing `alkis_gebaeude:gebaeude`, curate Berlin ALKIS buildings from the
accepted local copy:

```sql
SELECT utt_pkg.curate_building();
```

The routine uses ALKIS `uuid` as the stable building ID and retains `fid` as a
technical source value. It copies geometry and the directly corresponding ALKIS
descriptive fields through `bezeich`; an empty `hoh` remains NULL. The layer has no
feature-level validity date, so its exact registry `source_revision_at` opens
`source_valid`. Geometry or mapped descriptive changes create versions. A registry
revision or technical `fid` change alone does not. Missing buildings are not closed
or deleted automatically. This routine does not populate classification, heritage,
height or energy fields.

## Initial district curation

After storing `alkis:bezirk`, curate the twelve Berlin districts from the accepted
local copy:

```sql
SELECT utt_pkg.curate_district();
```

The routine maps the numeric long identifier in source `name` to `dist_id`, `namgem`
to the district name, and preserves geometry in its source CRS. It applies the same
content comparison, source-valid inference and transaction-time versioning rules as
city curation. A revision-only change creates no versions. The result is the number
of inserted versions; an unchanged rerun returns 0. Missing source districts are not
closed or deleted automatically.

Because temporal district versions repeat `dist_id`, unversioned columns such as
`address.district_id`, `block.in_district` and `plot.in_district` remain unconstrained until
their temporal relationship semantics are redesigned.

## Initial block curation

After storing `bloecke:rbs_bloecke`, curate Berlin statistical blocks from the
accepted local copy:

```sql
SELECT utt_pkg.curate_block();
```

The routine maps numeric `blknr` to `blk_id`, `plr` to `planning_area_no`, the
two-digit `bez` code to the long Berlin district ID, and preserves geometry. Unlike
the land and district layers, every block supplies a `datum`; midnight UTC on that
date starts its `source_valid` range. Geometry, planning-area or district changes
create versions. `centroid` is the geometric centroid when it lies in the block;
otherwise it is an interior point returned by `ST_PointOnSurface`. A changed date
without changed content creates no version. The
result is the number of inserted versions, and missing source blocks are not closed
or deleted automatically. Columns that refer to stable block IDs remain
unconstrained until their temporal relationship semantics are redesigned.

## Initial plot curation

After storing `alkis:flurstuecke`, curate Berlin cadastral plots from the accepted
local copy:

```sql
SELECT utt_pkg.curate_plot();
```

The routine removes trailing underscore padding from `fsko` and stores its numeric
portion as the stable plot ID. It copies geometry, parcel numerator `zae`, cadastral
district key `gmk`, field number `fln` and district key `gdz`; the feature's `beg`
date at midnight UTC opens `source_valid`. Geometry or mapped cadastral changes
create versions, while a changed `beg` alone does not. Missing source plots are not
closed or deleted automatically. This routine does not populate enrichment fields.

## Initial address curation

After storing `adressen_rbs:adressen_rbs`, curate Berlin RBS address records from the
accepted local copy:

```sql
SELECT utt_pkg.curate_address();
```

The routine uses numeric `adr_ident` values as stable IDs and maps the source address
and location fields directly. It expands `bez` to the long Berlin district ID and
keeps `str_typ` so streets, places and other RBS object types remain distinguishable.
`aufn_dt` at midnight UTC opens `source_valid`; a date-only change creates no version.
The RBS source does not provide `street_date`, `quality` or `hko_id`; those fields
remain NULL. The routine also leaves `bldg_fid`, `fsko`, `ens_id` and `bldg_uuid`
NULL. Missing source records are not closed or deleted automatically.

## Persistence

`uttdb/data/` holds PostgreSQL state; `uttdb/source-files/` holds original datasets.
Both are ignored by Git and need separate backups. Keep dataset sidecars together,
finish uploads before importing, and allow the PostgreSQL container user to read
files and traverse directories on Linux.

Init SQL runs only for a fresh database directory. Editing it does not migrate an
existing database. Stop the stack before deleting `uttdb/data/`; deletion resets
UTTDB on next startup. Preserve `uttdb/source-files/` independently.

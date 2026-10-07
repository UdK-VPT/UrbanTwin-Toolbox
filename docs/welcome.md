# UrbanTwin-Toolbox

UTT brings source GIS data into a self-owned PostgreSQL/PostGIS database alongside
3DCityDB. Keep data workflows readable and primarily in SQL,
so contributors can understand and develop the system together.

The current stack runs UTTDB and pgAdmin. WFS, local vector-file and GeoTIFF raster
mirroring, temporal curation for cities, districts, blocks, cadastral plots, buildings
and addresses, and version-aware spatial relation calculation.

- [Quick start](../README.md)
- [UTTDB](uttdb.md): schemas, source imports and storage
- [Temporal curation](temporal-model.md): versioning and update decisions
- [pgAdmin](pgadmin.md): database access
- [Architecture](architecture.md): current stack and data flow

Instance settings live in ignored `.env`, initialized from [`.env.example`](../.env.example).
Images, build settings and storage paths are defined in Compose.
The root [Compose file](../compose.yml) runs the entire stack on Windows or Linux.
Commands in these guides run from the repository root.

Contributions should favor small, explainable database changes. Describe proposed
structures before implementing them; distinguish fresh initialization from changes
to existing databases. Temporal curation follows the [shared temporal model](temporal-model.md),
and missing definitions must never imply deleting existing data.

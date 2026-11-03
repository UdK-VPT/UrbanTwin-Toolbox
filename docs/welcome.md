# UrbanTwin-Toolbox

UTT brings source GIS data into a self-owned PostgreSQL/PostGIS database alongside
3DCityDB. Registration and accepted source history work independently of optional
domain curation; the workflows run primarily in SQL.

The current stack runs UTTDB and pgAdmin. It mirrors WFS, local vector files and
GeoTIFF rasters with accepted source history, and versions native-file references
without converting their contents. Domain curation covers cities, districts,
blocks, cadastral plots, buildings and addresses, with spatial relations between
snapshot entity tables.

- [Quick start](../README.md)
- [UTTDB](uttdb.md): schemas, source imports and storage
- [Metadata model](metadata-modelling.md): source history and snapshot curation
- [Glossary](glossary.md): terminology used throughout the guides
- [Database reference](database-reference.md): workflow steps, objects and maintenance responsibilities
- [pgAdmin](pgadmin.md): database access
- [Architecture](architecture.md): current stack and data flow

Instance settings live in ignored `.env`, initialized from [`.env.example`](../.env.example).
Images, build settings and storage paths are defined in Compose.
The root [Compose file](../compose.yml) runs the entire stack on Windows or Linux.
Commands in these guides run from the repository root.

Initialization SQL applies to a fresh database; editing it does not update an
existing instance. Mirror history uses one system-time axis, recording accepted observations.
Curated tables are replaceable snapshots without temporal modelling. Source dates
remain ordinary attributes.
Contributor and agent implementation rules live in [AGENTS.md](../AGENTS.md).

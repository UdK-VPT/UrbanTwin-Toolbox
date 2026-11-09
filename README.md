# UrbanTwin Toolbox

UrbanTwin Toolbox (UTT) is a PostgreSQL-native foundation for urban digital twin
research and applications. It brings heterogeneous urban data into a self-owned
PostgreSQL/PostGIS database with consistent source management, accepted historical
states and SQL interfaces for research and application development.

Research projects often combine changing public GIS services, local datasets and
simulation results. UTT separates capturing those sources from interpreting them
for a particular project. Registration, review, acceptance and historical queries
follow a common workflow, making accepted observations understandable and reusable.
Researchers and partners should not have to operate a collection of specialized
tools merely to perform these common operations. A coherent database interface also
reduces the source-management work each application must implement independently.

UTT builds on PostgreSQL, PostGIS, 3DCityDB v5 and established foreign-data wrappers.
It does not replace their database, spatial or CityGML capabilities. Processing runs
primarily inside PostgreSQL to keep deployment small and research data under the
team's control. Transparent SQL, explicit metadata and replaceable project recipes
support long-term maintenance.

## Current capabilities and scope

The Compose stack runs UTTDB and pgAdmin. UTT registers WFS and local vector layers,
ingests accepted row history, tiles self-contained GeoTIFFs into PostGIS Raster,
and tracks native-file reference versions without converting their payloads.
It supports review thresholds, manual acceptance/rejection, source refresh,
retirement, individual administrator accounts and developer sandboxes.

Optional Berlin curation builds six entity tables and three spatial relationship
tables from one accepted mirror snapshot. It is a project-specific demonstration,
with regression checks and a reported successful full-scale run using Berlin data;
it is not a complete general-purpose urban data model. The repository remains a
research prototype. Existing checks do not establish compatibility with every WFS
service, GDAL format or deployment environment.

SQL and pgAdmin are the current administration interfaces. CityGML/3DCityDB is an interoperability component;
registered attributes need not all be copied into its model. Mirror stores observed
accepted history, not unobserved remote changes or real-world validity intervals.

## Quick start

Install Docker with Compose, copy `.env.example` to `.env`, and review credentials,
ports and CRS settings before first startup. Run from the repository root:

```sh
cp .env.example .env
docker compose up -d --build
docker compose logs -f uttdb
```

In PowerShell use `Copy-Item .env.example .env` for the copy step.
Open [pgAdmin](http://localhost:5050) on the default port and connect to UTTDB.
`docker compose down` stops the stack while preserving its bind-mounted data.
Initialization SQL runs only with a fresh database directory.

The [User Guide](docs/user-guide.md) takes you from installation through a complete
source workflow. [example/berlin.sql](example/berlin.sql) registers, imports and
curates public Berlin data; it downloads large datasets and can take substantial time.

## Documentation

- [User Guide](docs/user-guide.md): installation, accounts, mirror workflows, files and Berlin curation.
- [API Reference](docs/api-reference.md): public SQL contracts and internal routine inventory.
- [Architecture](docs/architecture.md): components, data model, privileges and maintenance boundaries.

Deferred proposals are in [BACKLOG.md](BACKLOG.md); contributor rules are in
[AGENTS.md](AGENTS.md). Database state, credentials and original datasets are not
versioned in Git and require appropriate separate backups.

## Future developments

- German administrations' NAS data format support
- CityGML ingestion pipeline with incremental update support
- OSM data ingestion
- Data provenance and lineage
- Generic and location-specific curation routines
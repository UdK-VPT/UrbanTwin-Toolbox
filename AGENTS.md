# UrbanTwin-Toolbox Project Briefing for agents

Read this file first when returning to the project. Keep all project, component and
documentation instructions here; do not create nested instruction files. Keep
development compatible with Windows and production/testing compatible with Linux.

## Response style

Keep final answers concise: normally 2–10 sentences or at most five short bullets.

## Direction and design priorities

UrbanTwin-Toolbox is a 3DCityDB v5-based urban digital twin centered on
PostgreSQL/PostGIS. The `mirror` and `utt` workflows should remain primarily inside
PostgreSQL so the team can understand, discuss and maintain them together.

- Prefer the smallest readable set of functions, tables and columns that preserves
  correctness and clear responsibilities. Add objects only for concrete current uses.
- Keep database structures understandable to contributors with PostgreSQL basics.
  Use clear names, concise comments and a few worked SQL examples. Do not hide
  complexity in opaque JSON, overloaded columns or oversized routines.
- Prefer PostgreSQL, PostGIS, constraints, views and suitable extensions over external
  workers. Add an external component only for a demonstrated database/extension gap,
  and keep it small and explainable.
- Use at most valid time and system time for bitemporal entities unless a documented
  domain requirement proves another temporal axis is necessary. Avoid redundant
  timestamps and do not impose bitemporality on data that does not need it.
- Existing interfaces describe the current implementation. Check their callers before
  replacement or removal, and use explicit migrations for live data changes.

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
  `docs/temporal-model.md`, `docs/pgadmin.md` and `docs/architecture.md`.
  `welcome.md` links the guides; the root README contains the Compose quick start.
- Use standard Markdown, relative links and Mermaid for architecture diagrams.
- Document current implementation. Keep roadmaps and speculative functionality out
  of the implementation guides.
- Prefer readable structures and a few practical SQL examples. Keep detailed
  interfaces in SQL comments instead of duplicating them throughout the guides.
- Use valid time and system time consistently when describing temporal history.
- Documentation commands run from the repository root unless stated otherwise.

## Database rules

- Put UTTDB cross-schema routines in `utt_pkg`. Prefix mirror routines `mirror_` and
  curation routines `curate_`.
- Add a PostgreSQL `COMMENT` to every UTT-owned function or procedure. State its
  purpose, caller, effects, result and a practical SQL example. A trigger-function
  example must show the operation that fires it.
- Use NOLOGIN group roles as the stable privilege surface. Give developers sandbox
  schemas instead of broad curated-schema write access.
- Add routines only for concrete integrity, privilege, transaction or reuse
  boundaries; prefer direct SQL, constraints and privileges when sufficient.
- Preserve published source metadata in its original language and wording. Leave
  absent values `NULL`; do not infer license rights. Registry `fees` and
  `access_constraints` retain service-level statements verbatim.
- Curated writes require explicit curation/diff workflows. Preserve narrow write
  privileges until a replacement boundary is designed.
- Keep changes small and independently usable. Document practical calls in
  [docs/uttdb.md](docs/uttdb.md) and routine comments.
- Use rollback-only database checks where practical. Distinguish repository changes
  from changes applied to a running database. Do not add migration files during the
  current preparation phase unless explicitly requested.

## Temporal curation rules

These rules are normative for current and future temporal `curate_*` routines. See
[docs/temporal-model.md](docs/temporal-model.md) for the explanatory guide.

- Each stored version has an immutable identity `row_id`, a repeatable stable source
  ID, optional `source_valid tstzrange`, and mandatory `utt_txn tstzrange`.
- Use half-open `[start, end)` ranges. Unknown source validity remains `NULL`; never
  substitute ingestion or transaction time unless a source-specific rule explicitly
  defines that approximation.
- For one stable ID, `utt_txn` ranges must not overlap. Also prevent overlapping
  `source_valid` ranges while their `utt_txn` ranges overlap. Enforce both invariants
  with GiST exclusion constraints.
- Curation is idempotent and content-based. Compare geometry and every curated state
  attribute with the current version. A source revision or validity-date change alone
  is a no-op and does not replace the current `source_valid`.
- A content change creates a new version. Use one database timestamp to close the old
  `utt_txn` and open the new one. Never overwrite the historical row.
- If changed content has a newer source-valid opening, close the former
  `source_valid` there and open the new version there. If the opening is unchanged,
  copy the same source-valid range to the new system-time version. Reject changed
  content carrying an older source-valid opening.
- Missing source objects are not deletions unless a source-specific routine defines
  and documents deletion semantics.
- A deterministic content hash may replace direct comparison, but it must cover all
  curated state and exclude UTT-generated metadata such as `row_id` and `utt_txn`.

## Current implementation

- `901-setup-structures.sql` creates `mirror`, `utt` and `utt_pkg`, enables required
  extensions, and removes optional PostGIS Tiger/topology extensions.
- `902-create-privilege-roles.sql` defines group roles and developer sandboxes.
- `903-mirror-setup.sql` implements the registry and WFS/local-file registration,
  review, acceptance, refresh and removal workflow. Accepted `_stored` tables contain
  the current mirror snapshot. It supports vector sources and self-contained GeoTIFFs,
  registry extents, source revision metadata and automatic review checks.
- `912-utt-buildings.sql` defines temporal `utt.city`, `district`, `block`, `plot`,
  `building` and `address` tables. All use `row_id`, a stable source ID,
  `source_valid`, `utt_txn` and exclusion constraints. Stable IDs kept as attributes
  are not foreign keys because logical objects may have multiple temporal versions.
- The same file defines `relation_bldg_block`, `relation_bldg_plot` and
  `relation_plot_block`. They reference immutable endpoint `row_id` values, store a
  relative intersection, and derive temporal context from endpoint versions. There is
  no curated postcode entity or postcode relation table.
- `913-curation.sql` defines content-based curation for all six entities. City,
  district and building use registry `source_revision_at`; block uses source `datum`;
  plot uses `beg`; address uses `aufn_dt`. `curate_relation(text)` calculates the
  three supported current-version spatial relations and omits intersections at or
  below 2%.
- [example/berlin.sql](example/berlin.sql) registers the Berlin sources, stores the
  six required layers, runs all six curation routines and calculates the three
  relation types.

## Local command

Copy `.env.example` to `.env`, review it, then run from the repository root:

```sh
docker compose --env-file .env up -d --build
```

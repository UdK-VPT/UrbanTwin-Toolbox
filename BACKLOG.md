# Backlog

Deferred low-priority fixes, small features and behavior changes. These are open
proposals, not descriptions of current behavior or instructions to implement them.
[AGENTS.md](AGENTS.md) remains authoritative for implementation.

Keep each item short: **kind**, **issue**, **next step** and **done when**. Add relevant
file links where useful. Put more pressing items first. Remove resolved items once
the resulting behavior and lasting decisions are documented in their proper places.

## Open items

### Source-to-output provenance

- **Kind:** Feature / scope decision.
- **Issue:** `curation.dataset_build` identifies the recipe and input snapshot, but
  does not explicitly record which sources contributed to which output tables or rows.
- **Next step:** Decide whether table-level traceability is sufficient or row-level
  provenance is needed; then define the smallest useful change. Keep
  `mirror.source_columns` in mirror as source-schema evidence.
- **Done when:** The intended granularity and concrete use are agreed; any resulting
  implementation is separately scoped. No provenance framework is implied.

### Curation transaction granularity

- **Kind:** Behavior / design review.
- **Issue:** The umbrella procedure installs all six entities, three relationship
  tables and build identity in one transaction. Smaller committed steps may be
  useful, but must account for consistency between cooperating tables.
- **Next step:** Review the tradeoff before changing the current atomic build.
- **Done when:** The desired commit boundary and behavior after a failed step are
  explicit, including how mixed snapshots would be prevented or identified.

### Schema-aware mirror row comparison

- **Kind:** Performance / behavior change.
- **Issue:** In `mirror.accept_layer()`, `schema_changed_imports` forces new
  `utt_txn` versions when `structure_version` changes, even for unchanged values.
- **Next step:** Optimize schema-aware comparison in
  [903-mirror-setup.sql](uttdb/init/903-mirror-setup.sql) so only actual value changes
  create row versions. Review native geometry/raster comparison behavior and how
  unchanged rows retain correct historical import/schema lineage.
- **Done when:** Tests cover added columns with all, some or no non-NULL values,
  removed columns, reordered columns and historical import/schema lineage. Existing
  history and current-view semantics remain intact, including the distinction
  between historically absent columns and supplied NULL values.

### ALKIS NAS source support

- **Kind:** Source-adapter feature. **Priority:** Later, after current mirror testing.
- **Issue:** Standardized NAS (Normbasierte Austauschschnittstelle) could provide
  original ALKIS data across German federal states, including attributes and object
  relationships absent from regional WFS services, such as ownership classifications.
- **Next step:** Investigate GDAL's NAS driver through `ogr_fdw`, reusing registration,
  foreign tables, staging, validation, acceptance and versioned mirror storage. Treat
  a complete, potentially multi-file delivery as one logical source and assemble
  per-class datasets such as `AX_Gebaeude` and `AX_Flurstueck`; investigate OGR VRT
  for aggregation. Preserve stable ALKIS identifiers, relationships and original
  attributes. Reuse `utt_txn`; source timestamps remain ordinary attributes. Establish
  delivery completeness before interpreting absent objects as withdrawals; count
  thresholds alone do not prove completeness.
- **Initial validation:** Check the server's GDAL NAS support and appropriate
  GeoInfoDok GFS template; inspect one XML file with `ogrinfo`, expose one object
  class through `ogr_fdw`, then exercise existing staging/validation/acceptance.
  Investigate multi-file partitioning, duplicate identities, schema consistency,
  performance and relationships. Compare attributes with Berlin WFS and the recovered
  ownership parser.
- **Done when:** A complete multi-file NAS delivery can be registered and ingested
  through generic mirror infrastructure, without a separate ALKIS database model or
  changes to core history semantics. Incremental NAS/NBA updates, proprietary import
  software and NAS-specific history are out of scope.

Reference material supplied for this investigation:

- Berlin NAS download: approximately 800 MB as 7z, containing one `A_...` file,
  one `P_...` file and 2,397 compressed `E_...xml.gz` files; partitioning remains
  to be investigated.
- Recovered `ownership_nas2emb.ipynb` (approximately 2024): ownership-classification
  extraction through `AX_Namensnummer` → `AX_Buchungsstelle` → `AX_Flurstueck`,
  followed by PostgreSQL processing. Use as a reference/validation case; prefer
  GDAL-based ingestion as its eventual replacement.
- [GDAL NAS driver](https://gdal.org/en/stable/drivers/vector/nas.html) and
  [norGIS ALKIS importer](https://github.com/norBIT/alkisimport).

### Preserve GeoTIFF NoData metadata

- **Kind:** Raster-ingestion fix.
- **Issue:** Reported GeoTIFF ingestion preserves pixel values but loses NoData
  metadata. NaN pixels then disrupt raster statistics and QGIS automatic display
  scaling.
- **Next step:** Investigate the GDAL/PostGIS conversion path and preserve per-band
  NoData metadata where available, including NaN handling, without changing valid
  pixels or inventing missing NoData declarations.
- **Done when:** Ingested NoData declarations, valid-pixel counts and raster statistics
  agree with the original GeoTIFF, with QGIS automatic visualization scaling verified.

### Raster grid identity and versioning

- **Kind:** Integrity / versioning behavior change.
- **Issue:** Generated raster tile IDs may refer to different geographic areas across
  imports; matching `rid` values alone does not establish stable tile identity.
- **Next step:** Validate grid origin, resolution, CRS, extent, tiling and band
  structure before per-tile comparison. Define compatible-grid matching explicitly;
  treat incompatible imports as whole-dataset revisions rather than matching tiles
  by `rid`. Coordinate this with existing grid-change review and acceptance safeguards.
- **Done when:** Tests cover compatible re-imports and incompatible grid layouts,
  including reused tile IDs at different locations. Whole-dataset replacement
  preserves historical raster interpretation, closes superseded tiles consistently
  and never equates tiles solely by generated ID.

### Review duplicate external-file checksums

- **Kind:** Acceptance behavior change.
- **Issue:** A newly registered external file can be accepted as a distinct file even
  when another tracked file has the same checksum.
- **Next step:** Check for another tracked file reference with the same checksum
  algorithm and checksum. Warn before acceptance and retain staging for explicit
  review instead of accepting automatically. Include the matching registration/path
  in the warning. Define whether historical references are included, and distinguish
  duplicates from ordinary unchanged re-imports of the same file reference.
- **Done when:** Duplicate-file evidence produces an inspectable warning and blocks
  automatic acceptance, while explicit manual acceptance remains possible and still
  enforces normal integrity checks. Test different registrations/paths with identical
  checksums, differing checksum algorithms, and unchanged same-reference re-imports.

### Shared file storage and lifecycle

- **Kind:** Storage / lifecycle design.
- **Issue:** Source files and module-generated outputs need consistent storage,
  access and retention across updates and deployments, with traceable processing.
- **Next step:** Design shared container storage with read-only database access and
  admin-managed uploads. Keep accepted files immutable at version-specific paths;
  register module-generated outputs explicitly as derived sources through the normal
  mirror workflow. Define upload completion, output handoff, retention, backups and
  deployment paths, coordinated with the deferred derived-source lineage design.
- **Done when:** Accepted historical files remain accessible across file updates and
  deployments; permissions enforce the intended write boundaries, and derived outputs
  retain links to their exact inputs and processing identity. Validate replacement,
  redeployment and recovery without overwriting accepted bytes or losing lineage.

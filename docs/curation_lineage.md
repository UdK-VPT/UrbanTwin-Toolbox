# UTT — Declarative Curation, Source Resolution and Data Lineage

## 1. Objective

Extend the Urban Twin Toolkit (UTT) with a metadata-driven curation and provenance system.

The system shall:

- Define relationships between registered source data and UTT data elements.
- Replace hardcoded source-to-target mappings with declarative definitions where practical.
- Resolve competing sources according to configurable priorities and eligibility rules.
- Support individual attributes and atomic groups of related attributes.
- Track provenance and lineage across curation, external simulations, analyses and result imports.
- Support multiple geographic regions within the same UTT instance.
- Preserve PostgreSQL/PostGIS performance, transparency and accessibility.

**Guiding principle:** Declarative relationships, efficient SQL execution, transparent provenance and minimal architectural complexity.

The UTT database shall remain understandable and explorable by researchers using ordinary PostgreSQL tools and QGIS.

## 2. Architectural constraints

### 2.1 PostgreSQL/PostGIS only

Implement all persistent metadata, provenance information and database-side execution logic in PostgreSQL/PostGIS.

Use:

- Relational tables for definitions and execution records.
- JSONB for limited, well-defined flexible configuration.
- PL/pgSQL for generic database-side orchestration.
- Generated set-based SQL for curation.
- PostGIS for spatial applicability and matching.
- SQL views/functions for human-readable inspection.

Do not introduce a separate metadata service, graph database, message broker or workflow engine.

Existing external FastAPI services and simulation tools may interact with the database through SQL functions.

### 2.2 Minimal metadata complexity

Prefer extending existing UTT structures over introducing additional tables or schemas.

Target a small model consisting of approximately four logical tables:

| Table | Responsibility |
|---|---|
| `mapping` | Source-to-target mappings, transformations, priorities and applicability |
| `operation` | Defined curation, simulation, analysis, import or export operations |
| `execution` | Individual executions, parameters, software versions and status |
| `lineage` | Relationships between executions, inputs, outputs and selected sources |

Reuse the existing mirror/source registry. Do not duplicate its source definitions, version metadata or geographic extents.

Additional tables are acceptable only where necessary for correctness, referential integrity, performance or a substantial improvement in clarity.

The suggested table names are conceptual. Follow existing UTT naming conventions and schemas.

### 2.3 Human-readable design

Definitions must be understandable without specialized framework knowledge.

Prefer descriptive columns, explicit relationships and conventional SQL.

Do not develop a new programming language inside JSONB metadata.

Expose inspectable SQL and comprehensible views for users unfamiliar with the internal implementation.

## 3. Field-level and atomic-group mappings

Mappings shall fundamentally describe relationships between **data elements**, not merely between tables.

Supported relationships should include:

- One source attribute to one target attribute.
- Multiple source attributes to one target attribute.
- One source attribute to multiple target attributes.
- Related attributes processed together as an atomic group.

Examples:

| Source | Transformation | Target |
|---|---|---|
| ALKiS geometry | CRS transformation | Building geometry |
| Roof and ground elevation | Difference | Building height |
| OSM construction date | Year extraction | Construction year |
| Building parameters | Group transformation | Thermal properties |

A mapping definition should specify:

- Registered source reference.
- Source element(s).
- UTT target element(s).
- Transformation identifier.
- Optional transformation parameters.
- Optional matching rule.
- Source priority.
- Optional eligibility conditions.
- Optional geographic applicability.
- Definition version and activation status.

Mappings must accommodate several source elements contributing to one target, without requiring a direct identifier relationship between source and target records.

Support identifier-based and spatial matching.

Do not assume that every source record matches exactly one UTT object.

Where necessary, specialized matching functions shall remain available.

## 4. Competing sources and resolution

A target attribute may have multiple candidate sources.

For example, UTT building construction year may be available from seven datasets, each with incomplete building coverage.

Each mapping produces eligible candidate values. The system selects values according to a defined resolution policy.

Initially implement **priority-based resolution**:

1. Collect candidate values from applicable mappings.
2. Exclude missing or invalid values.
3. Associate candidates with UTT target objects.
4. Resolve competing values by priority.
5. Apply deterministic tie-breaking.
6. Pass selected values to the existing temporal comparison/merge logic.

Priorities are **target-specific**, not global properties of a source.

The same source may have high priority for geometry but low priority for construction year.

Avoid seven consecutive updates where a single set-based candidate selection can achieve the same result.

Use conventional PostgreSQL techniques such as `UNION ALL`, window functions or `DISTINCT ON`.

Allow future extension to other resolution strategies, but do not implement a generalized strategy framework prematurely.

### Changes and fallback

If a higher-priority source gains a valid value, it shall replace a lower-priority value.

If a selected source loses its value, the system shall fall back to the next eligible source.

Updates to non-selected candidates shall not unnecessarily update curated target records.

Ensure that source disappearance, source refreshes and mapping changes can trigger appropriate re-evaluation.

Record the selected source and resolution definition for provenance.

## 5. Execution engine and performance

Implement a small, transparent PL/pgSQL execution layer.

Suggested conceptual interface:

```sql
SELECT utt.check_mapping(...);
SELECT utt.show_curation_sql(...);
SELECT utt.curate(...);
SELECT utt.explain_value(...);
```

Function names are provisional and should follow existing conventions.

### Execution approach

1. Read mapping definitions.
2. Validate source references, target types and applicability.
3. Compile mapping and resolution definitions into SQL.
4. Execute set-based PostgreSQL operations.
5. Compare selected values with existing UTT data.
6. Apply the established temporal update mechanism.
7. Record execution and provenance information.

Metadata interpretation shall happen per operation, **not per building or individual source record**.

Generated queries must remain inspectable and suitable for `EXPLAIN (ANALYZE, BUFFERS)`.

Use PostgreSQL indexes, spatial indexes and normal query optimization.

Avoid row-by-row PL/pgSQL processing of large datasets.

Compiled SQL may be cached or persisted if useful, but optimization and correctness take precedence over premature caching.

Generated SQL must use validated identifiers and safely bound values. Do not execute arbitrary SQL supplied through untrusted mapping metadata.

### Specialized functions

Retain ordinary SQL/PL/pgSQL functions where transformations are too complex for a simple declarative mapping.

A generic engine must not become more complicated than the operations it replaces.

Prefer a registry of approved transformations over arbitrary SQL expressions embedded in metadata.

## 6. Geographic applicability

UTT is geographically agnostic and may contain multiple regions.

No generic function shall assume Berlin, a particular German federal state, or any fixed administrative hierarchy.

Distinguish:

- **Source coverage:** Geographic extent registered with a dataset.
- **Mapping applicability:** Optional geographic limitations of a mapping.
- **Execution scope:** Geographic area requested for a specific operation.

Reuse geometry extents already recorded in the mirror registry.

Support arbitrary PostGIS geometries and optionally named regions.

### Validation

Before executing a mapping, compare its effective coverage with the requested region.

Return understandable validation results:

| Status | Meaning |
|---|---|
| Compatible | Source covers requested region |
| Partial | Source overlaps part of the region |
| Incompatible | Source and target region do not overlap |
| Unknown | Geographic applicability cannot be established |

Use PostGIS functions such as `ST_Intersects()` and `ST_Covers()` where appropriate.

Distinguish bounding-box extents from verified dataset coverage; an extent alone cannot guarantee complete coverage.

Incompatible mappings should normally be skipped with a clear explanation.

Partially overlapping mappings may execute within their valid spatial scope.

A geographic pre-check is not a substitute for building-level spatial matching.

Validate applicability at execution level without adding unnecessary per-record processing.

## 7. Temporal modelling

Preserve the existing UTT temporal architecture:

- Persistent logical object identifiers.
- `source_valid_time`, when available.
- `utt_txn_time`, maintained by UTT.
- Non-overlapping transaction-time versions.
- Comparison before inserting a new temporal version.

Do not redesign the existing primary-key or temporal-versioning approach as part of this work.

A new curated version shall only be created when required by the established update semantics.

Changes in source selection or provenance that do not change the target value must still be traceable without necessarily duplicating the curated value.

Lineage shall reference the actual target record version wherever version-level traceability is required.

## 8. Provenance and lineage

Lineage must extend beyond PostgreSQL curation.

UTT shall track transformations involving:

- Source ingestion and curation.
- Internal calculations.
- Data exports.
- External simulation and analysis tools.
- Result imports.
- Subsequent calculations using earlier results.

Use a minimal conceptual model inspired by W3C PROV:

- **Data artifacts:** Datasets, database records or versions, files, inputs and results.
- **Operations:** Defined processing steps.
- **Executions:** Individual runs of operations.
- **Lineage relationships:** Data consumed or produced by an execution.

Do not require an RDF store or graph database.

### Structural versus execution lineage

Distinguish:

**Structural lineage:** Defined relationships describing how source attributes can contribute to UTT attributes.

**Execution lineage:** Actual source versions, values, processing runs and outputs used or generated.

Structural lineage derives primarily from mapping definitions.

Execution lineage must be recorded when processing occurs.

### Provenance detail

Always retain enough information to identify:

- Input datasets and their versions.
- Mapping/operation definition versions.
- Execution identifier.
- Selected source where competing sources exist.
- Output dataset or record version.
- Software version and relevant parameters.

Avoid unbounded storage of every intermediate candidate value.

Persist winning-source information where needed; retain candidate snapshots selectively.

Do not claim historical reproducibility unless the necessary historical input versions and mapping definitions remain available.

## 9. External simulation and analysis tools

External tools shall participate in the same provenance model.

Example:

```text
UTT dataset / temporal snapshot
    ↓
Export execution
    ↓
Simulation input artifact
    ↓
External model execution (e.g. PALM-4U)
    ↓
Simulation output artifact
    ↓
Import execution
    ↓
UTT results tables
```

Track:

- Execution ID.
- Referenced input datasets and temporal snapshots.
- Exported file or input artifact identifiers.
- Relevant checksums, where available.
- Software/model name and version.
- Configuration and parameters.
- Execution status and timestamps.
- Output artifacts.
- Imported result records or dataset versions.

The lineage system shall establish a traceable chain from source data through UTT, external calculations and back to UTT results.

External tools should not need to understand internal UTT provenance tables. Existing services can perform database registrations on their behalf.

Long-running calculations must not hold database transactions open.

Use separate registration/start and finish/update calls.

Do not implement a general workflow scheduler.

## 10. Transparency and exploration

Provide human-readable views and inspection functions.

Examples:

```sql
SELECT * FROM utt.v_mapping_overview;

SELECT * FROM utt.v_processing_history;

SELECT *
FROM utt.explain_value(
    'building.year_built',
    1002
);
```

Expected questions include:

- Which sources could provide this attribute?
- Which source was selected for this building?
- Why was that source selected?
- Which mappings are applicable in this region?
- Which source datasets contributed to this simulation?
- Which software and parameters produced this result?
- Has the underlying input changed since the calculation?

Users should be able to inspect mappings, provenance and spatial coverage with conventional SQL and QGIS.

Prefer readable views over requiring users to join internal metadata tables manually.

## 11. Implementation strategy

Do not replace existing functionality in one step.

### Phase 1 — Assess existing implementation

Inspect the current repository and database model.

Identify:

- Mirror registry structure and existing source metadata.
- Curation functions and conventions.
- Temporal comparison/merge implementation.
- Existing provenance fields or tables.
- Existing data source and geographic extent handling.
- Relevant external model/export/import interfaces.

Reuse existing capabilities and naming conventions.

Do not create duplicate registries.

### Phase 2 — Design minimal extensions

Propose the smallest database schema changes meeting these requirements.

Provide a concise schema overview and explain each additional table.

Distinguish required features from optional future extensions.

Avoid speculative abstractions.

### Phase 3 — Reference implementation: building age

Use building construction year as the first complete implementation.

It must demonstrate:

- Multiple source mappings.
- Different source priorities.
- Incomplete source coverage.
- Identifier and/or spatial matching where needed.
- Missing-value handling.
- Deterministic resolution.
- Temporal compare-and-merge.
- Winning-source provenance.
- Geographic applicability validation.

Use the actual source mappings and priorities from the existing UTT implementation. Do not invent them.

### Phase 4 — Generic execution

Extract reusable mapping, candidate generation, priority resolution and execution logic from the reference implementation.

Preserve specialized transformations where they remain simpler.

Ensure that generated SQL is inspectable.

### Phase 5 — External processing lineage

Implement a minimal interface for recording export, external execution and result-import chains.

Demonstrate the model with one representative external calculation.

### Phase 6 — Views, validation and documentation

Provide concise SQL examples, readable views and tests.

Test at least:

- Competing priorities.
- Missing candidates.
- Higher-priority source updates.
- Fallback after source removal.
- Deterministic ties.
- Regional incompatibility and partial overlap.
- Temporal updates and unchanged values.
- Provenance changes without value changes.
- External execution chains.
- Referential and historical consistency.

Benchmark generated SQL against the existing hardcoded curation implementation on representative data volumes.

## 12. Explicit non-goals

Do not introduce:

- A separate provenance database.
- A graph database or RDF infrastructure.
- A new application-level workflow engine.
- A generic expression language.
- A large collection of metadata tables.
- Per-record interpretation of metadata during curation.
- Mandatory administrative-region identifiers.
- A wholesale redesign of UTT's temporal model.
- A rewrite of all existing curation functions.

Do not sacrifice PostgreSQL performance or database transparency for theoretical generality.

## 13. Instructions for Codex

**Begin with repository analysis and a concrete design proposal. Do not immediately implement a new framework.**

First, identify existing functionality that can be reused and determine the minimum required schema and function changes.

Present:

1. Proposed tables/columns and relationships.
2. Proposed SQL function interfaces.
3. How mappings compile into efficient SQL.
4. How source resolution and temporal updates interact.
5. How regional applicability is validated.
6. How provenance crosses external processing boundaries.
7. Which existing curation functions can be reused.
8. An incremental implementation plan.

For each proposed abstraction, evaluate whether ordinary SQL or an existing function would be simpler.

**Success criterion:** A researcher can understand where a UTT value came from, why that source was selected, where the data is geographically applicable, and how it was subsequently processed — without needing to understand a complicated framework.

The resulting implementation should remain compact, performant, reusable and understandable using PostgreSQL/PostGIS alone.

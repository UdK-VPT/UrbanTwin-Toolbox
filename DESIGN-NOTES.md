# Design notes

The coordinated implementation is complete for fresh initialization. These sections
record the resolved decisions for review; lasting implementation rules are in
`AGENTS.md`. No changes were applied to the running application database.

## 1. Workflow and database-object reference — implemented

- Create `docs/database-reference.md` as a workflow-oriented developer reference,
  with separate mirror and curation parts.
- Mirror must work without curation. Curation requires an initialized mirror and
  accepted inputs for its mappings. The lasting dependency rule is in `AGENTS.md`.
- Organize mirror by registration, adapters, staging, validation, acceptance/history,
  refresh and retirement; organize curation by mappings, selection, entity versioning,
  provenance, spatial relations and current/as-of readers.
- Cover every UTT-owned table, view, foreign table, function, trigger function,
  trigger and procedure. Explain its purpose, caller or maintainer, and what it
  reads or changes. Exclude extension-owned objects from this inventory.
- Document generated objects by naming pattern and purpose, with SQL to list actual
  instances rather than a manually maintained list of source tables.
- Explain the accepted-input dependency and shared publication locking between the
  two parts. Use the inventory to identify unnecessary objects before implementation.

## 2. Curation and historical-reader names — implemented

- Keep `curate_*` for routines that actually perform curation. Historical readers
  return stored state at system time; they do not execute curation retroactively.
- Rename `utt_pkg.curate_<entity>_at(timestamp)` to
  `utt_pkg.<entity>_at(timestamp)` for all six entities.
- Rename `utt_pkg.curate_provenance_at(entity, timestamp)` to
  `utt_pkg.provenance_at(entity, timestamp)` and
  `utt_pkg.curate_relation_at(type, timestamp)` to
  `utt_pkg.relation_at(type, timestamp)`.
- Keep current views and historical-reader behavior unchanged. Update internal
  callers, grants, routine comments, tests, examples and documentation together.
  Target fresh initialization without compatibility aliases or migration SQL.
- Historical readers have been renamed; internal helpers/triggers now use `curation_`
  rather than the `curate_` workflow prefix.

## 3. Provenance partitions — resolved; retain current structure

- Keep `utt.curation_provenance` partitioned by source registration. Its per-source
  partitions retain ordinary foreign keys to the corresponding source-history tables.
- Do not replace partitions with source-specific columns or generic source-reference
  trigger validation. The pgAdmin “p” identifies the partitioned parent table.
- Explain parent/partition storage and its integrity purpose in the planned reference.
  Partitions are physical tables and must be visible in the object inventory and
  structural-count discussion, even though contributors query one logical table.
- Partitions now have meaningful source-based names; mirror bases and file staging
  also use readable words without hashes or generated numeric suffixes. Native-file
  registry versions share one logical-source partition whose list bounds extend when
  needed, retaining exact file-version references and avoiding name collisions.

## 4. Tables and current views — implemented, documentation only

- Keep the existing table/view implementation unchanged.
- In `docs/database-reference.md`, list the history table and current view for all
  six curated entities and all three relation types, alongside the mirror object
  patterns. Label each object explicitly as a table, view or foreign table.
- Add a short explanation in `docs/uttdb.md`: ordinary read-only current views store
  no additional copy and reflect committed changes automatically. Entity views
  select current versions; relation views select pairs whose endpoints are current.
- Prefer current views in everyday inspection examples. Label history-table and
  version-metadata examples explicitly so readers can distinguish their purpose.
- Delivered in the database reference and UTTDB guide.

## 5. Source column definitions — implemented

- Rename `mirror.schema_revision` to `mirror.source_columns`; rename its `revision`
  column and the corresponding `mirror.import.schema_revision` reference to
  `structure_version`. Keep one row per column per distinct dataset structure version.
- During staging, compare the complete incoming column-definition set with existing
  sets for that registration. Compare names, order, types/type modifiers, collation
  and descriptions using ordinary SQL, without hashes or another metadata table.
- Reuse a matching structure version, including an older matching version if the
  source returns to it. Insert a new definition set only when no existing set matches.
  Unchanged structures must not add duplicate definition rows on each import.
- Each import must reference the exact captured structure version. Keep referenced
  definitions immutable and preserve the distinction between absent columns and
  supplied NULLs, historical interpretation and mapping eligibility.
- Preserve serialized per-dataset staging/publication so concurrent attempts cannot
  create duplicate sets. Update all SQL callers, validation, privileges, comments,
  tests and documentation together for fresh initialization, without migration SQL
  or compatibility aliases. Verify unchanged imports, changed definitions and a
  return to an older structure.
- Implemented and checked with unchanged, changed and returning source structures.

## 6. Maintenance responsibility and routine audience — implemented, documentation only

- In the database reference, distinguish human-configured data from automatically
  maintained history and operational metadata. For mixed tables such as
  `mirror.registry`, list configurable columns and permitted operations separately
  from routine-maintained fields. Explain mapping revision/activation maintenance.
- For each object, identify its maintainer, permitted operations, responsible routine
  and current access roles; do not describe an entire mixed table as freely editable.
- Classify routines by audience: administrative workflow entry points that could
  later serve a frontend admin interface, read-only query interfaces, and internal
  helpers/trigger functions called by other routines or database events.
- Identify candidate admin operations such as registration, configuration, staging,
  acceptance/rejection, refresh, retirement and starting curation. Verify actual
  entry points and prerequisites during the inventory rather than exposing every
  routine in `utt_pkg` as an application interface.
- Keep intended audience distinct from current permissions and execution context,
  including top-level transaction requirements. A future admin interface would use
  authorized server-side calls; this classification grants no browser/database access.
- Document current responsibilities in the guides; keep future frontend integration
  plans here until implemented. No frontend, new wrapper routines, privilege changes
  or extra metadata structures are authorized by this documentation task.
- Delivered with the workflow/object reference; no frontend or privilege expansion.

## 7. Public schema — resolved, no separate task

- Keep UTT-owned implementation objects outside `public`, following the existing
  project schema boundaries. No extension inventory or additional explanation is
  requested for this point.

All original discussion points are resolved and implemented. Fresh mirror-only and
full curation initialization, all six rollback SQL suites, and two-session structure
reuse checks passed in a disposable PostgreSQL 18 database. Routine inventory,
comments, documentation links and whitespace were checked. Live Berlin downloads
were not repeated; the suites use controlled data and generated file fixtures.

# Database workflow reference

This reference inventories UTT-owned objects, including generated objects by pattern.
It excludes extension objects and upstream `citydb` objects. For the model and
practical calls, see [Metadata modelling](metadata-modelling.md), [UTTDB](uttdb.md)
and the [glossary](glossary.md). Routine comments contain complete SQL signatures,
defaults and worked examples.

Mirror runs independently of curation. Curation requires initialized mirror tables
and accepted inputs for its mappings. Both workflows run in PostgreSQL through
`utt_pkg`; they do not require an external worker or frontend.

## Reading the inventory

**Admin entry** means an administrative workflow operation, currently called by a
DBA or authorized pipeline role. **Reader** means a read-only query interface.
**Internal** means a helper called by another routine or a database trigger, even
where a DBA can execute it directly. These categories do not grant permissions.
Existing roles and transaction requirements remain the access boundary.

`uttdb_dba` configures sources and mappings. `uttdb_pipeline` invokes curation entry
points without direct entity/provenance writes. `uttdb_reader` and
`uttdb_developer` can inspect mirror and curated history. Application reader/writer
roles can inspect curated state and historical readers, not administer mirror.
Developers write in sandbox schemas. Reader functions run with caller privileges;
curation engines and selected validation/file helpers use security-definer boundaries.

Initialization creates five shared metadata tables, six entity tables and three
relation tables. Each accepted row dataset adds a history table; each pending import
adds a temporary-lived staging table. Each mapped row-source registration adds a physical
provenance partition; native-file registry versions share one per logical dataset. Thus five shared metadata tables do not mean five physical
tables overall; partitions must be included when assessing structural complexity.

## Mirror

### 1. Register and configure a source

| Object | Kind / audience | Purpose and effects |
|---|---|---|
| `mirror.registry` | Table; mixed human configuration and routine-maintained state | Identifies datasets, source access and ingestion settings. Native-file accepted reference versions also live here; payloads remain outside PostgreSQL. |
| `mirror_register_wfs_source` | Function; admin entry, DBA | Discovers WFS layers, records published metadata and creates read-only OGR foreign tables. Returns source relation names; accepts no feature data. |
| `mirror_register_file_source` | Function; admin entry, DBA | Discovers local vector layers through OGR or creates a lazy GeoTIFF source view. Records registry rows and bounds; returns source relations without persisting accepted pixels/rows. |
| `mirror_register_external_file` | Function; admin entry, DBA | Validates a native file's readability and registers its identity/path/format. Returns the registry ID; creates neither a parser nor accepted file history. |
| `mirror_object_base` | Function; internal naming helper | Produces a readable normalized source/layer base. Rejects empty or overlength names; writes nothing. Shared with curation partition naming. |
| `mirror_layer_extent` | Function; internal spatial helper | Reads geometry or raster hulls and returns geographic bounds; writes nothing. Called during registration and acceptance. |
| `mirror_wfs_revision_dates` | Function; internal metadata reader | Reads WFS/linked ISO metadata for advertised dataset revision dates. Called by registration/refresh; returns dates without accepted-revision claims. |
| `mirror_read_geotiff` | Function; internal source adapter | Reads a self-contained GeoTIFF and returns `rid`/`rast` tiles, without storing them. Used by the raster source view; DBA-only file-reading boundary. |
| OGR foreign server named after the source | Foreign server; registration-managed | Holds access options for WFS/vector adapters; DBA usage. |
| `discovery_<source>` | Short-lived schema with discovered foreign tables | Registration discovers original layers here, then moves/renames them into `mirror` and drops the schema. |

Routine names in this reference are in `utt_pkg`. Generated bases normalize source
and layer words to lowercase with punctuation replaced by underscores; WFS/vector
bases include both source and layer, while a single GeoTIFF uses its source name.
Bases have at most 48 bytes. There are no hashes, truncation or automatic numeric
suffixes. Ambiguous names fail atomically; use distinct, shorter registration names.

Registry fields have different maintenance responsibilities:

| Fields | Maintainer / allowed use |
|---|---|
| `stable_key`, `change_threshold_percent`, `coverage` | DBA ingestion configuration. Set stable keys before row ingestion; accepted keys and registered coverage cannot be repurposed. Every row import covers the registered scope; there is no per-attempt partial-delivery override. |
| `title`, `description`, `fees`, `access_constraints`, `source_owner` | Published metadata supplied explicitly or collected during registration, without inferred rights/ownership. Row registrations can be maintained by DBAs; accepted native-file reference attributes are immutable. |
| `row_id`, `source_name`, `layer_name`, `source_type`, `storage_mode`, `source_url`, `import_scope`, `table_base`, `registered_at`, `path_namespace`, `file_format` | Registration identity/access and storage contract, established through registration routines. Do not repurpose referenced identities or rename generated relations by editing the registry. |
| `stored_table` | Generated column derived from `table_base`; never edited. |
| `last_imported_at`, `source_revision_at`, `extent` | Routine-maintained acceptance/advertised revision/bounds summaries. |
| `utt_txn`, `import_id`, `file_size`, `file_checksum`, `checksum_algorithm` | Accepted native-file reference evidence maintained by acceptance. NULL where inapplicable. |
| `retired` | Retirement state managed through `mirror_unregister_source`. |

### 2. Capture, inspect and publish

| Object | Kind / audience | Purpose and effects |
|---|---|---|
| `mirror.import` | System-maintained table | One ingestion attempt, including pending review state, immutable accepted evidence and diagnostic failures/rejections. DBA reads it for review; routines maintain its contents. |
| `mirror.source_columns` | System-maintained table | One row per column per distinct structure version for a registration. Stores order, type/modifier/collation and description. Imports reuse matching versions, including older matches; unchanged imports add no definitions. |
| `mirror_store_layer` | Function; admin entry, DBA | Fetches one snapshot/manifest, captures evidence and validates it. Automatically accepts eligible snapshots or retains staging for review; records read failures without changing accepted state. |
| `mirror_accept_layer` | Function; admin entry, DBA | Revalidates and publishes the inspected staging contents at one timestamp, versions changes and finalizes the import. Drops staging on success. The `automatic` argument is reserved for the staging routine. |
| `mirror_reject_layer` | Function; admin entry, DBA | Drops pending staging and marks its import rejected; leaves accepted history and files untouched. |
| `mirror_file_evidence` | Function; internal file helper | Returns file size and the named bounded-memory checksum, without decoding content. Called by native registration, staging and acceptance; DBA-only file-reading boundary. |

All three workflow functions return void. They lock the registration row, keeping
staging and definition reuse serialized for that dataset. Every accepted row snapshot
closes missing source versions. Count thresholds hold suspicious updates for review;
partial/delta ingestion is unsupported. Manual acceptance may
bypass thresholds, not integrity validation. Accepted rows, import evidence and
registry summaries commit atomically; an exception rolls publication back.

Each row dataset has the following objects; routines create/manage their definitions
and contents, while readers inspect staging/current/history as permitted:

| Object pattern | Kind | Lifetime / content |
|---|---|---|
| `mirror.<base>_source` | Foreign table for WFS/vector, view for GeoTIFF | Live source adapter, not an accepted local copy; DBA reads it. |
| `mirror.<base>_staging` | Ordinary table, temporarily retained | Incoming rows for one pending import, without UTT version columns. Retained for review; dropped on acceptance/rejection. |
| `mirror.<base>_stored` | Table | Original source state and immutable version/creating-import metadata for all accepted history. |
| `mirror.<base>` | Ordinary read-only view | Current source columns from `_stored`, without duplicate storage. |

Native-file datasets have no `_source`, `_stored` or current-view relations. Their
pending `mirror.<source_layer>_staging` table contains a one-file manifest; accepted
reference history stays in the registry. Query it by logical identity and `utt_txn`.
A mapping can continue referencing its original registry row across file replacements.

A source version's `import_id` identifies its creating accepted import. That import's
`structure_version`, together with its registration, identifies its column-definition
set. This distinguishes columns absent from that source structure from supplied
NULLs, even when old physical columns remain in `_stored`.

### 3. Protect history

These trigger functions are internal and called by the listed triggers. Their
normal callers are database events, not application code.

| Trigger(s) / table | Trigger function | Enforced boundary |
|---|---|---|
| `protect_import`, `protect_import_truncate` / `mirror.import` | `mirror_protect_metadata` | Reject edits/deletion of accepted imports and truncation. |
| `protect_source_columns`, `protect_source_columns_truncate` / `mirror.source_columns` | `mirror_protect_metadata` | Preserve immutable definitions and prevent truncation. |
| `protect_registry`, `protect_registry_truncate` / `mirror.registry` | `mirror_protect_metadata` | Preserve referenced identity, accepted native-file evidence and accepted key/scope contracts; permit controlled closure, summaries and retirement. |
| `protect_history`, `protect_history_truncate` / each `_stored` table | `mirror_protect_history` | Check creating accepted-import ownership; reject deletion/state rewrites/truncation while permitting current-range closure. |

### 4. Refresh or retire

| Routine | Kind / audience | Purpose and effects |
|---|---|---|
| `mirror_update_registered_sources` | Procedure; admin entry, DBA | Refreshes active registrations, skips pending/recent imports, and refreshes WFS advertised metadata separately. Does not discover new layers. Commits each dataset independently; use a top-level `CALL`, outside `BEGIN/COMMIT`. |
| `mirror_unregister_source` | Function; admin entry, DBA | Retires a source or layer after pending imports are resolved. Returns void; stops refresh without deleting registrations, history, adapters or files, and does not withdraw objects. |

Mirror needs none of the curation objects below. When curation is used, its exclusive
lock on `mirror.registry` waits for existing publishers and blocks new publication
while reading accepted inputs. Plain metadata reads remain possible.

## Curation

### 1. Define candidate mappings

| Object | Kind / audience | Purpose and effects |
|---|---|---|
| `utt.curation_mapping` | DBA-maintained configuration table | Stores immutable mapping revisions. DBAs insert new definitions and update only `active`; deletion is rejected. Reads accepted mirror structures before validation. |
| `curation_rule_query` | Function; internal helper | Returns approved candidate SQL for a mapping, including matching, transformations, eligibility and aggregation. Called during mapping validation and curation; writes nothing. |
| `curation_lock_mappings` | Trigger function; internal | Takes the shared advisory transaction lock before mapping changes; returns NULL for statement triggers. |
| `curation_validate_mapping` | Trigger function; internal | Normalizes paired columns, enforces immutable/equal-or-disjoint groups, validates rules/types and ensures the source provenance partition exists. Uses a security-definer boundary. |

| Trigger / table | Function | When / why |
|---|---|---|
| `lock_mapping_changes` / mappings | `curation_lock_mappings` | Before insert/update/delete/truncate, statement-level serialization. |
| `normalize_mapping` / mappings | `curation_validate_mapping` | Before insert/update, preserves positional source/target pairing while normalizing groups. |
| `validate_mapping` / mappings | `curation_validate_mapping` | After insert/update/delete, validates the contract and creates the required partition or rejects deletion. |

Mapping configuration currently uses explicit DBA SQL, not an additional write
wrapper. Activation can be turned off even when source columns are no longer present.

### 2. Select groups and curate domain state

| Routine | Kind / audience | Purpose and effects |
|---|---|---|
| `curate_city`, `curate_district`, `curate_block`, `curate_plot`, `curate_building`, `curate_address` | Functions; admin/pipeline entries | Thin typed-domain entry points calling the shared engine; return inserted-version counts. |
| `curate_entity` | Function; shared engine, DBA/pipeline | Selects accepted inputs by active mappings, compares full managed state, versions changed entities and appends complete selected provenance. Returns inserted-version count; security-definer write boundary. |
| `provenance_at` | Function; reader, also internal engine input | Returns the latest applicable contributor observations at system time using historical groups. The engine uses it to carry former origins. Writes nothing. |

Curation and relation writes share mapping edits' advisory lock `(70303,1)`. Curation
also holds `mirror.registry` EXCLUSIVE to stabilize accepted inputs. Content changes
create entity versions; selection-only changes create provenance observations.
Without replacements, prior state and exact origins remain.

The engine's temporary working tables are `pg_temp.utt_candidates`, `utt_chosen`,
`utt_groups`, `utt_effective`, `utt_previous`, `utt_origins` and `utt_observations`.
They hold intermediate candidates, selected groups, effective state and contributor
sets; they are recreated per call and dropped at commit, not permanent metadata.

All entity tables are system-maintained through curation. Their paired current views
are ordinary read-only views, storing no extra copy:

| History table | Current view | Historical reader in `utt_pkg` |
|---|---|---|
| `utt.city` | `utt.city_current` | `city_at` |
| `utt.district` | `utt.district_current` | `district_at` |
| `utt.block` | `utt.block_current` | `block_at` |
| `utt.plot` | `utt.plot_current` | `plot_at` |
| `utt.building` | `utt.building_current` | `building_at` |
| `utt.address` | `utt.address_current` | `address_at` |

Each table holds all immutable versions; each view selects current versions. Each
reader accepts a system-time timestamp and returns typed stored versions without
rerunning curation. Views/functions and underlying tables require reader privileges.
Current views reflect committed changes automatically.

### 3. Record and protect selected provenance

| Object | Kind / maintainer | Purpose |
|---|---|---|
| `utt.curation_provenance` | Partitioned table; curation engine | One selected contributor per target-version/group observation, with exact mapping, source version/key, accepted import and reason. |
| `utt.provenance_<source_layer>` | Physical table partition; mapping validation creates it | Holds the parent's rows for one row-source registration and adds its history FK. Native-file registry versions share a logical-source partition and retain registry-version FKs. |
| `curation_validate_provenance` | Trigger function; internal | Enforces append-only observations, mapping/target agreement, exact accepted source/key and observation time; locks/checks the generic target reference. |
| `curation_protect_history` | Trigger function; internal | Allows only system-time closure of domain versions and rejects history rewrites/deletion/truncation. |

The “p” on the parent in pgAdmin means partitioned table. Querying the parent reads
its partitions; these are storage pieces, not duplicate provenance. Partitioning is
used for source-specific FK enforcement, not a demonstrated performance requirement.
Names are source-based; ambiguous names are rejected rather than numerically suffixed.
For native files, a mapping can reference the original or a later accepted registry
version. Mapping validation extends the logical-source partition bounds when needed,
under the shared mapping/curation lock; exact source-version references remain intact.

| Trigger(s) / table | Function | Protection |
|---|---|---|
| `validate_provenance`, `protect_provenance_truncate` / provenance parent | `curation_validate_provenance` | Validate inserted observations and reject rewrites/deletion/truncation; row triggers also apply to partitions. |
| `protect_truncate` / each provenance partition | `curation_validate_provenance` | Prevent direct child-table truncation. |
| `protect_history`, `protect_truncate` / all six entity tables | `curation_protect_history` | Preserve domain version state. |

### 4. Calculate spatial relations and inspect history

| Routine | Kind / audience | Purpose and effects |
|---|---|---|
| `curate_relation` | Function; admin/pipeline entry | Backfills absent pairs of coexisting endpoint versions for one relation type; returns inserted-pair count. Run explicitly after endpoint curation. |
| `relation_at` | Function; reader | Returns stored pairs whose endpoints were both current at the requested time; writes nothing. |
| `curation_validate_relation` | Trigger function; internal | Checks endpoint coexistence on insertion; rejects updates/deletion. Endpoint FKs and fraction constraints also apply. |

| System-maintained table | Read-only current view | `relation_at` / `curate_relation` selector |
|---|---|---|
| `utt.relation_bldg_block` | `utt.relation_bldg_block_current` | `building_block` |
| `utt.relation_bldg_plot` | `utt.relation_bldg_plot_current` | `building_plot` |
| `utt.relation_plot_block` | `utt.relation_plot_block_current` | `plot_block` |

Each relation table has a `validate_relation` trigger calling
`curation_validate_relation`. Current relation views require both endpoints to be
current. Relations add no separate time axis. Fractions divide intersection area
by the first endpoint area, round to three decimals and retain values above 0.02.

## Shared setup and finding actual objects

`901-setup-structures.sql` creates project schemas/extensions; `902` establishes roles
and the admin function `utt_pkg.create_developer_sandbox`. A DBA calls that function
for an existing login; it creates/reuses `sandbox_<role>`, grants developer membership
and returns the schema name. The developer maintains that sandbox's own objects.
`903` implements mirror; `912` defines domain/curation structures; `913` implements
curation rules, writes, protections and readers.

These queries list actual instances, including generated relations and triggers:

```sql
SELECT n.nspname AS schema_name, c.relname AS object_name,
       CASE c.relkind WHEN 'r' THEN 'table' WHEN 'p' THEN 'partitioned table'
         WHEN 'v' THEN 'view' WHEN 'f' THEN 'foreign table' END AS object_type,
       c.relispartition AS is_partition, obj_description(c.oid) AS description
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname IN ('mirror','utt') AND c.relkind IN ('r','p','v','f')
ORDER BY 1,2;

SELECT p.oid::regprocedure AS routine, p.prokind,
       p.prorettype='trigger'::regtype AS is_trigger_function,
       obj_description(p.oid) AS description
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='utt_pkg' ORDER BY 1;

SELECT t.tgrelid::regclass AS relation, t.tgname AS trigger_name,
       t.tgfoid::regprocedure AS function, pg_get_triggerdef(t.oid) AS definition
FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname IN ('mirror','utt') AND NOT t.tgisinternal
ORDER BY 1,2;
```

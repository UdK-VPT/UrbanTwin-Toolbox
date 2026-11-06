# Database workflow reference

This reference inventories UTT-owned objects, including generated objects by pattern.
It excludes extension objects and upstream `citydb` objects. For the model and
practical calls, see [Metadata modelling](metadata-modelling.md), [UTTDB](uttdb.md)
and the [glossary](glossary.md). Routine comments contain complete SQL signatures,
defaults and worked examples.

Mirror runs independently of curation. Curation requires initialized mirror tables
and accepted inputs for its recipes. Both workflows run in PostgreSQL through
`mirror` and optional project procedures in `curation`; they require no external worker or frontend.

## Reading the inventory

**Admin entry** means an administrative workflow operation, currently called by a
member of `utt_admin`. **Reader** means a read-only query interface.
**Internal** means a helper called by another routine or a database trigger, even
where a DBA can execute it directly. These categories do not grant permissions.
Existing roles and transaction requirements remain the access boundary.

`utt_admin` administers sources and builds curation datasets. `utt_developer`
reads the five shared schemas and works in an individual sandbox. Applications
have no generic role or implicit administrative access. Routine execution is
restricted by default; the bounded GeoTIFF reader is authorized for developer
source-view queries. Routine comments identify actual callers and effects.

Initialization creates four metadata tables: `mirror.registry`, `mirror.import`,
`mirror.source_columns` and `curation.dataset_build`, plus six snapshot entities
and three relationship tables. Each accepted row dataset adds one source-history
table; each pending import adds one temporarily retained staging table. There are
no curation provenance partitions or additional per-entity metadata tables.

## Mirror

### 1. Register and configure a source

| Object | Kind / audience | Purpose and effects |
|---|---|---|
| `mirror.registry` | Table; mixed human configuration and routine-maintained state | Identifies datasets, source access and ingestion settings. Native-file accepted reference versions also live here; payloads remain outside PostgreSQL. |
| `register_wfs_source` | Function; admin entry, DBA | Discovers WFS layers, records published metadata and creates read-only OGR foreign tables. Returns source relation names; accepts no feature data. |
| `register_file_source` | Function; admin entry, DBA | Discovers local vector layers through OGR or creates a lazy GeoTIFF source view. Records registry rows and bounds; returns source relations without persisting accepted pixels/rows. |
| `register_external_file` | Function; admin entry, DBA | Validates a native file's readability and registers its identity/path/format. Returns the registry ID; creates neither a parser nor accepted file history. |
| `object_base` | Function; internal naming helper | Produces a readable normalized source/layer base. Rejects empty or overlength names; writes nothing. Used by row and native-file staging. |
| `layer_extent` | Function; internal spatial helper | Reads geometry or raster hulls and returns geographic bounds; writes nothing. Called during registration and acceptance. |
| `wfs_revision_dates` | Function; internal metadata reader | Reads WFS/linked ISO metadata for advertised dataset revision dates. Called by registration/refresh; returns dates without accepted-revision claims. |
| `read_geotiff` | Function; internal source adapter | Reads a self-contained GeoTIFF and returns `rid`/`rast` tiles, without storing them. Used by the raster source view; DBA-only file-reading boundary. |
| OGR foreign server named after the source | Foreign server; registration-managed | Holds access options for WFS/vector adapters; DBA usage. |
| `discovery_<source>` | Short-lived schema with discovered foreign tables | Registration discovers original layers here, then moves/renames them into `mirror` and drops the schema. |

Mirror routine names in this reference are in `mirror`, without a `mirror_` prefix. Generated bases normalize source
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
| `file_txn`, `import_id`, `file_size`, `file_checksum`, `checksum_algorithm` | Accepted native-file reference evidence maintained by acceptance. NULL where inapplicable. |
| `retired` | Retirement state managed through `unregister_source`. |

### 2. Capture, inspect and publish

| Object | Kind / audience | Purpose and effects |
|---|---|---|
| `mirror.import` | System-maintained table | One ingestion attempt, including pending review state, immutable accepted evidence and diagnostic failures/rejections. DBA reads it for review; routines maintain its contents. |
| `mirror.source_columns` | System-maintained table | One row per column per distinct structure version for a registration. Stores order, type/modifier/collation and description. Imports reuse matching versions, including older matches; unchanged imports add no definitions. |
| `store_layer` | Function; admin entry, DBA | Fetches one snapshot/manifest, captures evidence and validates it. Automatically accepts eligible snapshots or retains staging for review; records read failures without changing accepted state. |
| `accept_layer` | Function; admin entry, DBA | Revalidates and publishes the inspected staging contents at one timestamp, versions changes and finalizes the import. Drops staging on success. The `automatic` argument is reserved for the staging routine. |
| `reject_layer` | Function; admin entry, DBA | Drops pending staging and marks its import rejected; leaves accepted history and files untouched. |
| `file_evidence` | Function; internal file helper | Returns file size and the named bounded-memory checksum, without decoding content. Called by native registration, staging and acceptance; DBA-only file-reading boundary. |

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
reference history stays in the registry. Query it by logical identity and `file_txn`.
Imports retain exact registry-version references across file replacements.

A source version's `import_id` identifies its creating accepted import. That import's
`structure_version`, together with its registration, identifies its column-definition
set. This distinguishes columns absent from that source structure from supplied
NULLs, even when old physical columns remain in `_stored`.

### 3. Protect history

These trigger functions are internal and called by the listed triggers. Their
normal callers are database events, not application code.

| Trigger(s) / table | Trigger function | Enforced boundary |
|---|---|---|
| `protect_import`, `protect_import_truncate` / `mirror.import` | `protect_metadata` | Reject edits/deletion of accepted imports and truncation. |
| `protect_source_columns`, `protect_source_columns_truncate` / `mirror.source_columns` | `protect_metadata` | Preserve immutable definitions and prevent truncation. |
| `protect_registry`, `protect_registry_truncate` / `mirror.registry` | `protect_metadata` | Preserve referenced identity, accepted native-file evidence and accepted key/scope contracts; permit controlled closure, summaries and retirement. |
| `protect_history`, `protect_history_truncate` / each `_stored` table | `protect_history` | Check creating accepted-import ownership; reject deletion/state rewrites/truncation while permitting current-range closure. |

### 4. Refresh or retire

| Routine | Kind / audience | Purpose and effects |
|---|---|---|
| `update_registered_sources` | Procedure; admin entry, DBA | Refreshes active registrations, skips pending/recent imports, and refreshes WFS advertised metadata separately. Does not discover new layers. Commits each dataset independently; use a top-level `CALL`, outside `BEGIN/COMMIT`. |
| `unregister_source` | Function; admin entry, DBA | Retires a source or layer after pending imports are resolved. Returns void; stops refresh without deleting registrations, history, adapters or files, and does not withdraw objects. |

Mirror needs none of the curation objects below. When curation is used, its exclusive
lock on `mirror.registry` waits for existing publishers and blocks new publication
while reading accepted inputs. Plain metadata reads remain possible.

## Snapshot curation

All project objects below belong to `curation`. There are no generic mapping,
historical provenance or curated-history tables in this demonstration.

| Object | Caller / maintenance | Responsibility |
|---|---|---|
| `curate_berlin_20261101` | Procedure; Administrator entry | Builds and atomically installs six entities, three relationships and build identity. No internal commits; caller transaction controls completion. |
| `curate_berlin_<entity>_20261101` | Procedures; internal build steps | Read the requested mirror snapshot and create indexed temporary tables. Called by the entry point; administrator-only execution. |
| `curate_berlin_relations_20261101` | Procedure; internal chained step | Builds n:m pairs from the same build's entity working tables. |
| `curation_berlin_source` | Function; internal schema check | Resolves stored source and verifies required columns in the accepted snapshot's exact structure definition. |
| `dataset_build` | System-maintained table | One current successful dataset identity, updated with all output tables. Human edits are unsupported. |

The ordinary output tables are `berlin_city`, `berlin_district`, `berlin_block`,
`berlin_plot`, `berlin_building`, `berlin_address`, `berlin_relation_building_block`,
`berlin_relation_building_plot` and `berlin_relation_plot_block`. Each entity's official ID is unique
within its snapshot. Relationships have endpoint foreign keys and unique pairs;
fractions exceed 0.02 and are at most 1. The recipe rounds to three decimals.
Snapshot-local row IDs may change on reconstruction. Readers query the tables directly;
there are no curated current views or historical readers.

The entry point uses a security-definer boundary with a restricted search path.
It serializes builds with advisory transaction lock `(70303,1)` and holds an exclusive
registry lock while selecting accepted inputs. Indexed temporary working tables are
recreated for each call. Installation uses transactional deletes/inserts, preserving
output table identities and dependent queries. A failed final step rolls everything
back. Developers receive no build or internal-step execution privilege.
Administrators own and maintain the SQL definitions.

## Shared setup and finding actual objects

`901-setup-structures.sql` creates project schemas/extensions. `902` contains all
privilege policy, including bootstrap-owned provisioning and the internal
`utt_pkg.apply_shared_privileges()` event-trigger function. The `utt_shared_privileges`
DDL event trigger assigns shared ownership and read access for future objects;
its caller is PostgreSQL, not an application. Role creation and event-trigger
maintenance retain a bootstrap-superuser boundary. Other shared objects belong
to `utt_admin`, except extension members.

| Administrative entry in `utt_pkg` | Effect |
|---|---|
| `create_admin(login_name)` | Creates an individual administrator login; returns its name; no sandbox. |
| `create_developer(login_name)` | Atomically creates an individual login and empty sandbox; returns both names. |
| `create_developer_sandbox(developer_role)` | Creates/reuses an existing login's correctly owned sandbox, configuring peer reads. |
| `deactivate_account(login_name)` | Disables new logins without deleting the sandbox or terminating sessions. |

Only administrator sessions may call these provisioning entries. Credential setup
and sandbox deletion are separate operations; see [account examples](uttdb.md#human-accounts-and-sandboxes).
`903` implements mirror; `913-curation.sql` defines optional project tables and
snapshot procedures. No project object is required by the core privilege hook.

These queries list actual instances, including generated relations and triggers:

```sql
SELECT n.nspname AS schema_name, c.relname AS object_name,
       CASE c.relkind WHEN 'r' THEN 'table' WHEN 'p' THEN 'partitioned table'
         WHEN 'v' THEN 'view' WHEN 'f' THEN 'foreign table' END AS object_type,
       c.relispartition AS is_partition, obj_description(c.oid) AS description
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname IN ('mirror','utt_pkg','curation') AND c.relkind IN ('r','p','v','f')
ORDER BY 1,2;

SELECT p.oid::regprocedure AS routine, p.prokind,
       p.prorettype='trigger'::regtype AS is_trigger_function,
       obj_description(p.oid) AS description
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname IN ('mirror','utt_pkg','curation') ORDER BY 1;

SELECT t.tgrelid::regclass AS relation, t.tgname AS trigger_name,
       t.tgfoid::regprocedure AS function, pg_get_triggerdef(t.oid) AS definition
FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname IN ('mirror','utt_pkg','curation') AND NOT t.tgisinternal
ORDER BY 1,2;
```

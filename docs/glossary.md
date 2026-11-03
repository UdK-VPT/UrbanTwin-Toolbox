# Glossary

Key terms used in the [metadata model](metadata-modelling.md).

## Sources and imports

| Term | Meaning |
|---|---|
| Dataset / layer | A separately registered collection of records with a defined structure and scope. |
| Logical identity | The continuing dataset identity `(source_name, layer_name)`, independent of file paths or version rows. |
| Registry | `mirror.registry`: dataset identity, access and metadata; also accepted reference history for external files. |
| Source adapter | A reader exposing external data to staging, through a foreign table or another supported interface. |
| Staging snapshot | Temporary incoming rows (`_staging`) kept for comparison and review without refetching. |
| Staging manifest | File path, format, size and checksum evidence staged instead of decoded rows. |
| Import | One ingestion attempt in `mirror.import`, with pending evidence and eventual acceptance, rejection or failure. |
| Acceptance / publication | Atomic publication of validated staging contents and their import evidence. |
| Safety threshold | A check for suspicious changes that can hold staging for manual review; integrity validation still applies after approval. |
| Accepted import | Immutable evidence of successful acceptance, including no-op imports where no source state changed. |
| Acceptance time | `mirror.import.accepted_at`; `mirror.registry.last_imported_at` summarizes the latest successful acceptance. |
| Accepted revision | `data_revision_at`: a source revision reliably tied to accepted data, otherwise NULL. |
| Advertised revision | `source_revision_at`: a revision reported by the source, potentially newer than accepted data. |
| Coverage | The registered geographic/thematic dataset scope, captured per import. Mirror treats every row import as a full snapshot of this scope. |
| Full snapshot | All rows supplied by a registered source at ingestion. On acceptance, missing keys close current source versions; partial/delta imports are unsupported. |
| Source structure version | A distinct column-definition set in `mirror.source_columns`, referenced by imports through `structure_version` and reused when unchanged. A PostgreSQL schema such as `mirror` is a namespace. |
| File retention | Keeping accepted files unchanged at version-specific paths so historical references remain retrievable. |

## Identity and time

| Term | Meaning |
|---|---|
| Stable object key | Dataset-scoped identity repeated across an object's versions; `utt_key` is its technical representation in source history. |
| Version | One stored state with immutable `row_id`, distinct from the object's repeatable logical identity. |
| Stored history | `_stored`: accepted source states with their version and creating-import metadata. |
| System time | `utt_txn tstzrange`: when UTT considered a version current, rather than when reality changed. The model's only general temporal axis. |
| Half-open range | `[start, end)` includes its opening and excludes its closing instant; adjacent versions share a boundary without overlapping. |
| Current version | A version with an unbounded system-time end, selected by `upper_inf(utt_txn)`. |
| Source date | An ordinary source attribute, not another temporal axis; mapped date changes count as content changes. |
| Observed history | States actually accepted by UTT; changes between observations cannot be reconstructed. |
| Withdrawal | Closing a current source version absent from an accepted full snapshot; not proof of real-world cessation. |
| Retirement | Ending active use under explicit rules while preserving referenced history. |
| No-op / idempotency | Reprocessing unchanged state creates no additional data versions; a successful import can still be recorded. |
| Checksum / content hash | A fingerprint of file bytes or row state used as change evidence; it cannot restore the original data. |

## Snapshot curation

| Term | Meaning |
|---|---|
| Curation recipe | Versioned SQL procedure defining how to build a typed snapshot dataset from mirror or compatible curated inputs. |
| Mirror snapshot | One requested system-time timestamp selecting accepted source versions. |
| Curated dataset | Cooperating ordinary tables built for one snapshot/region; no record-version history. |
| Build identity | `curation.dataset_build`: current recipe, actual mirror snapshot, region, optional Git revision and completion time. |
| Snapshot default | Fixed recipe timestamp; callers can override it explicitly without changing the default. |
| Working table | Temporary indexed table used by a stepwise recipe before atomic output replacement. |
| Spatial relation | One matched endpoint pair in an n:m table, with attributes such as overlap fraction; no independent temporal history. |
| Derived source | Ordinary source produced by simulation or analysis, potentially using UTT data; explicitly registered through the usual mirror workflow. |
| As-of query | Selects mirror versions whose system-time ranges contain the requested timestamp. Curated historical datasets are rebuilt. |
| Current view | Read-only ordinary mirror view selecting current source versions without copying data. |

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

## Curation and provenance

| Term | Meaning |
|---|---|
| Domain curation | Optional selection and transformation of accepted sources into application-specific entity tables. |
| Mapping revision | An immutable candidate-contribution definition (`mapping_id`); only activation can change. |
| Atomic attribute group | Target attributes selected together; active groups are equal or disjoint. |
| Candidate / eligibility | A possible contribution and whether it meets the approved rule's matching, type and completeness requirements. |
| Priority / fallback | Preference among eligible candidates, with lower numbers winning; fallback selects another eligible candidate. Without replacements, existing state and origins remain. |
| Approved rule | Identified SQL behavior for matching, transformation, eligibility or aggregation; behavior changes receive a new identity. |
| Aggregation | Producing a group from multiple source records while retaining every selected contributor. |
| Carried group | Existing state retained on a new entity version because another group changed, with its original origins. |
| Provenance | Evidence of exact selected source versions and mappings supplying a target version's groups. |
| Contributor | One selected source record/version, mapping and accepted input used for a group. |
| Provenance observation | A timestamped complete contributor set for one target-version/group; its time is not another temporal axis. |
| Selection-only change | Different selected origins producing identical target values; adds provenance without a new entity version. |
| Replacement observation | A complete new selection superseding earlier contributors while preserving their history. |
| As-of query | Reads state or selected origins known at a requested system time, using historical mappings. |
| Current view | A read-only, non-materialized query selecting current versions without copying the dataset. |
| Spatial relation | A connection between immutable endpoint versions, with temporal context derived from their overlapping system-time ranges. |

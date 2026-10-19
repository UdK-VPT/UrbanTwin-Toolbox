# UTT metadata dictionary

Definitions for the requested [metadata model, ver03](metadata_modelling_ver03.md).
These terms describe the target design; they do not imply that every feature is
already implemented. The six sections group the main concepts and their vocabulary.

## 1. Source registration and ingestion

| Term | Definition |
|---|---|
| Source registration and ingestion | Identifying a dataset, reading it into staging, checking it and publishing accepted changes into persistent history. |
| Dataset / layer | An identifiable collection of records with a defined structure and scope. A service may expose several separately registered layers. Research outputs can also be datasets. |
| Source | The origin supplying a dataset, such as a WFS service, file or research tool. |
| Registry (`mirror.registry`) | Metadata describing registered datasets: identity, origin, access, coverage, ownership and related information. It does not store the dataset's feature rows. |
| Metadata | Information describing data, its meaning, origin, structure or handling, rather than the feature values themselves. |
| Foreign table | A PostgreSQL interface for reading externally held data without first copying it into a normal local table. |
| Source adapter | A reader for a source that does not use a foreign table, feeding the same staging workflow. |
| Feature / source record | One identifiable object or record in a source dataset, often with geometry. |
| Staging snapshot (`_staging`) | A temporary local copy of incoming source columns and values. It supports comparison, inspection and manual acceptance without fetching the source again. |
| Validation | Checks that incoming data satisfies required structure and integrity rules. Manual acceptance does not bypass these rules. |
| Safety threshold | An acceptance check for suspicious changes, such as an unexpectedly large decrease in record count. A failed threshold holds staging for manual review. |
| Acceptance / publication | The atomic operation that makes staged changes part of accepted history and commits their import metadata. It may be automatic or explicitly manual. |
| Manual review | Inspection of the existing staging snapshot, requested explicitly or triggered by failed thresholds. It does not require a separate `_review` table. |
| Change detection | Comparing stable keys and source state with current stored versions to identify new, changed, unchanged and eligible withdrawn records. |
| Incremental change set | The differences to apply after comparison. On first import, every incoming record is new. A change set can be derived from a complete snapshot. |
| Complete snapshot | A delivery containing all records within a declared scope. Missing records establish withdrawal only when that scope is also authoritative and verified. |
| Delta delivery | A delivery containing declared changes rather than a complete inventory. Omission alone does not mean deletion. |
| Coverage | The geographic and thematic scope represented by a dataset or delivery. A bounding extent does not prove completeness. |
| Accepted import (`import_id`) | An immutable record identifying a successful acceptance, its time, dataset, schema and coverage evidence. It can exist even when no feature changed. |
| Import time (`imported_at`) | The time of successful local publication; on the registry, it may summarize the latest accepted import. |
| Accepted source revision (`data_revision_at`) | A source-reported revision reliably associated with the accepted data. It is NULL when that association is unknown. |
| Advertised revision | A revision currently reported by a source. It may be newer than the data UTT has accepted. |
| Schema / schema revision | Here, the columns, types and meanings of a dataset, and an identifiable revision of that structure. A PostgreSQL schema such as `mirror` is instead a namespace. |
| Schema evolution | Handling changes to columns, types, units or meanings while keeping historical data interpretable. |

## 2. Temporal model and versioning

| Term | Definition |
|---|---|
| Temporal model and versioning | Rules for retaining successive data states and describing when they were known or valid. |
| Stable object key | A repeatable identifier for a logical object across versions. Its uniqueness is scoped to its dataset; it does not automatically match objects across sources. |
| Logical object | The continuing identity represented by successive stored versions, such as one building identified by a stable source key. |
| Version (`row_id`) | One stored state with an immutable identity. A changed object receives a new version; its previous row remains in history. |
| Stored history (`_stored`) | The persistent table containing source columns plus version metadata: `row_id`, `utt_txn`, creating `import_id` and optionally a content hash. |
| System time (`utt_txn`) | The interval during which UTT considered a stored version current. It describes database knowledge, not necessarily real-world validity. |
| Valid time (`source_valid`) | An optional interval describing when a domain state applies according to source evidence or a documented approximation. Unknown validity remains NULL. |
| Bitemporal model | A model using both system time and valid time to distinguish what UTT knew from when the described condition applied. |
| Timestamp | One instant. An import or provenance observation can have a timestamp without introducing another temporal axis. |
| Time range (`tstzrange`) | A PostgreSQL interval between timestamp bounds; the type used for `utt_txn` and `source_valid`. |
| Half-open range (`[start, end)`) | A range including its start and excluding its end. Adjacent versions can share a boundary without overlapping. |
| Open-ended version | A version with no upper system-time bound, selected by `upper_inf(utt_txn)`. |
| Version closure | Setting the upper system-time bound of an existing version. Replacement opens a new version at that same instant; closure does not erase the old row. |
| Exclusion constraint | A database rule preventing forbidden overlaps between temporal versions of the same stable identity. |
| Observed history | States actually accepted by UTT. It does not reconstruct changes that occurred between observations. |
| Withdrawal | Removal from the accepted current source state under explicit delivery rules. It does not by itself prove real-world demolition or cessation. |
| Retirement | Ending active use of a registration or entity under explicit rules while retaining required historical identities and references. |
| Content-based idempotency | Reprocessing the same state creates no additional data versions. For domain curation, date-only or provenance-only changes also leave entity versions unchanged. |
| Content hash | An optional deterministic fingerprint of complete state used for comparison. It excludes UTT-generated metadata. |

## 3. Domain curation and mappings

| Term | Definition |
|---|---|
| Domain curation and mappings | Optional selection and transformation of accepted source data into a model maintained for a particular application domain. |
| Domain model | Tables, attribute meanings and rules owned by domain maintainers, such as the building-energy model. |
| Entity | A logical object represented in a domain model, such as a building, plot or address. |
| Curated state | The managed attribute values and geometry that describe a domain entity version. |
| Mapping revision (`mapping_id`) | An identifiable definition of a candidate source contribution: source columns, target group, priority and approved rule. Referenced definitions remain immutable except for activation. |
| Atomic attribute group | Attributes selected together from one candidate contribution. Candidates compete for the same complete group; separate groups permit independent fallback. |
| Candidate contribution | A possible source contribution considered for a target group. It becomes provenance only when selected. |
| Eligibility | Whether a candidate satisfies the rule's requirements, including matching, coverage, types and permitted NULL values. |
| Priority | Selection preference among eligible candidates. Lower numbers win; priority does not guarantee accuracy. |
| Fallback | Selecting another eligible candidate when a preferred one cannot supply the group. Without a replacement, retain or fail unless explicit withdrawal rules exist. |
| Matching | Establishing which source records describe a target entity using approved identifiers or spatial rules. |
| Approved rule | Identifiable SQL logic for matching, transformation, eligibility or aggregation. Changed behavior requires a new durable rule identity. |
| Aggregation | Computing one group from multiple contributing source records. All selected contributors must remain traceable. |
| Carried-forward group | An unchanged group included in a new entity version because another group changed. Its provenance must accompany that new version. |

## 4. Provenance

| Term | Definition |
|---|---|
| Provenance | Evidence of which selected source feature versions and mapping revisions supplied a target version's attribute groups. |
| Selected contribution | One source record/version actually used for a group, together with its mapping and accepted-input reference. |
| Provenance observation | A timestamped, complete selection for one target-version/group. It contains one or more contribution rows. |
| Observation time | The system-time event when UTT established a selection. It is not an additional validity axis. |
| Selection reason | A short factual explanation for choosing a contribution, such as highest eligible priority or fallback. |
| Selection-only change | A changed mapping or selected source version that produces identical target values. It adds provenance without creating a new target version. |
| Replacement observation | A new observation containing the entire selected contributor set for a group, so removed contributors do not appear to remain selected. Earlier observations remain in history. |
| Historical provenance | The selected origins known at a requested system time, using the target version and latest applicable observation then, rather than today's mapping activation. |

## 5. Research runs and lineage

| Term | Definition |
|---|---|
| Research runs and lineage | Recording executions and their exact inputs so generated datasets can be traced to the data and methods that produced them. |
| Research dataset | Registered outputs of a calculation, simulation or manual research contribution, ingested through the common versioning path. |
| Run (`run_id`) | One execution with its tool/model version, time/status, parameters, tags, comments and appropriate authorship. |
| Scenario | A defined set of modelled conditions, such as a 2050 case. Distinct scenarios coexist rather than automatically replacing one another. |
| Parameter set | Configuration values for a run, stored once at run level rather than repeated in every output row. |
| Model/code version | An immutable identifier for the method executed, such as a code commit, allowing runs to distinguish changed behavior. |
| Run input | A durable reference to the accepted dataset state or exact versions read, including selection/query, scope and role. |
| Lineage | The chain connecting outputs to runs, exact input states and versioned methods. Group provenance describes the selected origins of curated values within this broader chain. |
| Reproducibility | The ability to reconstruct inputs and methods sufficiently to repeat or inspect a result. Logical data reconstruction does not guarantee byte-exact recovery of original files. |

## 6. Current and historical data access

| Term | Definition |
|---|---|
| Current and historical data access | Interfaces for reading accepted current state, earlier database knowledge and, where available, real-world valid state. |
| Current state | Versions with an unbounded `utt_txn` end. They represent current database knowledge, not necessarily conditions valid today. |
| Current-state view | A normal, read-only, non-materialized query over `_stored` selecting current source rows. It stores no duplicate dataset and reflects committed acceptances automatically. |
| Historical / as-of query | A query selecting versions whose system-time range contains a requested instant. |
| Bitemporal query | A query selecting versions at both a system-time instant and a valid-time instant. Strict valid-time queries exclude unknown validity. |
| Materialization | A deliberately stored copy of query results for performance. The normal current-state view is not materialized; exceptional caches must be explicit and rebuildable. |
| Atomic transaction | A unit of database work whose changes commit together or roll back together, keeping accepted data and metadata consistent. |
| Publication locking | Coordination that prevents competing publications or readers from combining incompatible accepted data and metadata. |
| Privilege boundary | Database permissions controlling who may inspect or modify data. Everyday views and historical tables are protected against uncontrolled writes. |
| Interoperability | Exchange with other representations or systems, including CityGML/3DCityDB, without requiring every dataset to adopt that representation. |


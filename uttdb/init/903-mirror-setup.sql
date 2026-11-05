-- Dataset registrations; native-file versions live here, never in a second file registry.
CREATE TABLE mirror.registry (
  row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source_name text NOT NULL CHECK (btrim(source_name) <> ''),
  layer_name text NOT NULL CHECK (btrim(layer_name) <> ''),
  source_type text NOT NULL CHECK (source_type IN ('wfs', 'file')),
  storage_mode text NOT NULL DEFAULT 'rows' CHECK (storage_mode IN ('rows', 'external_file')),
  source_url text NOT NULL CHECK (btrim(source_url) <> ''),
  import_scope text NOT NULL DEFAULT 'layer' CHECK (import_scope IN ('source', 'layer')),
  table_base text CHECK (octet_length(table_base) BETWEEN 1 AND 48),
  stored_table text GENERATED ALWAYS AS (table_base || '_stored') STORED,
  stable_key text[],
  change_threshold_percent numeric NOT NULL DEFAULT 1 CHECK (change_threshold_percent >= 0),
  retired boolean NOT NULL DEFAULT false,
  registered_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  last_imported_at timestamptz,
  source_revision_at timestamptz,
  title text, description text, fees text, access_constraints text[],
  source_owner text,
  coverage text,
  extent public.geometry(Geometry, 4326),
  file_format text,
  file_size bigint CHECK (file_size >= 0),
  file_checksum text,
  checksum_algorithm text CHECK (checksum_algorithm = 'sha256-chain-1m-v1'),
  path_namespace text,
  file_txn tstzrange,
  import_id bigint,
  CHECK ((storage_mode = 'rows' AND table_base IS NOT NULL AND file_txn IS NULL AND import_id IS NULL)
    OR (storage_mode = 'external_file' AND source_type = 'file' AND table_base IS NULL
      AND path_namespace IS NOT NULL AND file_format IS NOT NULL
      AND (file_txn IS NULL OR (file_size IS NOT NULL AND file_checksum IS NOT NULL AND checksum_algorithm IS NOT NULL AND import_id IS NOT NULL)))),
  CHECK (file_txn IS NULL OR (NOT isempty(file_txn) AND NOT lower_inf(file_txn)
    AND isfinite(lower(file_txn)) AND lower_inc(file_txn) AND NOT upper_inc(file_txn)
    AND (upper_inf(file_txn) OR isfinite(upper(file_txn))))),
  EXCLUDE USING gist (source_name WITH =, layer_name WITH =, storage_mode WITH <>),
  EXCLUDE USING gist (source_name WITH =, layer_name WITH =, file_txn WITH &&)
    WHERE (storage_mode = 'external_file' AND NOT retired)
);
CREATE UNIQUE INDEX registry_rows_identity ON mirror.registry(source_name, layer_name) WHERE storage_mode = 'rows';
-- Retired references retain their ranges; uniqueness/coexistence checks govern
-- non-retired registrations so a retired file source can be registered again.
CREATE UNIQUE INDEX registry_file_current ON mirror.registry(source_name, layer_name)
  WHERE storage_mode = 'external_file' AND NOT retired AND (file_txn IS NULL OR upper_inf(file_txn));
CREATE UNIQUE INDEX registry_table_base ON mirror.registry(table_base) WHERE table_base IS NOT NULL;
CREATE INDEX registry_extent_idx ON mirror.registry USING gist(extent);
COMMENT ON TABLE mirror.registry IS 'Dataset identity and access; external-file accepted versions are stored directly here. row_id identifies a registration version; source_name/layer_name repeats across file versions. Retire rather than delete referenced registrations.';
COMMENT ON COLUMN mirror.registry.storage_mode IS 'rows: one registration with per-layer source/staging/history/current relations; external_file: accepted reference versions directly in this registry. Exclusion prevents mixing modes for one logical identity.';
COMMENT ON COLUMN mirror.registry.checksum_algorithm IS 'Native files use sha256-chain-1m-v1, a bounded-memory 1 MiB block-chain fingerprint documented by file_evidence; not conventional whole-file SHA256.';
COMMENT ON COLUMN mirror.registry.source_owner IS 'Published dataset ownership wording, supplied explicitly when known; NULL when absent. Never inferred from service provider, fees or license statements.';
COMMENT ON COLUMN mirror.registry.coverage IS 'Declared geographic/thematic dataset scope in original wording when supplied, not an inferred bounding extent. Captured per import; each accepted row snapshot replaces current membership within this registered scope.';
COMMENT ON COLUMN mirror.registry.source_revision_at IS 'Latest advertised revision, possibly newer than accepted data. Never evidence of an accepted snapshot revision by itself.';
COMMENT ON COLUMN mirror.registry.stable_key IS 'Ordered source-column names forming a non-NULL unique logical key. Configure explicitly before row ingestion; never infer from physical row positions.';
COMMENT ON COLUMN mirror.registry.source_url IS 'WFS endpoint or server-side file path. File namespace is path_namespace; container files use /source-files paths.';
COMMENT ON COLUMN mirror.registry.table_base IS 'Unique registry-controlled base: _source adapter, _staging cache, _stored history; unsuffixed name is the read-only current view. NULL for external files.';
COMMENT ON COLUMN mirror.registry.file_txn IS 'Accepted external-file reference system time [start,end); NULL for database-row registrations and unaccepted file registrations.';

CREATE TABLE mirror.import (
  import_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  registry_row_id bigint NOT NULL REFERENCES mirror.registry(row_id),
  status text NOT NULL DEFAULT 'staged' CHECK (status IN ('staged','accepted','rejected','failed')),
  staging_table text,
  captured_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  source_location text NOT NULL,
  coverage text,
  accepted_at timestamptz,
  data_revision_at timestamptz,
  structure_version bigint,
  key_columns text[],
  manual_review boolean NOT NULL DEFAULT false,
  validation_errors text[] NOT NULL DEFAULT '{}',
  threshold_failures text[] NOT NULL DEFAULT '{}',
  acceptance_method text CHECK (acceptance_method IN ('automatic','manual')),
  CHECK ((status = 'staged') = (staging_table IS NOT NULL)),
  CHECK ((status = 'accepted') = (accepted_at IS NOT NULL AND acceptance_method IS NOT NULL))
);
CREATE UNIQUE INDEX import_one_pending ON mirror.import(registry_row_id) WHERE status = 'staged';
ALTER TABLE mirror.registry ADD FOREIGN KEY (import_id) REFERENCES mirror.import(import_id);
COMMENT ON COLUMN mirror.import.data_revision_at IS 'Source revision reliably associated with these captured bytes, or NULL. Current WFS/file adapters cannot prove that association; registry advertised revisions are not substituted.';
COMMENT ON COLUMN mirror.import.key_columns IS 'Exact stable-key definition captured at staging; unchanged across accepted history. NULL for pure-file datasets.';
COMMENT ON TABLE mirror.import IS 'One staged/accepted/rejected/failed ingestion attempt. Accepted imports include no-ops and are immutable. Revision is NULL unless reliably tied to captured data. Pending metadata is separate from source columns.';

CREATE TABLE mirror.source_columns (
  registry_row_id bigint NOT NULL REFERENCES mirror.registry(row_id),
  structure_version bigint NOT NULL,
  column_name text NOT NULL,
  ordinal integer NOT NULL,
  type_oid oid NOT NULL,
  type_modifier integer NOT NULL,
  collation_oid oid NOT NULL,
  type_name text NOT NULL,
  description text,
  PRIMARY KEY (registry_row_id, structure_version, column_name),
  UNIQUE (registry_row_id, structure_version, ordinal)
);
COMMENT ON TABLE mirror.source_columns IS 'Immutable distinct source-column definition sets per registration, including original order/type/comments. Imports reuse an equal structure_version, including older sets; only new structures add rows. Absent historical columns are distinct from supplied NULLs.';

-- Only history closure and registry operational summaries may alter accepted state.
CREATE FUNCTION mirror.protect_metadata() RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog SET extra_float_digits=3 AS $$
DECLARE compared_new mirror.registry%ROWTYPE;
BEGIN
  IF TG_OP='TRUNCATE' THEN RAISE EXCEPTION 'Metadata cannot be truncated.'; END IF;
  IF TG_TABLE_NAME = 'registry' AND TG_OP <> 'DELETE' THEN
   IF NEW.storage_mode='external_file' AND NEW.file_txn IS NOT NULL THEN
    IF NOT EXISTS(SELECT FROM mirror.import i JOIN mirror.registry r ON r.row_id=i.registry_row_id
      WHERE i.import_id=NEW.import_id AND i.status='accepted'
        AND r.source_name=NEW.source_name AND r.layer_name=NEW.layer_name AND r.storage_mode='external_file') THEN
      RAISE EXCEPTION 'File versions require an accepted import for their logical dataset.';
    END IF;
   END IF;
  END IF;
  IF TG_OP='INSERT' THEN RETURN NEW; END IF;
  IF TG_TABLE_NAME = 'import' THEN
    IF OLD.status = 'accepted' THEN RAISE EXCEPTION 'Accepted imports are immutable.'; END IF;
  ELSIF TG_TABLE_NAME = 'source_columns' THEN
    RAISE EXCEPTION 'Schema definitions are immutable.';
  ELSIF OLD.storage_mode = 'external_file' AND OLD.file_txn IS NOT NULL THEN
    IF TG_OP='DELETE' THEN
      RAISE EXCEPTION 'Accepted file references are immutable except for system-time closure and retirement.';
    END IF;
    -- Mask only allowed operational changes in a local copy. Native row output
    -- preserves extent geometry without invoking its implicit GeoJSON cast.
    compared_new := NEW;
    compared_new.file_txn := OLD.file_txn;
    compared_new.last_imported_at := OLD.last_imported_at;
    compared_new.retired := OLD.retired;
    IF (compared_new::text COLLATE "C") IS DISTINCT FROM (OLD::text COLLATE "C")
      OR (NEW.file_txn IS DISTINCT FROM OLD.file_txn AND
        (NOT upper_inf(OLD.file_txn) OR NEW.file_txn IS NULL OR upper_inf(NEW.file_txn)
          OR lower(NEW.file_txn) IS DISTINCT FROM lower(OLD.file_txn))) THEN
      RAISE EXCEPTION 'Accepted file references are immutable except for system-time closure and retirement.';
    END IF;
  ELSIF TG_OP = 'UPDATE' AND (NEW.source_name,NEW.layer_name,NEW.storage_mode) IS DISTINCT FROM
    (OLD.source_name,OLD.layer_name,OLD.storage_mode) THEN
    RAISE EXCEPTION 'Registry identities cannot be repurposed.';
  END IF;
  IF TG_TABLE_NAME='registry' AND TG_OP='UPDATE' THEN
    IF OLD.storage_mode='rows' AND (OLD.stable_key IS DISTINCT FROM NEW.stable_key OR OLD.coverage IS DISTINCT FROM NEW.coverage)
      AND EXISTS(SELECT FROM mirror.import WHERE registry_row_id=OLD.row_id AND status='accepted') THEN
      RAISE EXCEPTION 'Stable keys and registered dataset scope cannot change after acceptance; register a distinct dataset.';
    END IF;
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER protect_import BEFORE UPDATE OR DELETE ON mirror.import FOR EACH ROW EXECUTE FUNCTION mirror.protect_metadata();
CREATE TRIGGER protect_source_columns BEFORE UPDATE OR DELETE ON mirror.source_columns FOR EACH ROW EXECUTE FUNCTION mirror.protect_metadata();
CREATE TRIGGER protect_import_truncate BEFORE TRUNCATE ON mirror.import EXECUTE FUNCTION mirror.protect_metadata();
CREATE TRIGGER protect_source_columns_truncate BEFORE TRUNCATE ON mirror.source_columns EXECUTE FUNCTION mirror.protect_metadata();
CREATE TRIGGER protect_registry_truncate BEFORE TRUNCATE ON mirror.registry EXECUTE FUNCTION mirror.protect_metadata();
CREATE TRIGGER protect_registry BEFORE INSERT OR UPDATE OR DELETE ON mirror.registry FOR EACH ROW EXECUTE FUNCTION mirror.protect_metadata();
COMMENT ON FUNCTION mirror.protect_metadata() IS 'Integrity trigger for metadata writes by DBAs: rejects edits/deletion of accepted imports and schema definitions, and rewrites of accepted file state, comparing native row output without GeoJSON conversion of extent. Returns allowed NEW/OLD row. Example firing the trigger: UPDATE mirror.import SET data_revision_at = now() WHERE status = ''accepted''; -- rejected.';

REVOKE ALL ON mirror.registry, mirror.import, mirror.source_columns FROM PUBLIC, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT SELECT ON mirror.registry, mirror.import, mirror.source_columns TO uttdb_reader, uttdb_developer, uttdb_pipeline;
GRANT ALL ON mirror.registry, mirror.import, mirror.source_columns TO uttdb_dba;
-- Shared extent calculation for local registration and accepted data, never a WFS scan at registration.
CREATE OR REPLACE FUNCTION mirror.layer_extent(layer_table regclass)
RETURNS public.geometry
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
DECLARE
  spatial_column record;
  geom_expression text;
  bounds public.geometry;
  column_bounds public.geometry;
  unknown_srid boolean;
BEGIN
  FOR spatial_column IN
    SELECT attname, atttypid FROM pg_attribute
    WHERE attrelid = layer_table AND attnum > 0 AND NOT attisdropped
      AND atttypid IN ('public.geometry'::regtype, 'public.raster'::regtype)
  LOOP
    geom_expression := CASE WHEN spatial_column.atttypid = 'public.raster'::regtype
      THEN format('public.ST_ConvexHull(%I)', spatial_column.attname)
      ELSE format('public.ST_Force2D(%I)', spatial_column.attname) END;
    -- Transform before aggregating, so different source CRSs share one registry index.
    EXECUTE format('SELECT bool_or(public.ST_SRID(geom) = 0),
      public.ST_SetSRID(public.ST_Extent(CASE WHEN public.ST_SRID(geom) > 0
        THEN public.ST_Transform(geom, 4326) END)::public.geometry, 4326)
      FROM (SELECT %s AS geom FROM %s) features
      WHERE geom IS NOT NULL AND NOT public.ST_IsEmpty(geom)', geom_expression, layer_table)
      INTO unknown_srid, column_bounds;
    IF unknown_srid THEN RETURN NULL; END IF;
    IF column_bounds IS NOT NULL THEN
      bounds := CASE WHEN bounds IS NULL THEN column_bounds
        ELSE public.ST_Envelope(public.ST_Collect(bounds, column_bounds)) END;
    END IF;
  END LOOP;
  RETURN bounds;
END;
$$;

REVOKE ALL ON FUNCTION mirror.layer_extent(regclass)
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON FUNCTION mirror.layer_extent(regclass) TO uttdb_dba;
COMMENT ON FUNCTION mirror.layer_extent(regclass) IS
  'DBA invoker-security helper for file registration and publication. Scans geometry columns and raster tile hulls, transforms known coordinates to EPSG:4326 and returns their bounding geometry without writing data. Returns NULL for empty/nonspatial relations or any nonempty geometry with unknown SRID; other transform errors propagate. Raster bounds include NoData cells. Requires SELECT on the relation. Example: SELECT mirror.layer_extent(''mirror.buildings_stored''::regclass);';

-- One naming rule shared by registration and file staging.
CREATE FUNCTION mirror.object_base(source_name text, layer_name text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE base_name text;
BEGIN
  base_name := trim(both '_' FROM regexp_replace(lower(concat_ws('_',source_name,layer_name)),
    '[^a-z0-9_]+','_','g'));
  IF source_name IS NULL OR btrim(source_name)='' OR base_name='' OR octet_length(base_name)>48 THEN
    RAISE EXCEPTION 'Supply a readable source/layer name producing a base of 1 to 48 bytes; got %.',base_name;
  END IF;
  RETURN base_name;
END;
$$;
COMMENT ON FUNCTION mirror.object_base(text,text) IS 'Internal pure naming helper for registration and native-file staging. Normalizes source/layer words to a readable base without hashes or truncation; rejects empty/overlength bases, leaving collisions to registry/catalog uniqueness. Writes nothing and returns text. Use shorter, distinct source names for ambiguous/long names. Example: SELECT mirror.object_base(''berlin_alkis'',''alkis:land'');';

-- Read each distinct metadata URL once; multiple layers often share one dataset.
CREATE OR REPLACE FUNCTION mirror.wfs_revision_dates(
  wfs_url text, capabilities xml DEFAULT NULL
)
RETURNS TABLE (layer_name text, source_revision_at timestamptz)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
SET timezone = 'UTC'
SET http.curlopt_timeout_msec = '30000'
SET http.curlopt_connecttimeout_msec = '10000'
AS $$
DECLARE
  response public.http_response;
  metadata xml;
  linked_record record;
BEGIN
  IF capabilities IS NULL THEN
    SELECT * INTO response FROM public.http_get(wfs_url,
      jsonb_build_object('service', 'WFS', 'request', 'GetCapabilities'));
    IF response.status <> 200 THEN
      RAISE EXCEPTION 'WFS capabilities request failed with HTTP %.', response.status;
    END IF;
    capabilities := XMLPARSE(DOCUMENT response.content);
  END IF;
  IF NOT xmlexists('/*[local-name()="WFS_Capabilities"]' PASSING capabilities) THEN
    RAISE EXCEPTION 'Response is not a WFS capabilities document.';
  END IF;

  FOR linked_record IN
    SELECT layer.metadata_url, array_agg(layer.name ORDER BY layer.name) AS layers
    FROM XMLTABLE(
      '/*/*[local-name()="FeatureTypeList"]/*[local-name()="FeatureType"]'
      PASSING capabilities COLUMNS
        name text PATH '*[local-name()="Name"]',
        metadata_url text PATH '*[local-name()="MetadataURL"][1]/@*[local-name()="href"]'
    ) layer
    GROUP BY layer.metadata_url ORDER BY layer.metadata_url
  LOOP
    source_revision_at := NULL;
    IF linked_record.metadata_url IS NOT NULL THEN
      IF linked_record.metadata_url !~ '^https?://[^[:space:]]+$' THEN
        RAISE EXCEPTION 'MetadataURL must be an HTTP(S) URL: %', linked_record.metadata_url;
      END IF;
      SELECT * INTO response FROM public.http_get(linked_record.metadata_url);
      IF response.status <> 200 THEN
        RAISE EXCEPTION 'WFS metadata request failed with HTTP %: %', response.status, linked_record.metadata_url;
      END IF;
      metadata := XMLPARSE(DOCUMENT response.content);
      -- Only dataset citation revision dates: never metadata dateStamp,
      -- publication/creation dates, service dates or thesaurus citations.
      SELECT max(d.revision::timestamptz) INTO source_revision_at
      FROM XMLTABLE(
        '//*[local-name()="MD_Metadata"]/*[local-name()="identificationInfo"]/*[local-name()="MD_DataIdentification"]/*[local-name()="citation"]/*[local-name()="CI_Citation"]/*[local-name()="date"]/*[local-name()="CI_Date"][*[local-name()="dateType"]/*/@codeListValue="revision"]'
        PASSING metadata COLUMNS
          revision text PATH '*[local-name()="date"]/*[local-name()="Date" or local-name()="DateTime"]'
      ) d;
    END IF;
    FOREACH layer_name IN ARRAY linked_record.layers LOOP
      RETURN NEXT;
    END LOOP;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION mirror.wfs_revision_dates(text, xml)
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON FUNCTION mirror.wfs_revision_dates(text, xml) TO uttdb_dba;
COMMENT ON FUNCTION mirror.wfs_revision_dates(text, xml) IS
  'DBA invoker-security metadata reader used by WFS registration and batch refresh. Fetches capabilities unless supplied, follows each distinct first MetadataURL once, and returns each layer name with its latest ISO 19139 dataset citation revision timestamp. Date-only values become midnight UTC. Missing links or unsupported metadata/date fields yield NULL; HTTP, XML and timestamp errors abort. Writes nothing. Does not interpret revision as feature validity. Example: SELECT * FROM mirror.wfs_revision_dates(''https://gdi.berlin.de/services/wfs/alkis'');';

-- Define all WFS layers as foreign tables. No local feature data is copied.
CREATE OR REPLACE FUNCTION mirror.register_wfs_source(
  p_server_name text,
  p_wfs_url text
)
RETURNS SETOF regclass
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
SET http.curlopt_timeout_msec = '30000'
SET http.curlopt_connecttimeout_msec = '10000'
AS $$
DECLARE
  v_server oid;
  v_response public.http_response;
  v_capabilities xml;
  v_fees text;
  v_access_constraints text[];
  discovery_schema text := 'discovery_' || mirror.object_base(p_server_name);
  discovered record;
BEGIN
  IF p_server_name IS NULL OR btrim(p_server_name) = ''
     OR octet_length(p_server_name) > 63 THEN
    RAISE EXCEPTION 'Server name must contain 1 to 63 bytes.';
  END IF;
  IF p_wfs_url IS NULL OR p_wfs_url !~ '^https?://[^[:space:]]+$' THEN
    RAISE EXCEPTION 'Supply an HTTP(S) WFS service URL.';
  END IF;

  SELECT oid INTO v_server FROM pg_foreign_server WHERE srvname = p_server_name;
  IF v_server IS NULL THEN
    EXECUTE format(
      'CREATE SERVER %I FOREIGN DATA WRAPPER ogr_fdw
       OPTIONS (datasource %L, format %L, updateable %L,
                config_options %L)',
      p_server_name, 'WFS:' || p_wfs_url, 'WFS', 'false',
      'GDAL_HTTP_TIMEOUT=300 GDAL_HTTP_CONNECTTIMEOUT=10'
    );
    EXECUTE format('GRANT USAGE ON FOREIGN SERVER %I TO uttdb_dba', p_server_name);
  ELSIF NOT EXISTS (
    SELECT 1 FROM pg_foreign_server s
    JOIN pg_foreign_data_wrapper w ON w.oid = s.srvfdw
    WHERE s.oid = v_server AND w.fdwname = 'ogr_fdw'
      AND s.srvoptions @> ARRAY['datasource=WFS:' || p_wfs_url,
                               'format=WFS', 'updateable=false']
  ) THEN
    RAISE EXCEPTION 'Server % already exists with different connection options.', p_server_name;
  END IF;

  IF EXISTS (SELECT 1 FROM mirror.registry WHERE source_name = p_server_name) THEN
    RAISE EXCEPTION 'Source % is already registered; registration is not a refresh.', p_server_name;
  END IF;

  -- Fetch capabilities once for metadata. A failed/invalid response must not
  -- silently register layers without their published descriptions.
  SELECT * INTO v_response FROM public.http_get(
    p_wfs_url,
    jsonb_build_object('service', 'WFS', 'request', 'GetCapabilities')
  );
  IF v_response.status <> 200 THEN
    RAISE EXCEPTION 'WFS capabilities request failed with HTTP %.', v_response.status;
  END IF;
  v_capabilities := XMLPARSE(DOCUMENT v_response.content);
  IF NOT xmlexists(
    '/*[local-name()="WFS_Capabilities" and
       (namespace-uri()="http://www.opengis.net/wfs" or
        namespace-uri()="http://www.opengis.net/wfs/2.0")]'
    PASSING v_capabilities
  ) THEN
    RAISE EXCEPTION 'Response is not a WFS capabilities document.';
  END IF;

  -- WFS 1.0 uses Service; later versions use OWS ServiceIdentification.
  SELECT terms.fees INTO v_fees
  FROM XMLTABLE(
    '/*/*[local-name()="ServiceIdentification" or local-name()="Service"]'
    PASSING v_capabilities
    COLUMNS fees text PATH '*[local-name()="Fees"]'
  ) AS terms;
  SELECT array_agg(terms.statement ORDER BY terms.position) INTO v_access_constraints
  FROM XMLTABLE(
    '/*/*[local-name()="ServiceIdentification" or local-name()="Service"]/*[local-name()="AccessConstraints"]'
    PASSING v_capabilities
    COLUMNS position FOR ORDINALITY, statement text PATH '.'
  ) AS terms;

  SELECT oid INTO v_server FROM pg_foreign_server WHERE srvname=p_server_name;
  -- GDAL/OGR discovers the columns and geometry type; we do not infer them ourselves.
  EXECUTE format('CREATE SCHEMA %I', discovery_schema);
  EXECUTE format(
    'IMPORT FOREIGN SCHEMA ogr_all FROM SERVER %I INTO %I
     OPTIONS (launder_table_names %L, launder_column_names %L)',
    p_server_name, discovery_schema, 'false', 'false'
  );

  -- The foreign-table catalog retains the original OGR layer name. Register all
  -- layers atomically with discovery and the original published metadata.
  WITH revisions AS MATERIALIZED (
    SELECT * FROM mirror.wfs_revision_dates(p_wfs_url, v_capabilities)
  )
  INSERT INTO mirror.registry (
    source_name, layer_name, source_type, source_url, import_scope, table_base,
    title, description, fees, access_constraints, source_revision_at, extent
  )
  SELECT p_server_name, layer.option_value, 'wfs', p_wfs_url, 'source', mirror.object_base(p_server_name,layer.option_value),
         metadata.title, metadata.description, v_fees, v_access_constraints, revisions.source_revision_at,
         CASE WHEN bbox.xmin <= bbox.xmax AND bbox.ymin <= bbox.ymax
           AND bbox.xmin >= -180 AND bbox.xmax <= 180
           AND bbox.ymin >= -90 AND bbox.ymax <= 90
         THEN public.ST_MakeEnvelope(bbox.xmin, bbox.ymin, bbox.xmax, bbox.ymax, 4326) END
  FROM pg_foreign_table f
  JOIN pg_class c ON c.oid = f.ftrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_foreign_server s ON s.oid = f.ftserver
  CROSS JOIN LATERAL pg_options_to_table(f.ftoptions) AS layer
  JOIN XMLTABLE(
    '/*/*[local-name()="FeatureTypeList"]/*[local-name()="FeatureType"]'
    PASSING v_capabilities
    COLUMNS
      layer_name text PATH '*[local-name()="Name"]',
      title text PATH '*[local-name()="Title"]',
      description text PATH '*[local-name()="Abstract"]',
      lower_corner text PATH '*[local-name()="WGS84BoundingBox"][1]/*[local-name()="LowerCorner"]',
      upper_corner text PATH '*[local-name()="WGS84BoundingBox"][1]/*[local-name()="UpperCorner"]',
      minx double precision PATH '*[local-name()="LatLongBoundingBox"][1]/@minx',
      miny double precision PATH '*[local-name()="LatLongBoundingBox"][1]/@miny',
      maxx double precision PATH '*[local-name()="LatLongBoundingBox"][1]/@maxx',
      maxy double precision PATH '*[local-name()="LatLongBoundingBox"][1]/@maxy'
  ) AS metadata ON metadata.layer_name = layer.option_value
  LEFT JOIN revisions ON revisions.layer_name = layer.option_value
  CROSS JOIN LATERAL (
    SELECT regexp_split_to_array(btrim(metadata.lower_corner), '\s+') AS lo,
           regexp_split_to_array(btrim(metadata.upper_corner), '\s+') AS hi
  ) corners
  CROSS JOIN LATERAL (
    SELECT COALESCE(corners.lo[1]::double precision, metadata.minx) AS xmin,
           COALESCE(corners.lo[2]::double precision, metadata.miny) AS ymin,
           COALESCE(corners.hi[1]::double precision, metadata.maxx) AS xmax,
           COALESCE(corners.hi[2]::double precision, metadata.maxy) AS ymax
  ) bbox
  WHERE s.srvname = p_server_name AND n.nspname = discovery_schema
    AND layer.option_name = 'layer';

  FOR discovered IN
    SELECT c.relname, r.table_base FROM pg_foreign_table f
    JOIN pg_class c ON c.oid = f.ftrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    CROSS JOIN LATERAL pg_options_to_table(f.ftoptions) o
    JOIN mirror.registry r ON r.source_name = p_server_name AND r.layer_name = o.option_value
    WHERE f.ftserver = v_server AND n.nspname = discovery_schema AND o.option_name = 'layer'
  LOOP
    EXECUTE format('ALTER FOREIGN TABLE %I.%I RENAME TO %I', discovery_schema, discovered.relname, discovered.table_base || '_source');
    EXECUTE format('ALTER FOREIGN TABLE %I.%I SET SCHEMA mirror', discovery_schema, discovered.table_base || '_source');
    RETURN NEXT to_regclass(format('mirror.%I', discovered.table_base || '_source'));
  END LOOP;
  -- RESTRICT catches discovered layers without matching capabilities metadata.
  EXECUTE format('DROP SCHEMA %I RESTRICT', discovery_schema);
END;
$$;

-- Invoker security: the caller supplies its own schema and foreign-server privileges.
REVOKE ALL ON FUNCTION mirror.register_wfs_source(text, text)
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline,
       uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON FUNCTION mirror.register_wfs_source(text, text) TO uttdb_dba;
GRANT USAGE ON FOREIGN DATA WRAPPER ogr_fdw TO uttdb_dba;

COMMENT ON FUNCTION mirror.register_wfs_source(text, text) IS
  'DBA helper: registers all advertised WFS layers as read-only ogr_fdw foreign tables and mirror.registry rows. Records source identity, whole-source selection, first registration and advertised geographic bounds in EPSG:4326 when available; derives _stored names. Published layer titles, abstracts and service-level fees/access constraints are preserved in their original language; absent elements remain NULL. HTTP, XML or layer-matching errors roll back registration. Last import remains NULL until feature storage. Returns foreign table names as regclass values. Registry name limits and relation collisions cause the whole call to roll back, including any newly created server. Linked ISO dataset revision dates populate source_revision_at. Repeated registration is not a refresh. Requires caller database/schema/server and registry-write privileges, normally uttdb_dba membership. Example: SELECT * FROM mirror.register_wfs_source(''berlin_alkis'', ''https://gdi.berlin.de/services/wfs/alkis'');';

-- Manual example; not executed during initialization:
-- SELECT * FROM mirror.register_wfs_source(
--   'berlin_alkis', 'https://gdi.berlin.de/services/wfs/alkis'
-- );
-- Creates one registry-named _source foreign table per layer.

-- One bounded file-read privilege boundary, shared by registration and source views.
-- GeoTIFF decoding is in-memory; tiles persist their pixels inside PostgreSQL.
CREATE OR REPLACE FUNCTION mirror.read_geotiff(file_path text)
RETURNS TABLE (rid bigint, rast public.raster)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
SET postgis.gdal_enabled_drivers = 'GTiff'
AS $$
DECLARE
  image public.raster;
BEGIN
  IF file_path IS NULL OR file_path NOT LIKE '/source-files/%'
    OR file_path ~ '(^|/)(\.|\.\.)(/|$)' OR strpos(file_path, chr(92)) > 0
    OR file_path LIKE '%//%' OR right(file_path, 1) = '/' THEN
    RAISE EXCEPTION 'Supply a GeoTIFF path below /source-files, without dot segments.';
  END IF;
  -- Bound the bytea read; decoded pixels also need to fit in backend memory.
  IF (pg_stat_file(file_path)).size > 268435456 THEN
    RAISE EXCEPTION 'GeoTIFF exceeds the 256 MiB in-memory file limit; use a smaller source.';
  END IF;
  image := public.ST_FromGDALRaster(pg_read_binary_file(file_path));
  IF image IS NULL OR public.ST_Width(image) < 1 OR public.ST_Height(image) < 1
    OR public.ST_NumBands(image) < 1 THEN
    RAISE EXCEPTION 'GeoTIFF must contain pixels and at least one band.';
  END IF;
  RETURN QUERY SELECT tile.ordinality, tile.rast
    FROM public.ST_Tile(image, 256, 256, false) WITH ORDINALITY AS tile(rast, ordinality);
END;
$$;

REVOKE ALL ON FUNCTION mirror.read_geotiff(text)
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON FUNCTION mirror.read_geotiff(text) TO uttdb_dba;
COMMENT ON FUNCTION mirror.read_geotiff(text) IS
  'DBA-only security-definer file reader used by file registration and raster source views. Reads a trusted self-contained GeoTIFF below /source-files, decodes all pixels in memory and returns rid/rast tiles up to 256x256 with all bands, georeferencing and NoData retained. Writes nothing. Enables only GTiff locally; files larger than 256 MiB are rejected and decoded data must also fit memory. Requires the function owner to have server-file read permission; source files and symlinks must be administered by trusted DBAs. Example: SELECT rid, public.ST_Metadata(rast) FROM mirror.read_geotiff(''/source-files/heat.tif'');';

-- Register vector layers through OGR, or a GeoTIFF as a lazy raster source view.
-- GeoTIFFs use their filename as layer_name and a collision-checked naming base.
CREATE OR REPLACE FUNCTION mirror.register_file_source(
  source_name text, file_path text,
  driver text DEFAULT NULL, open_options text DEFAULT NULL
)
RETURNS SETOF regclass
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
  server_oid oid;
  server_options text;
  layer record;
  raster_layer text;
  layer_extent public.geometry;
  discovery_schema text := 'discovery_' || mirror.object_base(source_name);
  base_name text;
BEGIN
  IF source_name IS NULL OR btrim(source_name) = '' OR octet_length(source_name) > 63 THEN
    RAISE EXCEPTION 'Source name must contain 1 to 63 bytes.';
  END IF;
  -- Use container paths, never host drive letters, URLs, or GDAL connection strings.
  -- Source files and any sidecars/symlinks remain under trusted DBA administration.
  IF file_path IS NULL OR file_path NOT LIKE '/source-files/%'
    OR file_path ~ '(^|/)(\.|\.\.)(/|$)' OR strpos(file_path, chr(92)) > 0
    OR file_path LIKE '%//%' OR right(file_path, 1) = '/' THEN
    RAISE EXCEPTION 'Supply a file or dataset-directory path below /source-files, without dot segments.';
  END IF;
  IF driver IS NOT NULL AND btrim(driver) = '' THEN
    RAISE EXCEPTION 'driver must be a GDAL driver name or NULL for detection.';
  END IF;
  IF EXISTS (SELECT FROM mirror.registry r WHERE r.source_name = register_file_source.source_name)
    OR EXISTS (SELECT FROM pg_foreign_server s WHERE s.srvname = register_file_source.source_name) THEN
    RAISE EXCEPTION 'Source/server % already exists; registration is not a refresh.', source_name;
  END IF;

  -- Minimal raster adapter: a single self-contained GeoTIFF, one registry layer.
  -- Other file formats retain the OGR vector path (including vector GeoPackages).
  IF driver = 'GTiff' OR (driver IS NULL AND file_path ~* '\.(tif|tiff)$') THEN
    IF open_options IS NOT NULL THEN
      RAISE EXCEPTION 'GeoTIFF open_options are not supported.';
    END IF;
    base_name := mirror.object_base(source_name);
    raster_layer := regexp_replace(file_path, '^.*/', '');
    EXECUTE format(
      'CREATE VIEW mirror.%I WITH (security_invoker = true) AS
       SELECT rid, rast FROM mirror.read_geotiff(%L)', base_name || '_source', file_path);
    EXECUTE format('COMMENT ON VIEW mirror.%I IS %L', base_name || '_source',
      format('Raster source %I.%I; read with mirror.read_geotiff.', source_name, raster_layer));
    EXECUTE format('REVOKE ALL ON mirror.%I FROM PUBLIC, uttdb_reader, uttdb_developer,
      uttdb_pipeline, uttdb_app_reader, uttdb_app_writer', base_name || '_source');
    EXECUTE format('GRANT SELECT ON mirror.%I TO uttdb_dba', base_name || '_source');
    -- Decode and measure now; registration persists only the extent, not pixels.
    layer_extent := mirror.layer_extent(to_regclass(format('mirror.%I', base_name || '_source')));
    INSERT INTO mirror.registry (source_name, layer_name, source_type, source_url, import_scope, table_base, extent, stable_key)
    VALUES (source_name, raster_layer, 'file', file_path, 'source', base_name, layer_extent, ARRAY['rid']);
    RETURN NEXT to_regclass(format('mirror.%I', base_name || '_source'));
    RETURN;
  END IF;

  server_options := format('datasource %L, updateable %L', file_path, 'false');
  IF driver IS NOT NULL THEN
    server_options := server_options || format(', format %L', driver);
  END IF;
  IF open_options IS NOT NULL THEN
    server_options := server_options || format(', open_options %L', open_options);
  END IF;
  EXECUTE format('CREATE SERVER %I FOREIGN DATA WRAPPER ogr_fdw OPTIONS (%s)', source_name, server_options);
  EXECUTE format('GRANT USAGE ON FOREIGN SERVER %I TO uttdb_dba', source_name);
  EXECUTE format('CREATE SCHEMA %I', discovery_schema);
  EXECUTE format(
    'IMPORT FOREIGN SCHEMA ogr_all FROM SERVER %I INTO %I
     OPTIONS (launder_table_names %L, launder_column_names %L)', source_name, discovery_schema, 'false', 'false');

  SELECT s.oid INTO server_oid FROM pg_foreign_server s
  WHERE s.srvname = register_file_source.source_name;
  FOR layer IN
    SELECT c.oid, c.relname, options.option_value AS original_name
    FROM pg_foreign_table f JOIN pg_class c ON c.oid = f.ftrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    CROSS JOIN LATERAL pg_options_to_table(f.ftoptions) options
    WHERE f.ftserver = server_oid AND n.nspname = discovery_schema AND options.option_name = 'layer'
    ORDER BY c.relname
  LOOP
    base_name := mirror.object_base(source_name,layer.original_name);
    EXECUTE format('ALTER FOREIGN TABLE %I.%I RENAME TO %I', discovery_schema, layer.relname, base_name || '_source');
    EXECUTE format('ALTER FOREIGN TABLE %I.%I SET SCHEMA mirror', discovery_schema, base_name || '_source');
    layer_extent := mirror.layer_extent(layer.oid::regclass);
    INSERT INTO mirror.registry (source_name, layer_name, source_type, source_url, import_scope, table_base, extent)
    VALUES (source_name, layer.original_name, 'file', file_path, 'source', base_name, layer_extent);
    RETURN NEXT layer.oid::regclass;
  END LOOP;
  EXECUTE format('DROP SCHEMA %I RESTRICT', discovery_schema);
  IF NOT EXISTS (SELECT FROM mirror.registry r WHERE r.source_name = register_file_source.source_name) THEN
    RAISE EXCEPTION 'Dataset has no importable vector layers; registration rolled back.';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION mirror.register_file_source(text, text, text, text)
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON FUNCTION mirror.register_file_source(text, text, text, text) TO uttdb_dba;
COMMENT ON FUNCTION mirror.register_file_source(text, text, text, text) IS
  'DBA invoker-security registration: discovers all vector layers in a local dataset below /source-files using ogr_fdw, creates read-only source relations and source_type=file registry rows, and returns their regclass names. GeoTIFF (.tif/.tiff with no driver, or explicit GTiff) registers one registry-named _source view and one layer named after the filename, with stable tile key rid; every read inventories the entire self-contained raster. It validates by decoding but persists no pixels; requires a self-contained file at most 256 MiB and no open_options. Other formats use OGR vector discovery. Registration scans file geometry/raster bounds into registry.extent in EPSG:4326 (NULL for unknown SRID or empty/nonspatial data). No source rows are stored until store_layer or the batch procedure runs. GDAL detects the driver unless supplied; open_options passes driver-specific options. Published metadata is left NULL because no generic metadata extraction is implemented. Unsupported/unreadable files, empty datasets, name collisions roll back the entire registration. Files remain untouched. Example: SELECT * FROM mirror.register_file_source(''buildings'', ''/source-files/berlin/buildings.gpkg''); CSV: SELECT * FROM mirror.register_file_source(''points'', ''/source-files/points.csv'', ''CSV'', ''X_POSSIBLE_NAMES=longitude Y_POSSIBLE_NAMES=latitude'');';

-- A bounded reader fingerprints native files without decoding or loading them into PostGIS.
CREATE FUNCTION mirror.file_evidence(file_path text)
RETURNS TABLE(file_size bigint, file_checksum text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE offset_bytes bigint := 0; block bytea; fingerprint bytea := ''::bytea; initial record; final_stat record;
BEGIN
  IF file_path IS NULL OR file_path NOT LIKE '/source-files/%'
    OR file_path ~ '(^|/)(\.|\.\.)(/|$)' OR strpos(file_path, chr(92)) > 0
    OR file_path LIKE '%//%' OR right(file_path,1) = '/' THEN
    RAISE EXCEPTION 'Supply a trusted file below /source-files without dot segments.';
  END IF;
  SELECT * INTO initial FROM pg_stat_file(file_path);
  IF initial.isdir THEN RAISE EXCEPTION 'Expected a regular file.'; END IF;
  LOOP
    block := pg_read_binary_file(file_path, offset_bytes, 1048576);
    EXIT WHEN octet_length(block) = 0;
    fingerprint := sha256(fingerprint || block);
    offset_bytes := offset_bytes + octet_length(block);
  END LOOP;
  SELECT * INTO final_stat FROM pg_stat_file(file_path);
  IF offset_bytes <> initial.size OR final_stat.size <> initial.size
    OR final_stat.modification IS DISTINCT FROM initial.modification THEN
    RAISE EXCEPTION 'File changed while being read; finish uploading before registration.';
  END IF;
  RETURN QUERY SELECT offset_bytes, encode(sha256(fingerprint), 'hex');
END;
$$;
COMMENT ON FUNCTION mirror.file_evidence(text) IS 'DBA-only security-definer reader used during native-file staging/acceptance. Returns byte size and bounded-memory checksum without parsing. Algorithm sha256-chain-1m-v1: start empty, hash previous digest concatenated with each 1048576-byte block, then SHA256 the final digest (also defines empty files). Not the conventional whole-file SHA256. Files/symlinks below /source-files require trusted administration and immutable paths. Writes nothing. Example: SELECT * FROM mirror.file_evidence(''/source-files/climate/v1.nc'');';

CREATE FUNCTION mirror.register_external_file(source_name text, layer_name text,
  file_path text, file_format text)
RETURNS bigint LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog AS $$
DECLARE registration bigint;
BEGIN
  -- Validate naming/readability now; accepted evidence is captured during staging.
  PERFORM mirror.object_base(source_name,layer_name);
  PERFORM * FROM mirror.file_evidence(file_path);
  IF file_format IS NULL OR btrim(file_format) = '' THEN RAISE EXCEPTION 'Supply the native file format.'; END IF;
  INSERT INTO mirror.registry(source_name,layer_name,source_type,storage_mode,source_url,file_format,path_namespace)
  VALUES(source_name,layer_name,'file','external_file',file_path,file_format,'database-container:/source-files')
  RETURNING row_id INTO registration;
  RETURN registration;
END;
$$;
COMMENT ON FUNCTION mirror.register_external_file(text,text,text,text) IS 'DBA registration of one independently versioned native file dataset directly in mirror.registry. Validates readability but stores no payload or accepted history; returns registry row_id. No PostGIS conversion or foreign relation. Example: SELECT mirror.register_external_file(''climate'',''temperature'',''/source-files/climate/v1.nc'',''NetCDF''); Then SELECT mirror.store_layer(''climate'',''temperature'');';

-- Accepted history is append-only except for closing the current system-time bound.
CREATE FUNCTION mirror.protect_history() RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog SET extra_float_digits=3 AS $$
DECLARE accepted_registry bigint; compared_new record;
BEGIN
  IF TG_OP='TRUNCATE' THEN RAISE EXCEPTION 'Source history cannot be truncated.'; END IF;
  IF TG_OP = 'INSERT' THEN
    SELECT registry_row_id INTO accepted_registry FROM mirror.import WHERE import_id = NEW.import_id AND status = 'accepted';
    IF accepted_registry IS DISTINCT FROM TG_ARGV[0]::bigint THEN RAISE EXCEPTION 'History requires an accepted import for this dataset.'; END IF;
  ELSE
    IF TG_OP='DELETE' THEN
      RAISE EXCEPTION 'Source history is immutable except for current system-time closure.';
    END IF;
    -- Native row text uses lossless PostGIS geometry/raster output, not GeoJSON.
    -- Raster has no binary-send function, so generic record_send is unsuitable.
    -- Only the time range may differ; this copy never changes the stored old row.
    compared_new := NEW;
    compared_new.utt_txn := OLD.utt_txn;
    IF (compared_new::text COLLATE "C") IS DISTINCT FROM (OLD::text COLLATE "C")
      OR NOT upper_inf(OLD.utt_txn) OR upper_inf(NEW.utt_txn)
      OR lower(NEW.utt_txn) IS DISTINCT FROM lower(OLD.utt_txn) THEN
      RAISE EXCEPTION 'Source history is immutable except for current system-time closure.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
COMMENT ON FUNCTION mirror.protect_history() IS 'Trigger installed by acceptance on each _stored table: checks creating accepted-import ownership, prevents deletion/state rewrites using lossless native row output without GeoJSON conversion, and allows current-range closure only. Returns NEW. Example firing it: DELETE FROM mirror.example_stored; -- rejected.';

-- Capture once. Validation errors or threshold failures retain this exact cache.
CREATE OR REPLACE FUNCTION mirror.store_layer(source_name text, layer_name text,
  review boolean DEFAULT false, file_path text DEFAULT NULL, file_format text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog SET TimeZone='UTC' AS $$
DECLARE
  entry mirror.registry%ROWTYPE; attempt bigint; staging text; source_oid oid; stored_oid oid;
  attr record; captured_revision bigint; errors text[] := '{}'; failures text[] := '{}';
  null_test text; key_expression text; old_counts bigint[]; new_counts bigint[];
  count_expressions text; names text[]; i integer; invalid boolean; raster_changed boolean;
BEGIN
  IF review IS NULL THEN RAISE EXCEPTION 'review must be true or false.'; END IF;
  SELECT r.* INTO STRICT entry FROM mirror.registry r
  WHERE r.source_name = store_layer.source_name AND r.layer_name = store_layer.layer_name
    AND NOT r.retired AND (r.file_txn IS NULL OR upper_inf(r.file_txn)) FOR UPDATE;
  IF EXISTS (SELECT FROM mirror.import WHERE registry_row_id = entry.row_id AND status = 'staged') THEN
    RAISE EXCEPTION 'Accept or reject the pending import before fetching again.';
  END IF;
  INSERT INTO mirror.import(registry_row_id,staging_table,key_columns,manual_review,source_location,coverage)
  VALUES(entry.row_id,'pending',entry.stable_key,review,
    CASE WHEN entry.storage_mode='external_file' THEN coalesce(file_path,entry.source_url) ELSE entry.source_url END,
    entry.coverage) RETURNING import_id INTO attempt;
  staging := CASE WHEN entry.storage_mode = 'rows' THEN entry.table_base || '_staging' ELSE mirror.object_base(entry.source_name,entry.layer_name) || '_staging' END;
  UPDATE mirror.import SET staging_table = staging WHERE import_id = attempt;

  -- Subtransaction makes a failed read inspectable without leaving half a cache.
  BEGIN
    IF entry.storage_mode = 'external_file' THEN
      EXECUTE format('CREATE TABLE mirror.%I AS SELECT $1::text AS file_path, $2::text AS file_format,
        $3::text AS path_namespace, e.* FROM mirror.file_evidence($1) e', staging)
        USING coalesce(file_path,entry.source_url),coalesce(file_format,entry.file_format),entry.path_namespace;
    ELSE
      IF file_path IS NOT NULL OR file_format IS NOT NULL THEN RAISE EXCEPTION 'File overrides require external_file storage.'; END IF;
      source_oid := to_regclass(format('mirror.%I',entry.table_base || '_source'));
      IF source_oid IS NULL THEN RAISE EXCEPTION 'Source adapter is missing.'; END IF;
      EXECUTE format('CREATE TABLE mirror.%I AS SELECT * FROM %s',staging,source_oid::regclass);
      -- The registration row lock serializes capture/reuse for this dataset.
      WITH incoming AS MATERIALIZED (
        SELECT a.attname::text AS column_name,a.attnum::integer AS ordinal,
          a.atttypid AS type_oid,a.atttypmod AS type_modifier,a.attcollation AS collation_oid,
          format_type(a.atttypid,a.atttypmod) AS type_name,
          col_description(source_oid,sa.attnum) AS description
        FROM pg_attribute a
        LEFT JOIN pg_attribute sa ON sa.attrelid=source_oid AND sa.attname=a.attname AND NOT sa.attisdropped
        WHERE a.attrelid=to_regclass(format('mirror.%I',staging)) AND a.attnum>0 AND NOT a.attisdropped
      ), matching AS (
        SELECT DISTINCT c.structure_version FROM mirror.source_columns c
        WHERE c.registry_row_id=entry.row_id AND NOT EXISTS (
          (SELECT column_name,ordinal,type_oid,type_modifier,collation_oid,type_name,description FROM incoming
           EXCEPT SELECT column_name,ordinal,type_oid,type_modifier,collation_oid,type_name,description
           FROM mirror.source_columns WHERE registry_row_id=entry.row_id AND structure_version=c.structure_version)
          UNION ALL
          (SELECT column_name,ordinal,type_oid,type_modifier,collation_oid,type_name,description
           FROM mirror.source_columns WHERE registry_row_id=entry.row_id AND structure_version=c.structure_version
           EXCEPT SELECT column_name,ordinal,type_oid,type_modifier,collation_oid,type_name,description FROM incoming)
        )
      ), chosen AS (
        SELECT coalesce((SELECT min(structure_version) FROM matching),
          (SELECT coalesce(max(structure_version),0)+1 FROM mirror.source_columns WHERE registry_row_id=entry.row_id)) AS version,
          NOT EXISTS(SELECT FROM matching) AS is_new
      ), inserted AS (
        INSERT INTO mirror.source_columns
        SELECT entry.row_id,chosen.version,incoming.* FROM incoming CROSS JOIN chosen WHERE chosen.is_new
      )
      SELECT version INTO captured_revision FROM chosen;
      UPDATE mirror.import SET structure_version = captured_revision WHERE import_id = attempt;
    END IF;
    EXECUTE format('REVOKE ALL ON mirror.%I FROM PUBLIC, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer',staging);
    EXECUTE format('GRANT SELECT ON mirror.%I TO uttdb_reader, uttdb_developer, uttdb_pipeline',staging);
    EXECUTE format('GRANT ALL ON mirror.%I TO uttdb_dba',staging);
    EXECUTE format('ALTER TABLE mirror.%I OWNER TO uttdb_dba',staging);
  EXCEPTION WHEN OTHERS THEN
    UPDATE mirror.import SET status='failed',staging_table=NULL,validation_errors=ARRAY[SQLERRM] WHERE import_id=attempt;
    RAISE WARNING 'Import % failed: %',attempt,SQLERRM;
    RETURN;
  END;
  -- Advertised WFS metadata is not reliably associated with downloaded feature bytes.
  -- Keep data_revision_at NULL until an adapter can provide that association.
  IF entry.storage_mode = 'rows' THEN
    IF entry.stable_key IS NULL OR cardinality(entry.stable_key) = 0
      OR EXISTS (SELECT FROM unnest(entry.stable_key) k GROUP BY k HAVING count(*) > 1)
      OR EXISTS (SELECT FROM unnest(entry.stable_key) k WHERE k IS NULL OR NOT EXISTS
        (SELECT FROM mirror.source_columns WHERE registry_row_id=entry.row_id AND structure_version=captured_revision AND column_name=k)) THEN
      errors := array_append(errors,'Configure nonempty, distinct stable_key source columns before ingestion.');
    ELSIF EXISTS (SELECT FROM mirror.source_columns c JOIN pg_type t ON t.oid=c.type_oid
      WHERE c.registry_row_id=entry.row_id AND c.structure_version=captured_revision
        AND c.column_name=ANY(entry.stable_key)
        AND (t.oid IN ('public.geometry'::regtype,'public.geography'::regtype,'public.raster'::regtype)
          OR t.typelem IN ('public.geometry'::regtype,'public.geography'::regtype,'public.raster'::regtype)
          OR t.typbasetype IN ('public.geometry'::regtype,'public.geography'::regtype,'public.raster'::regtype))) THEN
      errors := array_append(errors,'Stable keys must use nonspatial identifier columns, not geometry, geography or raster.');
    ELSE
      SELECT string_agg(format('%I IS NULL',k),' OR ' ORDER BY n),
        'jsonb_build_array(' || string_agg(format('%I',k),',' ORDER BY n) || ')::text'
      INTO null_test,key_expression FROM unnest(entry.stable_key) WITH ORDINALITY u(k,n);
      EXECUTE format('SELECT EXISTS(SELECT FROM mirror.%I WHERE %s) OR EXISTS(SELECT FROM mirror.%I GROUP BY %s HAVING count(*)>1)',staging,null_test,staging,key_expression) INTO invalid;
      IF invalid THEN errors := array_append(errors,'Stable keys must be non-NULL and unique.'); END IF;
    END IF;
    IF EXISTS (SELECT FROM mirror.source_columns WHERE registry_row_id=entry.row_id AND structure_version=captured_revision
      AND column_name IN ('row_id','utt_txn','import_id','utt_key')) THEN
      errors := array_append(errors,'Source columns collide with row_id/utt_txn/import_id/utt_key; explicitly rename in the source adapter.');
    END IF;
    stored_oid := to_regclass(format('mirror.%I',entry.stored_table));
    IF stored_oid IS NOT NULL THEN
      FOR attr IN SELECT * FROM mirror.source_columns WHERE registry_row_id=entry.row_id AND structure_version=captured_revision LOOP
        IF EXISTS (SELECT FROM pg_attribute WHERE attrelid=stored_oid AND attname=attr.column_name AND NOT attisdropped
          AND (atttypid,atttypmod,attcollation) IS DISTINCT FROM (attr.type_oid,attr.type_modifier,attr.collation_oid)) THEN
          errors := array_append(errors,format('Incompatible type change for %I: use a new source column or distinct dataset.',attr.column_name));
        END IF;
      END LOOP;
      SELECT string_agg(format('count(*)-count(%I)',column_name),',' ORDER BY ordinal),array_agg(column_name ORDER BY ordinal)
      INTO count_expressions,names FROM mirror.source_columns sr WHERE registry_row_id=entry.row_id AND sr.structure_version=captured_revision
        AND EXISTS(SELECT FROM pg_attribute WHERE attrelid=stored_oid AND attname=column_name AND NOT attisdropped);
      IF count_expressions IS NOT NULL THEN
        EXECUTE format('SELECT ARRAY[count(*),%s] FROM mirror.%I WHERE upper_inf(utt_txn)',count_expressions,entry.stored_table) INTO old_counts;
        EXECUTE format('SELECT ARRAY[count(*),%s] FROM mirror.%I',count_expressions,staging) INTO new_counts;
        FOR i IN 1..cardinality(old_counts) LOOP
          IF abs(new_counts[i]::numeric-old_counts[i])*100 > old_counts[i]::numeric*entry.change_threshold_percent THEN
            failures := array_append(failures,format('%s: %s -> %s',CASE WHEN i=1 THEN 'rows' ELSE 'NULLs in '||names[i-1] END,old_counts[i],new_counts[i]));
          END IF;
        END LOOP;
      END IF;
    END IF;

    IF EXISTS(SELECT FROM mirror.source_columns WHERE registry_row_id=entry.row_id AND structure_version=captured_revision AND type_oid='public.raster'::regtype) THEN
      EXECUTE format('SELECT NOT EXISTS(SELECT FROM mirror.%I) OR EXISTS(SELECT FROM mirror.%I WHERE rid IS NULL OR rast IS NULL
        OR public.ST_Width(rast)<1 OR public.ST_Height(rast)<1 OR public.ST_NumBands(rast)<1)
        OR EXISTS(SELECT FROM mirror.%I t CROSS JOIN LATERAL public.ST_BandMetadata(t.rast,ARRAY[]::integer[]) b WHERE b.isoutdb)',staging,staging,staging) INTO invalid;
      IF invalid THEN errors := array_append(errors,'Raster requires nonempty in-database tiles.'); END IF;
      IF stored_oid IS NOT NULL AND cardinality(errors)=0 THEN
        EXECUTE format('SELECT EXISTS(SELECT FROM (SELECT * FROM mirror.%I WHERE upper_inf(utt_txn)) o
          FULL JOIN mirror.%I n USING(rid) WHERE o.rid IS NULL OR n.rid IS NULL
          OR public.ST_Metadata(o.rast) IS DISTINCT FROM public.ST_Metadata(n.rast)
          OR ARRAY(SELECT (b.pixeltype,b.nodatavalue)::text FROM public.ST_BandMetadata(o.rast,ARRAY[]::integer[]) b ORDER BY b.bandnum)
             IS DISTINCT FROM ARRAY(SELECT (b.pixeltype,b.nodatavalue)::text FROM public.ST_BandMetadata(n.rast,ARRAY[]::integer[]) b ORDER BY b.bandnum))',entry.stored_table,staging) INTO raster_changed;
        IF raster_changed THEN failures := array_append(failures,'Raster grid/band metadata changed.');
        ELSE
          EXECUTE format('WITH o AS (SELECT band,sum(public.ST_Count(rast,band,true)) pixels FROM mirror.%I
            CROSS JOIN LATERAL generate_series(1,public.ST_NumBands(rast)) band WHERE upper_inf(utt_txn) GROUP BY band),
            n AS (SELECT band,sum(public.ST_Count(rast,band,true)) pixels FROM mirror.%I
            CROSS JOIN LATERAL generate_series(1,public.ST_NumBands(rast)) band GROUP BY band)
            SELECT EXISTS(SELECT FROM o JOIN n USING(band) WHERE abs(n.pixels-o.pixels)*100 > o.pixels*$1)',entry.stored_table,staging)
            INTO raster_changed USING entry.change_threshold_percent;
          IF raster_changed THEN failures := array_append(failures,'Raster valid-pixel counts exceed threshold.'); END IF;
        END IF;
      END IF;
    END IF;
  END IF;
  UPDATE mirror.import SET validation_errors=errors,threshold_failures=failures WHERE import_id=attempt;
  IF review OR cardinality(errors)>0 OR cardinality(failures)>0 THEN
    RAISE NOTICE 'Import % retained in mirror.%: validation %, thresholds %. Accept or reject explicitly.',attempt,staging,errors,failures;
  ELSE
    BEGIN
      PERFORM mirror.accept_layer(source_name,layer_name,true);
    EXCEPTION WHEN OTHERS THEN
      UPDATE mirror.import SET validation_errors=array_append(validation_errors,SQLERRM) WHERE import_id=attempt;
      RAISE WARNING 'Import % remains staged after publication failed: %',attempt,SQLERRM;
    END;
  END IF;
END;
$$;
COMMENT ON FUNCTION mirror.store_layer(text,text,boolean,text,text) IS 'DBA staging entry point for row adapters and native-file registry datasets. Returns void; caches one snapshot/manifest and import evidence. Invalid data/threshold failures remain staged, read failures are recorded failed, and accepted state stays unchanged. Automatically accepts valid threshold-passing data unless review=true. file_path/file_format override only the next native-file manifest. Every row import is a full snapshot of the registered source scope; accepting it closes missing source versions. Partial/delta imports are unsupported. Threshold failures retain staging for explicit review. Revision remains NULL without reliable snapshot association. Example: SELECT mirror.store_layer(''berlin_alkis'',''alkis:bezirk'',review=>true); Native replacement: SELECT mirror.store_layer(''climate'',''temperature'',file_path=>''/source-files/climate/v2.nc'');';

CREATE OR REPLACE FUNCTION mirror.accept_layer(source_name text,layer_name text,
  automatic boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog SET TimeZone='UTC' SET extra_float_digits=3 AS $$
DECLARE
  entry mirror.registry%ROWTYPE; pending mirror.import%ROWTYPE; stage_oid oid; history_oid oid;
  evidence record; manifest record; attr record; columns_sql text; source_columns text; old_columns text;
  key_sql text; null_sql text; invalid boolean; at_time timestamptz; new_registry bigint;
  changed_sql text; schema_changed_imports bigint[];
BEGIN
  SELECT r.* INTO STRICT entry FROM mirror.registry r WHERE r.source_name=accept_layer.source_name
    AND r.layer_name=accept_layer.layer_name AND NOT r.retired
    AND (r.file_txn IS NULL OR upper_inf(r.file_txn)) FOR UPDATE;
  SELECT * INTO STRICT pending FROM mirror.import WHERE registry_row_id=entry.row_id AND status='staged' FOR UPDATE;
  IF automatic AND (pending.manual_review OR cardinality(pending.validation_errors)>0 OR cardinality(pending.threshold_failures)>0) THEN
    RAISE EXCEPTION 'Import requires manual review or validation repair.';
  END IF;
  stage_oid := to_regclass(format('mirror.%I',pending.staging_table));
  IF stage_oid IS NULL THEN RAISE EXCEPTION 'Staging cache is missing.'; END IF;
  EXECUTE format('LOCK TABLE %s IN ACCESS EXCLUSIVE MODE',stage_oid::regclass);
  at_time := clock_timestamp();
  IF entry.storage_mode='external_file' THEN
    EXECUTE format('SELECT count(*)<>1 FROM %s',stage_oid::regclass) INTO invalid;
    IF invalid THEN RAISE EXCEPTION 'File manifest requires exactly one file.'; END IF;
    EXECUTE format('SELECT * FROM %s',stage_oid::regclass) INTO manifest;
    SELECT * INTO evidence FROM mirror.file_evidence(manifest.file_path);
    IF (evidence.file_size,evidence.file_checksum) IS DISTINCT FROM (manifest.file_size,manifest.file_checksum)
      OR manifest.file_format IS NULL OR btrim(manifest.file_format)='' OR manifest.path_namespace IS DISTINCT FROM entry.path_namespace THEN
      RAISE EXCEPTION 'Staged file changed or manifest is invalid; reject and stage again.';
    END IF;
    UPDATE mirror.import SET status='accepted',staging_table=NULL,accepted_at=at_time,
      acceptance_method=CASE WHEN automatic THEN 'automatic' ELSE 'manual' END,validation_errors='{}'
    WHERE import_id=pending.import_id;
    IF entry.file_txn IS NULL THEN
      UPDATE mirror.registry SET source_url=manifest.file_path,file_format=manifest.file_format,
        file_size=manifest.file_size,file_checksum=manifest.file_checksum,checksum_algorithm='sha256-chain-1m-v1',
        file_txn=tstzrange(at_time,NULL,'[)'),import_id=pending.import_id,last_imported_at=at_time WHERE row_id=entry.row_id;
    ELSIF (entry.source_url,entry.file_format,entry.file_size,entry.file_checksum) IS DISTINCT FROM
      (manifest.file_path,manifest.file_format,manifest.file_size,manifest.file_checksum) THEN
      UPDATE mirror.registry SET file_txn=tstzrange(lower(file_txn),at_time,'[)') WHERE row_id=entry.row_id;
      INSERT INTO mirror.registry(source_name,layer_name,source_type,storage_mode,source_url,import_scope,
        registered_at,last_imported_at,title,description,fees,access_constraints,source_owner,coverage,extent,file_format,path_namespace,
        file_size,file_checksum,checksum_algorithm,file_txn,import_id,change_threshold_percent)
      VALUES(entry.source_name,entry.layer_name,'file','external_file',manifest.file_path,entry.import_scope,
        entry.registered_at,at_time,entry.title,entry.description,entry.fees,entry.access_constraints,entry.source_owner,entry.coverage,entry.extent,
        manifest.file_format,entry.path_namespace,manifest.file_size,manifest.file_checksum,'sha256-chain-1m-v1',
        tstzrange(at_time,NULL,'[)'),pending.import_id,entry.change_threshold_percent);
    ELSE
      UPDATE mirror.registry SET last_imported_at=at_time WHERE row_id=entry.row_id;
    END IF;
  ELSE
    IF pending.key_columns IS DISTINCT FROM entry.stable_key OR EXISTS(
      SELECT FROM mirror.import WHERE registry_row_id=entry.row_id AND status='accepted'
        AND key_columns IS DISTINCT FROM pending.key_columns) THEN
      RAISE EXCEPTION 'Stable-key definitions cannot change across accepted history or pending staging. Reject and re-stage if not yet accepted.';
    END IF;
    -- Validate the captured layout, never today's remote adapter definition.
    IF EXISTS(
      (SELECT attname::text,attnum::integer,atttypid,atttypmod,attcollation FROM pg_attribute WHERE attrelid=stage_oid AND attnum>0 AND NOT attisdropped
       EXCEPT SELECT column_name,ordinal,type_oid,type_modifier,collation_oid FROM mirror.source_columns WHERE registry_row_id=entry.row_id AND structure_version=pending.structure_version)
      UNION ALL
      (SELECT column_name,ordinal,type_oid,type_modifier,collation_oid FROM mirror.source_columns WHERE registry_row_id=entry.row_id AND structure_version=pending.structure_version
       EXCEPT SELECT attname::text,attnum::integer,atttypid,atttypmod,attcollation FROM pg_attribute WHERE attrelid=stage_oid AND attnum>0 AND NOT attisdropped)) THEN
      RAISE EXCEPTION 'Staged layout differs from captured schema.';
    END IF;
    IF entry.stable_key IS NULL OR cardinality(entry.stable_key)=0
      OR EXISTS(SELECT FROM unnest(entry.stable_key) k GROUP BY k HAVING count(*)>1)
      OR EXISTS(SELECT FROM unnest(entry.stable_key) k WHERE k IS NULL OR NOT EXISTS(SELECT FROM pg_attribute WHERE attrelid=stage_oid AND attname=k AND NOT attisdropped)) THEN
      RAISE EXCEPTION 'Configure valid distinct stable-key columns.';
    END IF;
    IF EXISTS (SELECT FROM pg_attribute a JOIN pg_type t ON t.oid=a.atttypid
      WHERE a.attrelid=stage_oid AND a.attnum>0 AND NOT a.attisdropped
        AND a.attname=ANY(entry.stable_key)
        AND (t.oid IN ('public.geometry'::regtype,'public.geography'::regtype,'public.raster'::regtype)
          OR t.typelem IN ('public.geometry'::regtype,'public.geography'::regtype,'public.raster'::regtype)
          OR t.typbasetype IN ('public.geometry'::regtype,'public.geography'::regtype,'public.raster'::regtype))) THEN
      RAISE EXCEPTION 'Stable keys must use nonspatial identifier columns, not geometry, geography or raster.';
    END IF;
    IF EXISTS(SELECT FROM pg_attribute WHERE attrelid=stage_oid AND attnum>0 AND attname IN ('row_id','utt_txn','import_id','utt_key')) THEN
      RAISE EXCEPTION 'Reserved metadata column collision; explicitly rename in adapter.';
    END IF;
    SELECT string_agg(format('s.%I IS NULL',k),' OR ' ORDER BY n),
      'jsonb_build_array(' || string_agg(format('s.%I',k),',' ORDER BY n) || ')::text'
      INTO null_sql,key_sql FROM unnest(entry.stable_key) WITH ORDINALITY u(k,n);
    EXECUTE format('SELECT EXISTS(SELECT FROM %s s WHERE %s) OR EXISTS(SELECT FROM %s s GROUP BY %s HAVING count(*)>1)',stage_oid::regclass,null_sql,stage_oid::regclass,key_sql) INTO invalid;
    IF invalid THEN RAISE EXCEPTION 'Stable keys must be non-NULL and unique.'; END IF;
    -- Raster structure is an integrity boundary, even on manual acceptance.
    IF EXISTS(SELECT FROM pg_attribute WHERE attrelid=stage_oid AND atttypid='public.raster'::regtype AND NOT attisdropped) THEN
      EXECUTE format('SELECT NOT EXISTS(SELECT FROM %s) OR EXISTS(SELECT FROM %s WHERE rid IS NULL OR rast IS NULL
        OR public.ST_Width(rast)<1 OR public.ST_Height(rast)<1 OR public.ST_NumBands(rast)<1)
        OR EXISTS(SELECT FROM %s t CROSS JOIN LATERAL public.ST_BandMetadata(t.rast,ARRAY[]::integer[]) b WHERE b.isoutdb)',stage_oid::regclass,stage_oid::regclass,stage_oid::regclass) INTO invalid;
      IF invalid THEN RAISE EXCEPTION 'Raster requires nonempty in-database tiles.'; END IF;
    END IF;
    SELECT string_agg(format('%I',column_name),',' ORDER BY ordinal),
      string_agg(format('s.%I',column_name),',' ORDER BY ordinal),string_agg(format('h.%I',column_name),',' ORDER BY ordinal)
      INTO columns_sql,source_columns,old_columns FROM mirror.source_columns
      WHERE registry_row_id=entry.row_id AND structure_version=pending.structure_version;
    history_oid := to_regclass(format('mirror.%I',entry.stored_table));
    IF history_oid IS NULL THEN
      EXECUTE format('CREATE TABLE mirror.%I AS SELECT * FROM %s WITH NO DATA',entry.stored_table,stage_oid::regclass);
      EXECUTE format('ALTER TABLE mirror.%I ADD COLUMN row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        ADD COLUMN utt_txn tstzrange NOT NULL, ADD COLUMN import_id bigint NOT NULL REFERENCES mirror.import(import_id),
        ADD COLUMN utt_key text NOT NULL,
        ADD CHECK(NOT isempty(utt_txn) AND NOT lower_inf(utt_txn) AND isfinite(lower(utt_txn))
          AND lower_inc(utt_txn) AND NOT upper_inc(utt_txn) AND (upper_inf(utt_txn) OR isfinite(upper(utt_txn)))),
        ADD EXCLUDE USING gist(utt_key WITH =,utt_txn WITH &&)',entry.stored_table);
      EXECUTE format('CREATE TRIGGER protect_history BEFORE INSERT OR UPDATE OR DELETE ON mirror.%I FOR EACH ROW EXECUTE FUNCTION mirror.protect_history(%L)',entry.stored_table,entry.row_id::text);
      EXECUTE format('CREATE TRIGGER protect_history_truncate BEFORE TRUNCATE ON mirror.%I EXECUTE FUNCTION mirror.protect_history()',entry.stored_table);
      EXECUTE format('CREATE INDEX ON mirror.%I(utt_key) WHERE upper_inf(utt_txn)',entry.stored_table);
      history_oid := to_regclass(format('mirror.%I',entry.stored_table));
    ELSE
      EXECUTE format('LOCK TABLE %s IN SHARE ROW EXCLUSIVE MODE',history_oid::regclass);
      -- Keys cannot silently change once history exists.
      EXECUTE format('SELECT EXISTS(SELECT FROM %s s WHERE jsonb_build_array(%s)::text IS DISTINCT FROM s.utt_key)',history_oid::regclass,
        (SELECT string_agg(format('s.%I',k),',' ORDER BY n) FROM unnest(entry.stable_key) WITH ORDINALITY u(k,n))) INTO invalid;
      IF invalid THEN RAISE EXCEPTION 'Stable-key definition differs from existing history.'; END IF;
      FOR attr IN SELECT * FROM mirror.source_columns WHERE registry_row_id=entry.row_id AND structure_version=pending.structure_version LOOP
        IF EXISTS(SELECT FROM pg_attribute WHERE attrelid=history_oid AND attname=attr.column_name AND NOT attisdropped) THEN
          IF EXISTS(SELECT FROM pg_attribute WHERE attrelid=history_oid AND attname=attr.column_name AND (atttypid,atttypmod,attcollation) IS DISTINCT FROM (attr.type_oid,attr.type_modifier,attr.collation_oid)) THEN
            RAISE EXCEPTION 'Incompatible type/collation change for %. Use a new column or dataset.',attr.column_name;
          END IF;
        ELSE
          EXECUTE format('ALTER TABLE %s ADD COLUMN %I %s%s',history_oid::regclass,attr.column_name,attr.type_name,
            CASE WHEN attr.collation_oid=0 THEN '' ELSE ' COLLATE '||attr.collation_oid::regcollation::text END);
        END IF;
      END LOOP;
    END IF;
    -- Import state and all new versions commit together; guards require accepted status.
    UPDATE mirror.import SET status='accepted',staging_table=NULL,accepted_at=at_time,
      acceptance_method=CASE WHEN automatic THEN 'automatic' ELSE 'manual' END,validation_errors='{}'
      WHERE import_id=pending.import_id;
    -- Equal definitions share a structure version, so compare references directly.
    SELECT array_agg(i.import_id) INTO schema_changed_imports FROM mirror.import i
    WHERE i.registry_row_id=entry.row_id AND i.status='accepted'
      AND i.structure_version<>pending.structure_version;
    -- Native row output retains exact geometry/raster state, NULLs and typed
    -- source values. Whole-row JSON would invoke the GeoJSON cast, which rejects
    -- MultiSurface and can round coordinates on otherwise supported geometries.
    changed_sql := format('((ROW(%s)::text COLLATE "C") IS DISTINCT FROM (ROW(%s)::text COLLATE "C") OR h.import_id=ANY($2))',old_columns,source_columns);
    EXECUTE format('UPDATE %s h SET utt_txn=tstzrange(lower(h.utt_txn),$1,''[)'')
      FROM %s s WHERE upper_inf(h.utt_txn) AND h.utt_key=%s AND %s',
      history_oid::regclass,stage_oid::regclass,key_sql,changed_sql) USING at_time,schema_changed_imports;
    -- Acceptance publishes a full snapshot: absence closes current source history.
    EXECUTE format('UPDATE %s h SET utt_txn=tstzrange(lower(h.utt_txn),$1,''[)'')
      WHERE upper_inf(h.utt_txn) AND NOT EXISTS(SELECT FROM %s s WHERE h.utt_key=%s)',
      history_oid::regclass,stage_oid::regclass,key_sql) USING at_time;
    EXECUTE format('INSERT INTO %s(%s,utt_key,utt_txn,import_id)
      SELECT %s,%s,tstzrange($1,NULL,''[)''),$2 FROM %s s
      WHERE NOT EXISTS(SELECT FROM %s h WHERE h.utt_key=%s AND upper_inf(h.utt_txn))',history_oid::regclass,columns_sql,source_columns,key_sql,stage_oid::regclass,history_oid::regclass,key_sql)
      USING at_time,pending.import_id;
    -- Recreate only the derived current view when columns are removed/reordered.
    IF to_regclass(format('mirror.%I',entry.table_base)) IS NOT NULL AND EXISTS(
      (SELECT attname::text,atttypid,atttypmod,attnum::integer FROM pg_attribute
        WHERE attrelid=to_regclass(format('mirror.%I',entry.table_base)) AND attnum>0 AND NOT attisdropped
       EXCEPT SELECT column_name,type_oid,type_modifier,ordinal FROM mirror.source_columns WHERE registry_row_id=entry.row_id AND structure_version=pending.structure_version)
    ) THEN
      EXECUTE format('DROP VIEW mirror.%I RESTRICT',entry.table_base);
    END IF;
    EXECUTE format('CREATE OR REPLACE VIEW mirror.%I WITH (security_invoker=true) AS SELECT %s FROM %s WHERE upper_inf(utt_txn)',entry.table_base,columns_sql,history_oid::regclass);
    FOR attr IN SELECT * FROM mirror.source_columns WHERE registry_row_id=entry.row_id AND structure_version=pending.structure_version LOOP
      IF attr.type_oid='public.geometry'::regtype AND NOT EXISTS(SELECT FROM pg_index WHERE indrelid=history_oid AND indkey[0]=(SELECT attnum FROM pg_attribute WHERE attrelid=history_oid AND attname=attr.column_name) AND indisvalid) THEN
        EXECUTE format('CREATE INDEX ON %s USING gist(%I)',history_oid::regclass,attr.column_name);
      ELSIF attr.type_oid='public.raster'::regtype AND NOT EXISTS(SELECT FROM pg_index WHERE indrelid=history_oid AND indexprs IS NOT NULL) THEN
        EXECUTE format('CREATE INDEX ON %s USING gist(public.ST_ConvexHull(%I))',history_oid::regclass,attr.column_name);
      END IF;
    END LOOP;
    EXECUTE format('REVOKE ALL ON %s, mirror.%I FROM PUBLIC, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer',history_oid::regclass,entry.table_base);
    EXECUTE format('GRANT SELECT ON %s, mirror.%I TO uttdb_reader, uttdb_developer, uttdb_pipeline',history_oid::regclass,entry.table_base);
    EXECUTE format('GRANT ALL ON %s TO uttdb_dba',history_oid::regclass);
    EXECUTE format('ALTER TABLE %s OWNER TO uttdb_dba',history_oid::regclass);
    EXECUTE format('ALTER VIEW mirror.%I OWNER TO uttdb_dba',entry.table_base);
    EXECUTE format('ANALYZE %s',history_oid::regclass);
    UPDATE mirror.registry SET last_imported_at=at_time,
      extent=mirror.layer_extent(to_regclass(format('mirror.%I',entry.table_base))) WHERE row_id=entry.row_id;
  END IF;
  EXECUTE format('DROP TABLE %s',stage_oid::regclass);
END;
$$;
COMMENT ON FUNCTION mirror.accept_layer(text,text,boolean) IS 'DBA acceptance of cached staging without re-fetch. Revalidates captured layout, keys and raster integrity or exact native-file checksum. Closes changed and missing source versions from the full snapshot and inserts replacements at one timestamp; no-ops still record immutable imports. Manual acceptance overrides thresholds only. External-file reference versions remain in registry. Returns void; exceptions roll back publication and retain staging. Example: SELECT mirror.accept_layer(''berlin_alkis'',''alkis:bezirk''); automatic=true is reserved for validated automatic staging.';

CREATE FUNCTION mirror.reject_layer(source_name text,layer_name text)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE entry mirror.registry%ROWTYPE; pending mirror.import%ROWTYPE;
BEGIN
  SELECT r.* INTO STRICT entry FROM mirror.registry r WHERE r.source_name=reject_layer.source_name
    AND r.layer_name=reject_layer.layer_name AND NOT r.retired
    AND (r.file_txn IS NULL OR upper_inf(r.file_txn)) FOR UPDATE;
  SELECT * INTO STRICT pending FROM mirror.import WHERE registry_row_id=entry.row_id AND status='staged' FOR UPDATE;
  EXECUTE format('DROP TABLE mirror.%I',pending.staging_table);
  UPDATE mirror.import SET status='rejected',staging_table=NULL WHERE import_id=pending.import_id;
END;
$$;
COMMENT ON FUNCTION mirror.reject_layer(text,text) IS 'DBA rejection of a pending import for the non-retired registration. Drops its staging cache, marks import rejected and preserves accepted data and original files. Returns void. Example: SELECT mirror.reject_layer(''berlin_alkis'',''alkis:bezirk'');';

CREATE OR REPLACE FUNCTION mirror.unregister_source(source_name text,layer_name text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE entry mirror.registry%ROWTYPE; found_entry boolean := false;
BEGIN
  FOR entry IN SELECT r.* FROM mirror.registry r WHERE r.source_name=unregister_source.source_name
    AND (unregister_source.layer_name IS NULL OR r.layer_name=unregister_source.layer_name)
    AND NOT r.retired AND (r.file_txn IS NULL OR upper_inf(r.file_txn)) ORDER BY r.layer_name FOR UPDATE
  LOOP
    found_entry:=true;
    IF EXISTS(SELECT FROM mirror.import WHERE registry_row_id=entry.row_id AND status='staged') THEN
      RAISE EXCEPTION 'Accept or reject pending imports before retirement.';
    END IF;
    UPDATE mirror.registry SET retired=true WHERE row_id=entry.row_id;
  END LOOP;
  IF NOT found_entry THEN RAISE EXCEPTION 'No active matching registration.'; END IF;
END;
$$;
COMMENT ON FUNCTION mirror.unregister_source(text,text) IS 'DBA retirement, replacing destructive unregister semantics. Marks matching active registrations retired and stops refresh; preserves registry/import/history rows, source adapters and original files. Does not claim source withdrawal. Reject/accept staging first. Returns void. Example: SELECT mirror.unregister_source(''berlin_alkis'',''alkis:bezirk'');';

CREATE OR REPLACE PROCEDURE mirror.update_registered_sources(review boolean DEFAULT false,
  source_type text DEFAULT NULL,skip_interval interval DEFAULT interval '1 hour')
LANGUAGE plpgsql SECURITY INVOKER AS $$
DECLARE selected record; entry mirror.registry%ROWTYPE; checked_source text;
BEGIN
  IF review IS NULL OR (skip_interval IS NOT NULL AND skip_interval<interval '0')
    OR (source_type IS NOT NULL AND source_type NOT IN ('wfs','file')) THEN RAISE EXCEPTION 'Invalid refresh options.'; END IF;
  FOR selected IN SELECT r.source_name,r.layer_name FROM mirror.registry r
    WHERE NOT r.retired AND (r.file_txn IS NULL OR upper_inf(r.file_txn))
      AND (update_registered_sources.source_type IS NULL OR r.source_type=update_registered_sources.source_type)
    ORDER BY r.source_name,r.layer_name
  LOOP
    SELECT r.* INTO entry FROM mirror.registry r WHERE r.source_name=selected.source_name AND r.layer_name=selected.layer_name
      AND NOT r.retired AND (r.file_txn IS NULL OR upper_inf(r.file_txn)) FOR UPDATE;
    IF FOUND THEN
      IF entry.source_type='wfs' AND checked_source IS DISTINCT FROM entry.source_name THEN
        WITH revisions AS MATERIALIZED(SELECT * FROM mirror.wfs_revision_dates(entry.source_url))
        UPDATE mirror.registry r SET source_revision_at=(SELECT d.source_revision_at FROM revisions d WHERE d.layer_name=r.layer_name)
        WHERE r.source_name=entry.source_name AND r.storage_mode='rows';
        checked_source:=entry.source_name;
      END IF;
      IF EXISTS(SELECT FROM mirror.import WHERE registry_row_id=entry.row_id AND status='staged') THEN
        RAISE NOTICE 'Skipping %.%: import awaits acceptance/rejection.',entry.source_name,entry.layer_name;
      ELSIF skip_interval IS NULL OR entry.last_imported_at IS NULL OR entry.last_imported_at<=clock_timestamp()-skip_interval THEN
        PERFORM mirror.store_layer(entry.source_name,entry.layer_name,review);
      END IF;
    END IF;
    COMMIT;
  END LOOP;
END;
$$;
COMMENT ON PROCEDURE mirror.update_registered_sources(boolean,text,interval) IS 'DBA top-level batch, outside BEGIN/COMMIT: refreshes active row/file registrations in stable order, committing each dataset independently. Skips pending staging and recently accepted imports; skip_interval NULL disables freshness skip. Refreshes WFS advertised revisions separately from accepted evidence. Failed source reads persist failed attempts; earlier commits survive later errors. Returns no result. Example: CALL mirror.update_registered_sources(review=>true,skip_interval=>NULL);';

-- Explicit privilege boundaries override the broad initialization defaults in 902.
DO $$ DECLARE routine record; BEGIN
  FOR routine IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='mirror'
  LOOP
    EXECUTE format('REVOKE ALL ON ROUTINE %s FROM PUBLIC,uttdb_reader,uttdb_developer,uttdb_pipeline,uttdb_app_reader,uttdb_app_writer',routine.signature);
    EXECUTE format('GRANT EXECUTE ON ROUTINE %s TO uttdb_dba',routine.signature);
  END LOOP;
END $$;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA mirror TO uttdb_dba;
REVOKE UPDATE ON ALL SEQUENCES IN SCHEMA mirror FROM uttdb_pipeline;

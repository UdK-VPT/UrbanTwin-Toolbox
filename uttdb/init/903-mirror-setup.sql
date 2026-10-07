-- One row per mirrored layer. Creating this registry does not copy feature data.
CREATE TABLE IF NOT EXISTS mirror.registry (
  source_name text NOT NULL CHECK (btrim(source_name) <> ''),
  layer_name text NOT NULL CHECK (btrim(layer_name) <> ''),
  source_type text NOT NULL CHECK (btrim(source_type) <> ''),
  source_url text NOT NULL CHECK (btrim(source_url) <> ''),
  import_scope text NOT NULL CHECK (import_scope IN ('source', 'layer')),
  table_base text NOT NULL UNIQUE
    CHECK (btrim(table_base) <> '' AND octet_length(table_base) <= 56),
  stored_table text GENERATED ALWAYS AS (table_base || '_stored') STORED,
  registered_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_imported_at timestamptz,
  source_revision_at timestamptz,
  title text,
  description text,
  fees text,
  access_constraints text[],
  extent public.geometry(Geometry, 4326),
  PRIMARY KEY (source_name, layer_name),
  CHECK (last_imported_at IS NULL OR last_imported_at >= registered_at)
);

CREATE INDEX registry_extent_idx ON mirror.registry USING gist (extent);

COMMENT ON TABLE mirror.registry IS
  'One row per mirrored layer, grouped by source_name. Records source identity, selection scope, table names and successful storage imports. Registration alone does not mean data has been copied. Example: SELECT * FROM mirror.registry ORDER BY source_name, layer_name;';
COMMENT ON COLUMN mirror.registry.source_name IS 'Parent source identifier; also the foreign server name for OGR sources, or source view name for GeoTIFFs. Shared by all layers from that source.';
COMMENT ON COLUMN mirror.registry.layer_name IS 'Original layer name advertised by the source, including its namespace.';
COMMENT ON COLUMN mirror.registry.source_type IS 'Source adapter: wfs for remote WFS services, file for local vector datasets or GeoTIFF rasters.';
COMMENT ON COLUMN mirror.registry.source_url IS 'WFS service URL or absolute /source-files path for a file source. Shared source details must agree across its layer rows.';
COMMENT ON COLUMN mirror.registry.import_scope IS 'source: included through a whole-source import; layer: explicitly selected individually. Records selection intent, not refresh atomicity.';
COMMENT ON COLUMN mirror.registry.table_base IS 'Unqualified naming base in mirror for the _review and _stored tables. This also names the OGR foreign table or GeoTIFF source view. Unique and limited to 56 bytes so suffixes fit. A name records intent, not relation existence.';
COMMENT ON COLUMN mirror.registry.stored_table IS 'Unqualified persistent table name in mirror, derived with the _stored suffix. The storage implementation must check relation name collisions before creating it.';
COMMENT ON COLUMN mirror.registry.registered_at IS 'Time this layer was first registered here. Preserve on later imports; not an upstream creation date.';
COMMENT ON COLUMN mirror.registry.last_imported_at IS 'Time of last successful complete import into the stored table; NULL until first success. Update in the same transaction as data replacement, never on discovery or failed refresh.';
COMMENT ON COLUMN mirror.registry.source_revision_at IS 'Latest dataset revision reported by linked WFS ISO metadata (Stand), not feature validity or local import time. Date-only values use midnight UTC. Refreshed at registration and batch source checks, even when data import is skipped; may therefore be newer than stored data. NULL when unavailable or unsupported.';
COMMENT ON COLUMN mirror.registry.title IS 'Optional human-readable title supplied by source metadata; NULL when unavailable.';
COMMENT ON COLUMN mirror.registry.description IS 'Optional description supplied by source metadata; NULL when unavailable.';
COMMENT ON COLUMN mirror.registry.fees IS 'Published service-level Fees text, repeated for each layer. Preserved without interpreting it as a license identifier; NULL when absent.';
COMMENT ON COLUMN mirror.registry.access_constraints IS 'Published service-level AccessConstraints statements, one array entry per XML element; NULL when absent. Preserves wording and explicit NONE values without inferring dataset licensing.';

COMMENT ON COLUMN mirror.registry.extent IS 'Layer bounding geometry in EPSG:4326 for spatial discovery. Initially from WFS advertised geographic bounds or a scan of local vector/raster data; recalculated from the stored copy on publication. NULL for absent bounds, empty/nonspatial layers or unknown SRID. Includes raster NoData cells; not an exact coverage footprint.';

REVOKE ALL ON TABLE mirror.registry FROM PUBLIC, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT SELECT ON TABLE mirror.registry TO uttdb_reader, uttdb_developer, uttdb_pipeline;
GRANT ALL ON TABLE mirror.registry TO uttdb_dba;

-- Shared extent calculation for local registration and accepted data, never a WFS scan at registration.
CREATE OR REPLACE FUNCTION utt_pkg.mirror_layer_extent(layer_table regclass)
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

REVOKE ALL ON FUNCTION utt_pkg.mirror_layer_extent(regclass)
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON FUNCTION utt_pkg.mirror_layer_extent(regclass) TO uttdb_dba;
COMMENT ON FUNCTION utt_pkg.mirror_layer_extent(regclass) IS
  'DBA invoker-security helper for file registration and publication. Scans geometry columns and raster tile hulls, transforms known coordinates to EPSG:4326 and returns their bounding geometry without writing data. Returns NULL for empty/nonspatial relations or any nonempty geometry with unknown SRID; other transform errors propagate. Raster bounds include NoData cells. Requires SELECT on the relation. Example: SELECT utt_pkg.mirror_layer_extent(''mirror.buildings_stored''::regclass);';

-- Read each distinct metadata URL once; multiple layers often share one dataset.
CREATE OR REPLACE FUNCTION utt_pkg.mirror_wfs_revision_dates(
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

REVOKE ALL ON FUNCTION utt_pkg.mirror_wfs_revision_dates(text, xml)
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON FUNCTION utt_pkg.mirror_wfs_revision_dates(text, xml) TO uttdb_dba;
COMMENT ON FUNCTION utt_pkg.mirror_wfs_revision_dates(text, xml) IS
  'DBA invoker-security metadata reader used by WFS registration and batch refresh. Fetches capabilities unless supplied, follows each distinct first MetadataURL once, and returns each layer name with its latest ISO 19139 dataset citation revision timestamp. Date-only values become midnight UTC. Missing links or unsupported metadata/date fields yield NULL; HTTP, XML and timestamp errors abort. Writes nothing. Does not interpret revision as feature validity. Example: SELECT * FROM utt_pkg.mirror_wfs_revision_dates(''https://gdi.berlin.de/services/wfs/alkis'');';

-- Define all WFS layers as foreign tables. No local feature data is copied.
CREATE OR REPLACE FUNCTION utt_pkg.mirror_register_wfs_source(
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

  -- GDAL/OGR discovers the columns and geometry type; we do not infer them ourselves.
  EXECUTE format(
    'IMPORT FOREIGN SCHEMA ogr_all FROM SERVER %I INTO mirror
     OPTIONS (launder_table_names %L, launder_column_names %L)',
    p_server_name, 'false', 'false'
  );

  -- The foreign-table catalog retains the original OGR layer name. Register all
  -- layers atomically with discovery and the original published metadata.
  WITH revisions AS MATERIALIZED (
    SELECT * FROM utt_pkg.mirror_wfs_revision_dates(p_wfs_url, v_capabilities)
  )
  INSERT INTO mirror.registry (
    source_name, layer_name, source_type, source_url, import_scope, table_base,
    title, description, fees, access_constraints, source_revision_at, extent
  )
  SELECT p_server_name, layer.option_value, 'wfs', p_wfs_url, 'source', c.relname,
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
  WHERE s.srvname = p_server_name AND n.nspname = 'mirror'
    AND layer.option_name = 'layer';

  IF EXISTS (
    SELECT 1 FROM pg_foreign_table f
    JOIN pg_class c ON c.oid = f.ftrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_foreign_server s ON s.oid = f.ftserver
    WHERE s.srvname = p_server_name AND n.nspname = 'mirror'
      AND NOT EXISTS (SELECT 1 FROM mirror.registry r
                      WHERE r.source_name = p_server_name AND r.table_base = c.relname)
  ) THEN
    RAISE EXCEPTION 'A discovered layer has no matching capabilities metadata; registration rolled back.';
  END IF;

  RETURN QUERY
    SELECT c.oid::regclass
    FROM pg_foreign_table f
    JOIN pg_class c ON c.oid = f.ftrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_foreign_server s ON s.oid = f.ftserver
    WHERE s.srvname = p_server_name AND n.nspname = 'mirror'
    ORDER BY c.relname;
END;
$$;

-- Invoker security: the caller supplies its own schema and foreign-server privileges.
REVOKE ALL ON FUNCTION utt_pkg.mirror_register_wfs_source(text, text)
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline,
       uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON FUNCTION utt_pkg.mirror_register_wfs_source(text, text) TO uttdb_dba;
GRANT USAGE ON FOREIGN DATA WRAPPER ogr_fdw TO uttdb_dba;

COMMENT ON FUNCTION utt_pkg.mirror_register_wfs_source(text, text) IS
  'DBA helper: registers all advertised WFS layers as read-only ogr_fdw foreign tables and mirror.registry rows. Records source identity, whole-source selection, first registration and advertised geographic bounds in EPSG:4326 when available; derives _stored names. Published layer titles, abstracts and service-level fees/access constraints are preserved in their original language; absent elements remain NULL. HTTP, XML or layer-matching errors roll back registration. Last import remains NULL until feature storage. Returns foreign table names as regclass values. Registry name limits and relation collisions cause the whole call to roll back, including any newly created server. Linked ISO dataset revision dates populate source_revision_at. Repeated registration is not a refresh. Requires caller database/schema/server and registry-write privileges, normally uttdb_dba membership. Example: SELECT * FROM utt_pkg.mirror_register_wfs_source(''berlin_alkis'', ''https://gdi.berlin.de/services/wfs/alkis'');';

-- Manual example; not executed during initialization:
-- SELECT * FROM utt_pkg.mirror_register_wfs_source(
--   'berlin_alkis', 'https://gdi.berlin.de/services/wfs/alkis'
-- );
-- Creates one foreign table per layer, including mirror."alkis:bezirk".

-- One bounded file-read privilege boundary, shared by registration and source views.
-- GeoTIFF decoding is in-memory; tiles persist their pixels inside PostgreSQL.
CREATE OR REPLACE FUNCTION utt_pkg.mirror_read_geotiff(file_path text)
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

REVOKE ALL ON FUNCTION utt_pkg.mirror_read_geotiff(text)
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON FUNCTION utt_pkg.mirror_read_geotiff(text) TO uttdb_dba;
COMMENT ON FUNCTION utt_pkg.mirror_read_geotiff(text) IS
  'DBA-only security-definer file reader used by file registration and raster source views. Reads a trusted self-contained GeoTIFF below /source-files, decodes all pixels in memory and returns rid/rast tiles up to 256x256 with all bands, georeferencing and NoData retained. Writes nothing. Enables only GTiff locally; files larger than 256 MiB are rejected and decoded data must also fit memory. Requires the function owner to have server-file read permission; source files and symlinks must be administered by trusted DBAs. Example: SELECT rid, public.ST_Metadata(rast) FROM utt_pkg.mirror_read_geotiff(''/source-files/heat.tif'');';

-- Register vector layers through OGR, or a GeoTIFF as a lazy raster source view.
-- GeoTIFFs use their filename as layer_name and source_name as table_base.
CREATE OR REPLACE FUNCTION utt_pkg.mirror_register_file_source(
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
  IF EXISTS (SELECT FROM mirror.registry r WHERE r.source_name = mirror_register_file_source.source_name)
    OR EXISTS (SELECT FROM pg_foreign_server s WHERE s.srvname = mirror_register_file_source.source_name) THEN
    RAISE EXCEPTION 'Source/server % already exists; registration is not a refresh.', source_name;
  END IF;

  -- Minimal raster adapter: a single self-contained GeoTIFF, one registry layer.
  -- Other file formats retain the OGR vector path (including vector GeoPackages).
  IF driver = 'GTiff' OR (driver IS NULL AND file_path ~* '\.(tif|tiff)$') THEN
    IF open_options IS NOT NULL THEN
      RAISE EXCEPTION 'GeoTIFF open_options are not supported.';
    END IF;
    IF octet_length(source_name) > 56 THEN
      RAISE EXCEPTION 'Raster source name must not exceed 56 bytes.';
    END IF;
    raster_layer := regexp_replace(file_path, '^.*/', '');
    EXECUTE format(
      'CREATE VIEW mirror.%I WITH (security_invoker = true) AS
       SELECT rid, rast FROM utt_pkg.mirror_read_geotiff(%L)', source_name, file_path);
    EXECUTE format('COMMENT ON VIEW mirror.%I IS %L', source_name,
      format('Raster source %I.%I; read with utt_pkg.mirror_read_geotiff.', source_name, raster_layer));
    EXECUTE format('REVOKE ALL ON mirror.%I FROM PUBLIC, uttdb_reader, uttdb_developer,
      uttdb_pipeline, uttdb_app_reader, uttdb_app_writer', source_name);
    EXECUTE format('GRANT SELECT ON mirror.%I TO uttdb_dba', source_name);
    -- Decode and measure now; registration persists only the extent, not pixels.
    layer_extent := utt_pkg.mirror_layer_extent(to_regclass(format('mirror.%I', source_name)));
    INSERT INTO mirror.registry (source_name, layer_name, source_type, source_url, import_scope, table_base, extent)
    VALUES (source_name, raster_layer, 'file', file_path, 'source', source_name, layer_extent);
    RETURN NEXT to_regclass(format('mirror.%I', source_name));
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
  EXECUTE format(
    'IMPORT FOREIGN SCHEMA ogr_all FROM SERVER %I INTO mirror
     OPTIONS (launder_table_names %L, launder_column_names %L)', source_name, 'false', 'false');

  SELECT s.oid INTO server_oid FROM pg_foreign_server s
  WHERE s.srvname = mirror_register_file_source.source_name;
  FOR layer IN
    SELECT c.oid, c.relname, options.option_value AS original_name
    FROM pg_foreign_table f JOIN pg_class c ON c.oid = f.ftrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    CROSS JOIN LATERAL pg_options_to_table(f.ftoptions) options
    WHERE f.ftserver = server_oid AND n.nspname = 'mirror' AND options.option_name = 'layer'
    ORDER BY c.relname
  LOOP
    IF octet_length(layer.original_name) > 56 THEN
      RAISE EXCEPTION 'Layer name % exceeds 56 bytes; choose a shorter name in the source dataset.', layer.original_name;
    END IF;
    layer_extent := utt_pkg.mirror_layer_extent(layer.oid::regclass);
    INSERT INTO mirror.registry (source_name, layer_name, source_type, source_url, import_scope, table_base, extent)
    VALUES (source_name, layer.original_name, 'file', file_path, 'source', layer.relname, layer_extent);
    RETURN NEXT layer.oid::regclass;
  END LOOP;
  IF NOT EXISTS (SELECT FROM mirror.registry r WHERE r.source_name = mirror_register_file_source.source_name) THEN
    RAISE EXCEPTION 'Dataset has no importable vector layers; registration rolled back.';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION utt_pkg.mirror_register_file_source(text, text, text, text)
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON FUNCTION utt_pkg.mirror_register_file_source(text, text, text, text) TO uttdb_dba;
COMMENT ON FUNCTION utt_pkg.mirror_register_file_source(text, text, text, text) IS
  'DBA invoker-security registration: discovers all vector layers in a local dataset below /source-files using ogr_fdw, creates read-only source relations and source_type=file registry rows, and returns their regclass names. GeoTIFF (.tif/.tiff with no driver, or explicit GTiff) registers one source view named source_name and one layer named after the filename. It validates by decoding but persists no pixels; requires a self-contained file at most 256 MiB and no open_options. Other formats use OGR vector discovery. Registration scans file geometry/raster bounds into registry.extent in EPSG:4326 (NULL for unknown SRID or empty/nonspatial data). No source rows are stored until mirror_store_layer or the batch procedure runs. GDAL detects the driver unless supplied; open_options passes driver-specific options. Published metadata is left NULL because no generic metadata extraction is implemented. Unsupported/unreadable files, empty datasets, name collisions and layer names exceeding 56 bytes roll back the entire registration. Files remain untouched. Example: SELECT * FROM utt_pkg.mirror_register_file_source(''buildings'', ''/source-files/berlin/buildings.gpkg''); CSV: SELECT * FROM utt_pkg.mirror_register_file_source(''points'', ''/source-files/points.csv'', ''CSV'', ''X_POSSIBLE_NAMES=longitude Y_POSSIBLE_NAMES=latitude'');';

-- Per-layer storage: a complete candidate is published in the same transaction.
-- A _review suffix, like _stored, fits the registry's 56-byte name limit.
CREATE OR REPLACE FUNCTION utt_pkg.mirror_accept_layer(
  source_name text, layer_name text
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
DECLARE
  entry mirror.registry%ROWTYPE;
  candidate_name text;
  candidate_oid oid;
  stored_oid oid;
  foreign_oid oid;
  relation_oid oid;
  expected_columns text[];
  actual_columns text[];
  geometry_column record;
  invalid_raster boolean;
BEGIN
  -- This row lock serializes download and acceptance for the same layer.
  SELECT r.* INTO STRICT entry FROM mirror.registry r
  WHERE r.source_name = mirror_accept_layer.source_name
    AND r.layer_name = mirror_accept_layer.layer_name FOR UPDATE;
  candidate_name := entry.table_base || '_review';
  candidate_oid := to_regclass(format('mirror.%I', candidate_name));
  stored_oid := to_regclass(format('mirror.%I', entry.stored_table));
  foreign_oid := to_regclass(format('mirror.%I', entry.table_base));

  IF candidate_oid IS NULL OR NOT EXISTS (
    SELECT FROM pg_class WHERE oid = candidate_oid AND relkind = 'r'
      AND relpersistence = 'p'
      AND obj_description(oid, 'pg_class') = format(
        'Mirror review candidate for %I.%I; publish with utt_pkg.mirror_accept_layer.',
        entry.source_name, entry.layer_name)
  ) THEN
    RAISE EXCEPTION 'No recognized review candidate for %.%.', entry.source_name, entry.layer_name;
  END IF;
  IF NOT EXISTS (
    SELECT FROM pg_foreign_table f JOIN pg_foreign_server s ON s.oid = f.ftserver
    JOIN pg_foreign_data_wrapper w ON w.oid = s.srvfdw
    WHERE f.ftrelid = foreign_oid AND s.srvname = entry.source_name
      AND w.fdwname = 'ogr_fdw' AND entry.source_type IN ('wfs', 'file')
  ) AND NOT EXISTS (
    SELECT FROM pg_class WHERE oid = foreign_oid AND relkind = 'v'
      AND entry.source_type = 'file' AND obj_description(oid, 'pg_class') = format(
        'Raster source %I.%I; read with utt_pkg.mirror_read_geotiff.', entry.source_name, entry.layer_name)
  ) THEN
    RAISE EXCEPTION 'Registered source relation is missing or belongs to another source.';
  END IF;

  EXECUTE format('LOCK TABLE mirror.%I IN ACCESS EXCLUSIVE MODE', candidate_name);
  IF stored_oid IS NOT NULL THEN
    IF NOT EXISTS (SELECT FROM pg_class WHERE oid = stored_oid AND relkind = 'r'
      AND relpersistence = 'p' AND obj_description(oid, 'pg_class') = format(
        'Stored mirror layer %I.%I; maintained by utt_pkg.mirror_store_layer.',
        entry.source_name, entry.layer_name)) THEN
      RAISE EXCEPTION 'Storage name % is occupied by an unmanaged relation.', entry.stored_table;
    END IF;
    EXECUTE format('LOCK TABLE mirror.%I IN SHARE ROW EXCLUSIVE MODE', entry.stored_table);
  END IF;

  -- Compare ordered column names, types (including geometry SRID/type), and collations.
  SELECT array_agg(format('%s:%s:%s:%s', attname, atttypid, atttypmod, attcollation)
                   ORDER BY attnum) INTO expected_columns
  FROM pg_attribute WHERE attrelid = foreign_oid AND attnum > 0 AND NOT attisdropped;
  FOREACH relation_oid IN ARRAY ARRAY[candidate_oid, stored_oid] LOOP
    IF relation_oid IS NULL THEN CONTINUE; END IF;
    SELECT array_agg(format('%s:%s:%s:%s', attname, atttypid, atttypmod, attcollation)
                     ORDER BY attnum) INTO actual_columns
    FROM pg_attribute WHERE attrelid = relation_oid AND attnum > 0 AND NOT attisdropped;
    IF actual_columns IS DISTINCT FROM expected_columns THEN
      RAISE EXCEPTION 'Column layout changed; an explicit schema migration is required.';
    END IF;
  END LOOP;

  IF EXISTS (SELECT FROM pg_class WHERE oid = foreign_oid AND relkind = 'v') THEN
    EXECUTE format('SELECT EXISTS (SELECT FROM mirror.%I WHERE rid IS NULL OR rast IS NULL
      OR public.ST_Width(rast) < 1 OR public.ST_Height(rast) < 1 OR public.ST_NumBands(rast) < 1)
      OR EXISTS (SELECT FROM mirror.%I t,
        LATERAL public.ST_BandMetadata(t.rast, ARRAY[]::integer[]) b WHERE b.isoutdb)
      OR NOT EXISTS (SELECT FROM mirror.%I)', candidate_name, candidate_name, candidate_name)
      INTO invalid_raster;
    IF invalid_raster THEN
      RAISE EXCEPTION 'Raster candidate must contain nonempty in-database tiles with IDs.';
    END IF;
  END IF;

  IF stored_oid IS NULL THEN
    EXECUTE format('ALTER TABLE mirror.%I RENAME TO %I', candidate_name, entry.stored_table);
  ELSE
    -- DELETE preserves MVCC visibility for older readers, unlike TRUNCATE.
    EXECUTE format('DELETE FROM mirror.%I', entry.stored_table);
    EXECUTE format('INSERT INTO mirror.%I SELECT * FROM mirror.%I', entry.stored_table, candidate_name);
    EXECUTE format('DROP TABLE mirror.%I', candidate_name);
  END IF;
  -- Index published geometry columns, including older stored tables without indexes.
  -- Inspect definitions rather than names; PostgreSQL chooses collision-safe names.
  stored_oid := to_regclass(format('mirror.%I', entry.stored_table));
  FOR geometry_column IN
    SELECT attname, attnum FROM pg_attribute
    WHERE attrelid = stored_oid AND attnum > 0 AND NOT attisdropped
      AND atttypid = 'public.geometry'::regtype
  LOOP
    IF NOT EXISTS (
      SELECT FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      JOIN pg_am am ON am.oid = c.relam
      WHERE i.indrelid = stored_oid AND i.indisvalid AND i.indisready
        AND i.indpred IS NULL AND i.indexprs IS NULL
        AND i.indnkeyatts = 1 AND i.indkey[0] = geometry_column.attnum
        AND am.amname = 'gist'
        AND i.indclass[0] = (SELECT oid FROM pg_opclass
          WHERE opcnamespace = 'public'::regnamespace AND opcname = 'gist_geometry_ops_2d')
    ) THEN
      EXECUTE format('CREATE INDEX ON mirror.%I USING gist (%I public.gist_geometry_ops_2d)',
                     entry.stored_table, geometry_column.attname);
    END IF;
  END LOOP;
  IF EXISTS (SELECT FROM pg_class WHERE oid = foreign_oid AND relkind = 'v') THEN
    -- A primary key makes tile identity usable by GIS clients and rejects duplicates.
    IF NOT EXISTS (SELECT FROM pg_constraint WHERE conrelid = stored_oid AND contype = 'p') THEN
      EXECUTE format('ALTER TABLE mirror.%I ADD PRIMARY KEY (rid)', entry.stored_table);
    END IF;
    IF NOT EXISTS (
      SELECT FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
      JOIN pg_am am ON am.oid = c.relam
      WHERE i.indrelid = stored_oid AND i.indisvalid AND i.indisready
        AND i.indpred IS NULL AND am.amname = 'gist'
        AND pg_get_expr(i.indexprs, i.indrelid) = 'public.st_convexhull(rast)'
    ) THEN
      EXECUTE format('CREATE INDEX ON mirror.%I USING gist (public.ST_ConvexHull(rast))', entry.stored_table);
    END IF;
  END IF;
  EXECUTE format('ANALYZE mirror.%I', entry.stored_table);
  EXECUTE format('COMMENT ON TABLE mirror.%I IS %L', entry.stored_table, format(
    'Stored mirror layer %I.%I; maintained by utt_pkg.mirror_store_layer.', entry.source_name, entry.layer_name));
  UPDATE mirror.registry r SET last_imported_at = clock_timestamp(),
    extent = utt_pkg.mirror_layer_extent(stored_oid::regclass)
  WHERE r.source_name = entry.source_name AND r.layer_name = entry.layer_name;
END;
$$;

CREATE OR REPLACE FUNCTION utt_pkg.mirror_store_layer(
  source_name text, layer_name text, review boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
DECLARE
  entry mirror.registry%ROWTYPE;
  candidate_name text;
  stored_oid oid;
  foreign_oid oid;
  count_expressions text;
  column_names text[];
  old_counts bigint[];
  new_counts bigint[];
  failures text[] := ARRAY[]::text[];
  i integer;
  raster_changed boolean;
BEGIN
  IF review IS NULL THEN RAISE EXCEPTION 'review must be true or false.'; END IF;
  SELECT r.* INTO STRICT entry FROM mirror.registry r
  WHERE r.source_name = mirror_store_layer.source_name
    AND r.layer_name = mirror_store_layer.layer_name FOR UPDATE;
  candidate_name := entry.table_base || '_review';
  stored_oid := to_regclass(format('mirror.%I', entry.stored_table));
  foreign_oid := to_regclass(format('mirror.%I', entry.table_base));
  IF NOT EXISTS (
    SELECT FROM pg_foreign_table f JOIN pg_foreign_server s ON s.oid = f.ftserver
    JOIN pg_foreign_data_wrapper w ON w.oid = s.srvfdw
    WHERE f.ftrelid = foreign_oid AND s.srvname = entry.source_name
      AND w.fdwname = 'ogr_fdw' AND entry.source_type IN ('wfs', 'file')
  ) AND NOT EXISTS (
    SELECT FROM pg_class WHERE oid = foreign_oid AND relkind = 'v'
      AND entry.source_type = 'file' AND obj_description(oid, 'pg_class') = format(
        'Raster source %I.%I; read with utt_pkg.mirror_read_geotiff.', entry.source_name, entry.layer_name)
  ) THEN
    RAISE EXCEPTION 'Registered source relation is missing or belongs to another source.';
  END IF;
  IF to_regclass(format('mirror.%I', candidate_name)) IS NOT NULL THEN
    RAISE EXCEPTION 'Relation mirror.% already exists; accept or explicitly drop the review candidate first.', candidate_name;
  END IF;
  IF stored_oid IS NOT NULL THEN
    IF NOT EXISTS (SELECT FROM pg_class WHERE oid = stored_oid AND relkind = 'r'
      AND relpersistence = 'p' AND obj_description(oid, 'pg_class') = format(
        'Stored mirror layer %I.%I; maintained by utt_pkg.mirror_store_layer.',
        entry.source_name, entry.layer_name)) THEN
      RAISE EXCEPTION 'Storage name % is occupied by an unmanaged relation.', entry.stored_table;
    END IF;
    EXECUTE format('LOCK TABLE mirror.%I IN SHARE ROW EXCLUSIVE MODE', entry.stored_table);
    IF EXISTS (
      SELECT FROM (
        (SELECT attnum, attname, atttypid, atttypmod, attcollation
         FROM pg_attribute WHERE attrelid = foreign_oid AND attnum > 0 AND NOT attisdropped
         EXCEPT
         SELECT attnum, attname, atttypid, atttypmod, attcollation
         FROM pg_attribute WHERE attrelid = stored_oid AND attnum > 0 AND NOT attisdropped)
        UNION ALL
        (SELECT attnum, attname, atttypid, atttypmod, attcollation
         FROM pg_attribute WHERE attrelid = stored_oid AND attnum > 0 AND NOT attisdropped
         EXCEPT
         SELECT attnum, attname, atttypid, atttypmod, attcollation
         FROM pg_attribute WHERE attrelid = foreign_oid AND attnum > 0 AND NOT attisdropped)
      ) differences
    ) THEN
      RAISE EXCEPTION 'Column layout changed; an explicit schema migration is required.';
    END IF;
  END IF;

  -- CTAS preserves the exposed column types and values, without copying defaults,
  -- constraints or triggers that could modify downloaded values.
  EXECUTE format('CREATE TABLE mirror.%I AS SELECT * FROM mirror.%I', candidate_name, entry.table_base);
  EXECUTE format('COMMENT ON TABLE mirror.%I IS %L', candidate_name, format(
    'Mirror review candidate for %I.%I; publish with utt_pkg.mirror_accept_layer.', entry.source_name, entry.layer_name));
  EXECUTE format('REVOKE ALL ON TABLE mirror.%I FROM PUBLIC, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer', candidate_name);
  EXECUTE format('GRANT SELECT ON TABLE mirror.%I TO uttdb_reader, uttdb_developer, uttdb_pipeline', candidate_name);
  EXECUTE format('GRANT ALL ON TABLE mirror.%I TO uttdb_dba', candidate_name);
  EXECUTE format('ALTER TABLE mirror.%I OWNER TO uttdb_dba', candidate_name);

  IF stored_oid IS NOT NULL THEN
    -- One aggregate scan per local table counts rows and NULLs in every column.
    SELECT string_agg(format('count(*) - count(%I)', attname), ', ' ORDER BY attnum),
           array_agg(attname::text ORDER BY attnum)
    INTO count_expressions, column_names
    FROM pg_attribute WHERE attrelid = foreign_oid AND attnum > 0 AND NOT attisdropped;
    EXECUTE format('SELECT ARRAY[count(*), %s] FROM mirror.%I', count_expressions, entry.stored_table) INTO old_counts;
    EXECUTE format('SELECT ARRAY[count(*), %s] FROM mirror.%I', count_expressions, candidate_name) INTO new_counts;
    FOR i IN 1..cardinality(old_counts) LOOP
      -- Numeric arithmetic avoids rounding and bigint overflow. Zero must stay zero.
      IF abs(new_counts[i]::numeric - old_counts[i]) * 100 > old_counts[i]::numeric THEN
        failures := array_append(failures, format('%s: %s -> %s',
          CASE WHEN i = 1 THEN 'rows' ELSE format('NULLs in %I', column_names[i - 1]) END,
          old_counts[i], new_counts[i]));
      END IF;
    END LOOP;
  END IF;
  IF stored_oid IS NOT NULL AND EXISTS (
    SELECT FROM pg_class WHERE oid = foreign_oid AND relkind = 'v'
  ) THEN
    -- Compare every tile's grid and bands. A moved/resized grid needs manual review.
    EXECUTE format('SELECT EXISTS (
      SELECT FROM mirror.%I old FULL JOIN mirror.%I new USING (rid)
      WHERE old.rid IS NULL OR new.rid IS NULL
        OR public.ST_Metadata(old.rast) IS DISTINCT FROM public.ST_Metadata(new.rast)
        OR ARRAY(SELECT (b.pixeltype, b.nodatavalue)::text FROM
             public.ST_BandMetadata(old.rast, ARRAY[]::integer[]) b ORDER BY b.bandnum)
           IS DISTINCT FROM
           ARRAY(SELECT (b.pixeltype, b.nodatavalue)::text FROM
             public.ST_BandMetadata(new.rast, ARRAY[]::integer[]) b ORDER BY b.bandnum))',
      entry.stored_table, candidate_name) INTO raster_changed;
    IF raster_changed THEN
      failures := array_append(failures, 'raster grid, SRID, extent or band metadata changed');
    ELSE
      -- Per-band valid-pixel counts catch changes hidden by unchanged tile counts.
      EXECUTE format('WITH old AS (
        SELECT band, sum(public.ST_Count(rast, band, true)) AS pixels
        FROM mirror.%I CROSS JOIN LATERAL generate_series(1, public.ST_NumBands(rast)) band
        GROUP BY band), new AS (
        SELECT band, sum(public.ST_Count(rast, band, true)) AS pixels
        FROM mirror.%I CROSS JOIN LATERAL generate_series(1, public.ST_NumBands(rast)) band
        GROUP BY band)
        SELECT EXISTS (SELECT FROM old JOIN new USING (band)
          WHERE abs(new.pixels - old.pixels) * 100 > old.pixels)',
        entry.stored_table, candidate_name) INTO raster_changed;
      IF raster_changed THEN
        failures := array_append(failures, 'raster valid-pixel counts changed by more than 1 percent');
      END IF;
    END IF;
  END IF;
  IF cardinality(failures) > 0 THEN
    IF NOT review THEN
      RAISE EXCEPTION 'Changes exceed +/-1%%: %. Retry with review => true for manual inspection.', array_to_string(failures, '; ');
    END IF;
    RAISE NOTICE 'Changes exceed +/-1%%: %', array_to_string(failures, '; ');
  END IF;
  IF review THEN
    RAISE NOTICE 'Candidate mirror.% is ready for review; stored data and import date are unchanged.', candidate_name;
  ELSE
    PERFORM utt_pkg.mirror_accept_layer(entry.source_name, entry.layer_name);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION utt_pkg.mirror_store_layer(text, text, boolean),
  utt_pkg.mirror_accept_layer(text, text)
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON FUNCTION utt_pkg.mirror_store_layer(text, text, boolean),
  utt_pkg.mirror_accept_layer(text, text) TO uttdb_dba;

COMMENT ON FUNCTION utt_pkg.mirror_store_layer(text, text, boolean) IS
  'DBA invoker-security operation: copies one registered WFS or file layer, preserving exposed columns and rows. GeoTIFF views produce in-database rid/rast tiles. Raster automatic publication also requires unchanged tile georeferencing and band metadata, and per-band valid-pixel counts within 1 percent; review=true permits explicit approval of changes. Default publication requires row and per-column NULL counts within +/-1% of stored counts; zero must stay zero. First import has no baseline. Returns void. Errors roll back download and publication. review=true retains a persistent _review candidate, reports count failures, and leaves stored data/import date unchanged. Existing candidates are never overwritten. Example: SELECT utt_pkg.mirror_store_layer(''berlin_alkis'', ''alkis:bezirk'', review => true);';
COMMENT ON FUNCTION utt_pkg.mirror_accept_layer(text, text) IS
  'DBA invoker-security approval: publishes a completed _review candidate without count thresholds. Requires compatible columns; preserves an existing stored table object and its privileges, replaces all rows, removes the candidate, ensures a full 2D GiST index per geometry column (or raster tile footprint index and rid primary key), rejects empty or out-of-database raster candidates, runs ANALYZE and sets last_imported_at and the EPSG:4326 registry extent atomically. Returns void; errors preserve prior state. Also called by automatic storage after safety checks. Example after manual inspection: SELECT utt_pkg.mirror_accept_layer(''berlin_alkis'', ''alkis:bezirk'');';

-- One entry point for all registered layers; add adapters here when implemented.
CREATE OR REPLACE PROCEDURE utt_pkg.mirror_update_registered_sources(
  review boolean DEFAULT false, source_type text DEFAULT NULL,
  skip_interval interval DEFAULT interval '1 hour'
)
LANGUAGE plpgsql
SECURITY INVOKER
-- No routine SET clause: PostgreSQL forbids transaction control with one.
-- Relations and routine calls are schema-qualified instead.
AS $$
DECLARE
  selected_layer record;
  entry mirror.registry%ROWTYPE;
  checked_source text;
BEGIN
  IF skip_interval < interval '0' THEN
    RAISE EXCEPTION 'skip_interval must be nonnegative or NULL to disable skipping.';
  END IF;
  IF review IS NULL THEN RAISE EXCEPTION 'review must be true or false.'; END IF;
  IF source_type IS NOT NULL AND source_type NOT IN ('wfs', 'file') THEN
    RAISE EXCEPTION 'Unsupported batch source type: %. Supported types are wfs and file.', source_type;
  END IF;
  IF EXISTS (SELECT FROM mirror.registry r
    WHERE (mirror_update_registered_sources.source_type IS NULL
           OR r.source_type = mirror_update_registered_sources.source_type)
      AND r.source_type NOT IN ('wfs', 'file')) THEN
    RAISE EXCEPTION 'Registry contains unknown source types; the batch supports wfs and file.';
  END IF;

  -- This read-only cursor retains the selected keys across per-layer commits.
  -- Lock and re-read each row separately so concurrent runs see committed imports.
  FOR selected_layer IN
    SELECT r.source_name, r.layer_name, r.source_type, r.source_url FROM mirror.registry r
    WHERE r.source_type IN ('wfs', 'file')
      AND (mirror_update_registered_sources.source_type IS NULL
           OR r.source_type = mirror_update_registered_sources.source_type)
    ORDER BY r.source_name, r.layer_name
  LOOP
    -- Check remote revision metadata once per source, including recently imported
    -- layers. This timestamp describes the latest advertised source, not storage.
    IF selected_layer.source_type = 'wfs'
      AND checked_source IS DISTINCT FROM selected_layer.source_name THEN
      WITH revisions AS MATERIALIZED (
        SELECT * FROM utt_pkg.mirror_wfs_revision_dates(selected_layer.source_url)
      )
      UPDATE mirror.registry r SET source_revision_at = (
        SELECT d.source_revision_at FROM revisions d WHERE d.layer_name = r.layer_name
      )
      WHERE r.source_name = selected_layer.source_name AND r.source_type = 'wfs';
      checked_source := selected_layer.source_name;
    END IF;
    SELECT r.* INTO entry FROM mirror.registry r
    WHERE r.source_name = selected_layer.source_name
      AND r.layer_name = selected_layer.layer_name
      AND r.source_type IN ('wfs', 'file')
      AND (mirror_update_registered_sources.source_type IS NULL
           OR r.source_type = mirror_update_registered_sources.source_type)
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE NOTICE 'Skipping %.%: no longer selected.', selected_layer.source_name, selected_layer.layer_name;
    ELSIF skip_interval IS NOT NULL AND skip_interval > interval '0'
      AND entry.last_imported_at >= pg_catalog.clock_timestamp() - skip_interval THEN
      RAISE NOTICE 'Skipping %.%: imported within %.', entry.source_name, entry.layer_name, skip_interval;
    ELSE
      RAISE NOTICE 'Updating %.% (%)', entry.source_name, entry.layer_name, entry.source_type;
      CASE entry.source_type
        WHEN 'wfs', 'file' THEN
          PERFORM utt_pkg.mirror_store_layer(entry.source_name, entry.layer_name, review);
        ELSE
          RAISE EXCEPTION 'Unsupported source type: %.', entry.source_type;
      END CASE;
    END IF;
    -- Release this layer's locks and make its data/date (or review candidate) durable.
    -- An error stops the run; earlier commits survive, the failing layer rolls back.
    COMMIT;
  END LOOP;
END;
$$;

REVOKE ALL ON PROCEDURE utt_pkg.mirror_update_registered_sources(boolean, text, interval)
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON PROCEDURE utt_pkg.mirror_update_registered_sources(boolean, text, interval) TO uttdb_dba;
COMMENT ON PROCEDURE utt_pkg.mirror_update_registered_sources(boolean, text, interval) IS
  'DBA invoker-security batch: CALL at top level with autocommit enabled, outside BEGIN/COMMIT. Updates registered WFS/file layers in source/layer order and commits each completed layer independently. source_type=NULL selects wfs/file; wfs or file selects that type only. Refreshes linked WFS dataset revision dates once per source even when layer imports are skipped; metadata errors stop the batch. Skips layers successfully published within skip_interval (default 1 hour) using last_imported_at, rechecked under a row lock. NULL or zero skip_interval disables skipping; negative intervals are rejected. Normal layer safety checks apply; review=true commits candidates without advancing last_imported_at. Pending candidates still require acceptance or explicit removal. Errors stop the run and roll back only the current layer; earlier commits survive. Reruns skip recent successes. No new layers are discovered and no result is returned. Example: CALL utt_pkg.mirror_update_registered_sources(); WFS only: CALL utt_pkg.mirror_update_registered_sources(source_type => ''wfs''); No freshness skip: CALL utt_pkg.mirror_update_registered_sources(skip_interval => NULL); Manual review: CALL utt_pkg.mirror_update_registered_sources(review => true);';


-- Remove one registered mirror layer, or all layers when layer_name is omitted.
CREATE OR REPLACE FUNCTION utt_pkg.mirror_unregister_source(
  source_name text, layer_name text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
DECLARE
  entry mirror.registry%ROWTYPE;
  server_oid oid;
  table_name text;
  table_oid oid;
  expected_comment text;
BEGIN
  -- Lock all layers of this source in a stable order, including when removing one.
  -- This serializes competing removals and coordinates with storage/publication.
  PERFORM 1 FROM mirror.registry r
  WHERE r.source_name = mirror_unregister_source.source_name
  ORDER BY r.layer_name FOR UPDATE;
  IF NOT EXISTS (SELECT FROM mirror.registry r
    WHERE r.source_name = mirror_unregister_source.source_name
      AND (mirror_unregister_source.layer_name IS NULL
           OR r.layer_name = mirror_unregister_source.layer_name)) THEN
    RAISE EXCEPTION 'No registered layer matches source % and layer %.', source_name, layer_name;
  END IF;
  IF EXISTS (SELECT FROM mirror.registry r
    WHERE r.source_name = mirror_unregister_source.source_name AND r.source_type NOT IN ('wfs', 'file')) THEN
    RAISE EXCEPTION 'Source % contains unsupported registry entries.', source_name;
  END IF;
  SELECT s.oid INTO server_oid FROM pg_foreign_server s
  JOIN pg_foreign_data_wrapper w ON w.oid = s.srvfdw
  WHERE s.srvname = mirror_unregister_source.source_name AND w.fdwname = 'ogr_fdw';
  IF EXISTS (
    SELECT FROM mirror.registry r JOIN pg_class c
      ON c.oid = to_regclass(format('mirror.%I', r.table_base))
    WHERE r.source_name = mirror_unregister_source.source_name AND r.source_type = 'file'
      AND c.relkind = 'v' AND obj_description(c.oid, 'pg_class') = format(
        'Raster source %I.%I; read with utt_pkg.mirror_read_geotiff.', r.source_name, r.layer_name)
  ) THEN
    server_oid := NULL; -- Raster registration owns no foreign server.
  ELSIF server_oid IS NULL THEN
    RAISE EXCEPTION 'Expected OGR foreign server % is missing or has another wrapper.', source_name;
  END IF;

  FOR entry IN SELECT r.* FROM mirror.registry r
    WHERE r.source_name = mirror_unregister_source.source_name
      AND (mirror_unregister_source.layer_name IS NULL
           OR r.layer_name = mirror_unregister_source.layer_name)
    ORDER BY r.layer_name
  LOOP
    -- Names alone are insufficient: refuse unrelated tables occupying these names.
    FOREACH table_name IN ARRAY ARRAY[entry.table_base || '_review', entry.stored_table] LOOP
      table_oid := to_regclass(format('mirror.%I', table_name));
      IF table_oid IS NULL THEN CONTINUE; END IF;
      expected_comment := CASE WHEN table_name = entry.stored_table THEN format(
        'Stored mirror layer %I.%I; maintained by utt_pkg.mirror_store_layer.', entry.source_name, entry.layer_name)
      ELSE format(
        'Mirror review candidate for %I.%I; publish with utt_pkg.mirror_accept_layer.', entry.source_name, entry.layer_name)
      END;
      IF NOT EXISTS (SELECT FROM pg_class WHERE oid = table_oid AND relkind = 'r'
        AND relpersistence = 'p' AND obj_description(oid, 'pg_class') = expected_comment) THEN
        RAISE EXCEPTION 'Refusing to remove unmanaged relation mirror.%.', table_name;
      END IF;
      EXECUTE format('DROP TABLE mirror.%I RESTRICT', table_name);
    END LOOP;

    table_oid := to_regclass(format('mirror.%I', entry.table_base));
    IF table_oid IS NOT NULL THEN
      IF EXISTS (SELECT FROM pg_class WHERE oid = table_oid AND relkind = 'v'
        AND entry.source_type = 'file' AND obj_description(oid, 'pg_class') = format(
          'Raster source %I.%I; read with utt_pkg.mirror_read_geotiff.', entry.source_name, entry.layer_name)) THEN
        EXECUTE format('DROP VIEW mirror.%I RESTRICT', entry.table_base);
      ELSE
        IF NOT EXISTS (SELECT FROM pg_foreign_table f WHERE f.ftrelid = table_oid
          AND f.ftserver = server_oid) THEN
          RAISE EXCEPTION 'Foreign table mirror.% does not belong to source %.', entry.table_base, source_name;
        END IF;
        EXECUTE format('DROP FOREIGN TABLE mirror.%I RESTRICT', entry.table_base);
      END IF;
    END IF;
    DELETE FROM mirror.registry r
    WHERE r.source_name = entry.source_name AND r.layer_name = entry.layer_name;
  END LOOP;

  IF server_oid IS NOT NULL AND NOT EXISTS (SELECT FROM mirror.registry r
    WHERE r.source_name = mirror_unregister_source.source_name) THEN
    -- Unregistered foreign tables or other dependencies must be resolved explicitly.
    EXECUTE format('DROP SERVER %I RESTRICT', source_name);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION utt_pkg.mirror_unregister_source(text, text)
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON FUNCTION utt_pkg.mirror_unregister_source(text, text) TO uttdb_dba;
COMMENT ON FUNCTION utt_pkg.mirror_unregister_source(text, text) IS
  'Destructive DBA invoker-security operation: removes a registered WFS/file source or one of its layers. Leaves source files untouched. Deletes managed review/stored tables, foreign tables or raster source views, and registry rows. Removes the OGR server after its last registered layer. Missing local tables are tolerated; unmanaged relations, unknown selections and dependencies raise errors. Uses RESTRICT; any error rolls back the whole call. Requires object ownership. Returns void. Examples: SELECT utt_pkg.mirror_unregister_source(''berlin_alkis'', ''alkis:bezirk''); SELECT utt_pkg.mirror_unregister_source(''berlin_alkis'');';

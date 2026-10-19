-- Curation starts from accepted local mirror data, never from a live WFS query.
-- ALKIS land has no feature validity date; use its source-reported revision.
CREATE FUNCTION utt_pkg.curate_city()
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
DECLARE
  source_city record;
  current_city utt.city%ROWTYPE;
  validity_start timestamptz;
  recorded_at timestamptz;
  content_changed boolean;
BEGIN
  -- Do not accept a caller-supplied date: temporal metadata must be source-backed.
  SELECT r.source_revision_at INTO STRICT validity_start
  FROM mirror.registry r
  WHERE r.source_name = 'berlin_alkis' AND r.layer_name = 'alkis:land'
    AND r.last_imported_at IS NOT NULL
  FOR SHARE;
  IF validity_start IS NULL OR NOT isfinite(validity_start) THEN
    RAISE EXCEPTION 'The stored berlin_alkis.alkis:land layer has no finite source revision date.';
  END IF;
  -- Serialize competing city writes; the SELECT below reads one source snapshot.
  LOCK TABLE utt.city IN SHARE ROW EXCLUSIVE MODE;

  -- Berlin is both a city and a federal state; lan is its official state code.
  SELECT lan::bigint AS id, namlan AS name, geom
    INTO STRICT source_city FROM mirror."alkis:land_stored";

  SELECT * INTO current_city FROM utt.city
  WHERE city_id_official = source_city.id AND upper_inf(utt_txn);
  IF FOUND THEN
    IF current_city.source_valid IS NULL THEN
      RAISE EXCEPTION 'Current city % has no source-valid range.', source_city.id;
    END IF;

    content_changed := current_city.name IS DISTINCT FROM source_city.name
      OR public.ST_AsEWKB(current_city.geom) IS DISTINCT FROM public.ST_AsEWKB(source_city.geom);
    IF NOT content_changed THEN
      -- A new advertised revision alone does not create a UTT version.
      RETURN 0;
    END IF;

    IF validity_start < lower(current_city.source_valid) THEN
      RAISE EXCEPTION 'Changed city data has source revision %, before current revision %.',
        validity_start, lower(current_city.source_valid);
    END IF;

    recorded_at := clock_timestamp();
    UPDATE utt.city
    SET source_valid = CASE WHEN validity_start > lower(source_valid)
          THEN tstzrange(lower(source_valid), validity_start, '[)')
          ELSE source_valid END,
        utt_txn = tstzrange(lower(utt_txn), recorded_at, '[)')
    WHERE row_id = current_city.row_id;
  ELSE
    recorded_at := clock_timestamp();
  END IF;

  INSERT INTO utt.city (city_id_official, name, geom, source_valid, utt_txn)
  VALUES (source_city.id, source_city.name, source_city.geom,
          tstzrange(validity_start, NULL, '[)'),
          tstzrange(recorded_at, NULL, '[)'));
  RETURN 1;
END;
$$;

REVOKE ALL ON FUNCTION utt_pkg.curate_city()
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON FUNCTION utt_pkg.curate_city() TO uttdb_dba, uttdb_pipeline;
COMMENT ON FUNCTION utt_pkg.curate_city() IS
  'DBA/pipeline invoker-security curation of Berlin from mirror."alkis:land_stored" into utt.city: lan becomes the stable city_id_official, namlan becomes name, geometry retains its source CRS, and each version receives an internal row_id. Requires exactly one source row and a successfully imported registry entry with a finite source_revision_at. No temporal input is accepted from the caller. The first import opens source_valid at the source revision and utt_txn at insertion. Name or geometry changes close the current utt_txn and insert a new version; a newer revision also closes source_valid at that revision, while unchanged revision metadata is retained for content-only corrections. A revision change without a content change returns 0 and leaves the current version untouched. An insert or content change returns 1; a content change with an older revision raises an error. Requires registry/source SELECT and target SELECT/INSERT/UPDATE plus row/table-lock privileges. Example: SELECT utt_pkg.curate_city();';

-- ALKIS district has no feature validity date; use its source-reported revision.
CREATE FUNCTION utt_pkg.curate_district()
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
DECLARE
  source_district record;
  current_district utt.district%ROWTYPE;
  validity_start timestamptz;
  recorded_at timestamptz;
  content_changed boolean;
  inserted_count integer := 0;
BEGIN
  SELECT r.source_revision_at INTO STRICT validity_start
  FROM mirror.registry r
  WHERE r.source_name = 'berlin_alkis' AND r.layer_name = 'alkis:bezirk'
    AND r.last_imported_at IS NOT NULL
  FOR SHARE;
  IF validity_start IS NULL OR NOT isfinite(validity_start) THEN
    RAISE EXCEPTION 'The stored berlin_alkis.alkis:bezirk layer has no finite source revision date.';
  END IF;

  LOCK TABLE utt.district IN SHARE ROW EXCLUSIVE MODE;
  recorded_at := clock_timestamp();

  IF NOT EXISTS (SELECT FROM mirror."alkis:bezirk_stored") THEN
    RAISE EXCEPTION 'Stored berlin_alkis.alkis:bezirk contains no districts.';
  END IF;
  IF EXISTS (
    SELECT FROM mirror."alkis:bezirk_stored"
    WHERE name IS NULL OR name !~ '^[0-9]+$'
      OR namgem IS NULL OR btrim(namgem) = ''
      OR geom IS NULL OR public.ST_IsEmpty(geom)
  ) THEN
    RAISE EXCEPTION 'Stored districts require a numeric name ID, nonempty namgem and nonempty geometry.';
  END IF;
  IF EXISTS (
    SELECT FROM mirror."alkis:bezirk_stored" GROUP BY name HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Stored districts contain duplicate stable name IDs.';
  END IF;

  FOR source_district IN
    SELECT name::bigint AS dist_id, namgem AS name, geom
    FROM mirror."alkis:bezirk_stored"
    ORDER BY name::bigint
  LOOP
    SELECT * INTO current_district FROM utt.district
    WHERE district_id_official = source_district.dist_id AND upper_inf(utt_txn);

    IF FOUND THEN
      IF current_district.source_valid IS NULL THEN
        RAISE EXCEPTION 'Current district % has no source-valid range.', source_district.dist_id;
      END IF;

      content_changed := current_district.name IS DISTINCT FROM source_district.name
        OR public.ST_AsEWKB(current_district.geom) IS DISTINCT FROM public.ST_AsEWKB(source_district.geom);
      IF NOT content_changed THEN
        CONTINUE;
      END IF;

      IF validity_start < lower(current_district.source_valid) THEN
        RAISE EXCEPTION 'Changed district % has source revision %, before current revision %.',
          source_district.dist_id, validity_start, lower(current_district.source_valid);
      END IF;

      UPDATE utt.district
      SET source_valid = CASE WHEN validity_start > lower(source_valid)
            THEN tstzrange(lower(source_valid), validity_start, '[)')
            ELSE source_valid END,
          utt_txn = tstzrange(lower(utt_txn), recorded_at, '[)')
      WHERE row_id = current_district.row_id;
    END IF;

    INSERT INTO utt.district (district_id_official, name, geom, source_valid, utt_txn)
    VALUES (source_district.dist_id, source_district.name, source_district.geom,
            tstzrange(validity_start, NULL, '[)'),
            tstzrange(recorded_at, NULL, '[)'));
    inserted_count := inserted_count + 1;
  END LOOP;

  RETURN inserted_count;
END;
$$;

REVOKE ALL ON FUNCTION utt_pkg.curate_district()
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON FUNCTION utt_pkg.curate_district() TO uttdb_dba, uttdb_pipeline;
COMMENT ON FUNCTION utt_pkg.curate_district() IS
  'DBA/pipeline invoker-security curation of Berlin districts from mirror."alkis:bezirk_stored" into utt.district: numeric source name becomes the stable district_id_official, namgem becomes name, geometry retains its source CRS, and each version receives an internal row_id. Requires a successfully imported registry entry with a finite source_revision_at. No temporal input is accepted from the caller. The first import opens source_valid at the source revision and utt_txn at insertion. Name or geometry changes create versions under the shared temporal curation model; a revision change without a content change leaves the current version untouched. Returns the number of inserted district versions, including first imports. Missing source objects are not closed or deleted. Requires registry/source SELECT and target SELECT/INSERT/UPDATE plus row/table-lock privileges. Example: SELECT utt_pkg.curate_district();';

-- The ALKIS building layer has no feature validity date; use its source-reported revision.
CREATE FUNCTION utt_pkg.curate_building()
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
DECLARE
  source_building record;
  current_building utt.building%ROWTYPE;
  validity_start timestamptz;
  recorded_at timestamptz;
  content_changed boolean;
  inserted_count integer := 0;
BEGIN
  SELECT r.source_revision_at INTO STRICT validity_start
  FROM mirror.registry r
  WHERE r.source_name = 'berlin_alkis_gebaeude'
    AND r.layer_name = 'alkis_gebaeude:gebaeude'
    AND r.last_imported_at IS NOT NULL
  FOR SHARE;
  IF validity_start IS NULL OR NOT isfinite(validity_start) THEN
    RAISE EXCEPTION 'The stored berlin_alkis_gebaeude.alkis_gebaeude:gebaeude layer has no finite source revision date.';
  END IF;

  LOCK TABLE utt.building IN SHARE ROW EXCLUSIVE MODE;
  recorded_at := clock_timestamp();

  IF NOT EXISTS (SELECT FROM mirror."alkis_gebaeude:gebaeude_stored") THEN
    RAISE EXCEPTION 'Stored berlin_alkis_gebaeude.alkis_gebaeude:gebaeude contains no buildings.';
  END IF;
  IF EXISTS (
    SELECT FROM mirror."alkis_gebaeude:gebaeude_stored"
    WHERE fid IS NULL OR uuid IS NULL OR btrim(uuid) = ''
      OR geom IS NULL OR public.ST_IsEmpty(geom)
      OR nullif(btrim(hoh), '') IS NOT NULL
        AND lower(btrim(hoh)) NOT IN ('true', 'false')
  ) THEN
    RAISE EXCEPTION 'Stored buildings require fid, nonempty uuid and geometry, and hoh must be true, false or empty.';
  END IF;
  IF EXISTS (
    SELECT FROM mirror."alkis_gebaeude:gebaeude_stored"
    GROUP BY uuid HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Stored buildings contain duplicate stable uuid values.';
  END IF;

  FOR source_building IN
    SELECT fid, uuid, geom, gfk, bezgfk, ofl, bezofl, aog, aug,
           nullif(btrim(hoh), '')::boolean AS hoh,
           bat, bezbat, nam, baw, bezbaw, zus, bezzus,
           lag, namlag, hnr, pnr, lnr, bezeich
    FROM mirror."alkis_gebaeude:gebaeude_stored"
    ORDER BY uuid
  LOOP
    SELECT * INTO current_building FROM utt.building
    WHERE building_id_official = source_building.uuid AND upper_inf(utt_txn);

    IF FOUND THEN
      IF current_building.source_valid IS NULL THEN
        RAISE EXCEPTION 'Current building % has no source-valid range.', source_building.uuid;
      END IF;

      content_changed :=
        public.ST_AsEWKB(current_building.geom) IS DISTINCT FROM public.ST_AsEWKB(source_building.geom)
        OR current_building.building_function IS DISTINCT FROM source_building.gfk
        OR current_building.building_function_description IS DISTINCT FROM source_building.bezgfk
        OR current_building.position_relative_to_ground IS DISTINCT FROM source_building.ofl
        OR current_building.position_relative_to_ground_description IS DISTINCT FROM source_building.bezofl
        OR current_building.storeys_above_ground IS DISTINCT FROM source_building.aog
        OR current_building.storeys_below_ground IS DISTINCT FROM source_building.aug
        OR current_building.highrise IS DISTINCT FROM source_building.hoh
        OR current_building.building_component_type IS DISTINCT FROM source_building.bat
        OR current_building.building_component_type_description IS DISTINCT FROM source_building.bezbat
        OR current_building.name IS DISTINCT FROM source_building.nam
        OR current_building.building_configuration IS DISTINCT FROM source_building.baw
        OR current_building.building_configuration_description IS DISTINCT FROM source_building.bezbaw
        OR current_building.building_condition IS DISTINCT FROM source_building.zus
        OR current_building.building_condition_description IS DISTINCT FROM source_building.bezzus
        OR current_building.street_code IS DISTINCT FROM source_building.lag
        OR current_building.street_name IS DISTINCT FROM source_building.namlag
        OR current_building.house_number IS DISTINCT FROM source_building.hnr
        OR current_building.pseudo_house_number IS DISTINCT FROM source_building.pnr
        OR current_building.building_association_number IS DISTINCT FROM source_building.lnr
        OR current_building.aaa_description IS DISTINCT FROM source_building.bezeich;
      IF NOT content_changed THEN
        CONTINUE;
      END IF;

      IF validity_start < lower(current_building.source_valid) THEN
        RAISE EXCEPTION 'Changed building % has source revision %, before current revision %.',
          source_building.uuid, validity_start, lower(current_building.source_valid);
      END IF;

      UPDATE utt.building
      SET source_valid = CASE WHEN validity_start > lower(source_valid)
            THEN tstzrange(lower(source_valid), validity_start, '[)')
            ELSE source_valid END,
          utt_txn = tstzrange(lower(utt_txn), recorded_at, '[)')
      WHERE row_id = current_building.row_id;
    END IF;

    INSERT INTO utt.building (
      source_fid, building_id_official, geom, building_function, building_function_description, position_relative_to_ground, position_relative_to_ground_description, storeys_above_ground, storeys_below_ground, highrise,
      building_component_type, building_component_type_description, name, building_configuration, building_configuration_description, building_condition, building_condition_description, street_code, street_name,
      house_number, pseudo_house_number, building_association_number, aaa_description, source_valid, utt_txn
    ) VALUES (
      source_building.fid, source_building.uuid, source_building.geom,
      source_building.gfk, source_building.bezgfk, source_building.ofl,
      source_building.bezofl, source_building.aog, source_building.aug,
      source_building.hoh, source_building.bat, source_building.bezbat,
      source_building.nam, source_building.baw, source_building.bezbaw,
      source_building.zus, source_building.bezzus, source_building.lag,
      source_building.namlag, source_building.hnr, source_building.pnr,
      source_building.lnr, source_building.bezeich,
      tstzrange(validity_start, NULL, '[)'),
      tstzrange(recorded_at, NULL, '[)')
    );
    inserted_count := inserted_count + 1;
  END LOOP;

  RETURN inserted_count;
END;
$$;

REVOKE ALL ON FUNCTION utt_pkg.curate_building()
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON FUNCTION utt_pkg.curate_building() TO uttdb_dba, uttdb_pipeline;
COMMENT ON FUNCTION utt_pkg.curate_building() IS
  'DBA/pipeline invoker-security curation of Berlin ALKIS buildings from mirror."alkis_gebaeude:gebaeude_stored" into utt.building. Source uuid supplies building_id_official; source fid is retained as technical source metadata in source_fid but does not trigger versions. Geometry and the directly mapped ALKIS descriptive attributes gfk, bezgfk, ofl, bezofl, aog, aug, hoh, bat, bezbat, nam, baw, bezbaw, zus, bezzus, lag, namlag, hnr, pnr, lnr and bezeich define content. The exact registry source_revision_at opens source_valid because the layer has no feature validity date. Content changes create versions under the shared temporal model; a revision or fid change alone creates no version. Derived classification, heritage, height and energy fields remain NULL. Returns the number of inserted versions, including first imports. Missing source objects are not closed or deleted. Requires registry/source SELECT and target SELECT/INSERT/UPDATE plus row/table-lock privileges. Example: SELECT utt_pkg.curate_building();';

CREATE FUNCTION utt_pkg.curate_block()
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
DECLARE
  source_block record;
  current_block utt.block%ROWTYPE;
  imported_at timestamptz;
  recorded_at timestamptz;
  content_changed boolean;
  inserted_count integer := 0;
BEGIN
  SELECT r.last_imported_at INTO STRICT imported_at
  FROM mirror.registry r
  WHERE r.source_name = 'berlin_bloecke' AND r.layer_name = 'bloecke:rbs_bloecke'
    AND r.last_imported_at IS NOT NULL
  FOR SHARE;

  LOCK TABLE utt.block IN SHARE ROW EXCLUSIVE MODE;
  recorded_at := clock_timestamp();

  IF NOT EXISTS (SELECT FROM mirror."bloecke:rbs_bloecke_stored") THEN
    RAISE EXCEPTION 'Stored berlin_bloecke.bloecke:rbs_bloecke contains no blocks.';
  END IF;
  IF EXISTS (
    SELECT FROM mirror."bloecke:rbs_bloecke_stored"
    WHERE blknr IS NULL OR blknr !~ '^[0-9]+$'
      OR plr IS NULL OR plr !~ '^[0-9]+$'
      OR bez IS NULL OR bez !~ '^[0-9]+$'
      OR datum IS NULL OR geom IS NULL OR public.ST_IsEmpty(geom)
  ) THEN
    RAISE EXCEPTION 'Stored blocks require numeric blknr, plr and bez, plus datum and nonempty geometry.';
  END IF;
  IF EXISTS (
    SELECT FROM mirror."bloecke:rbs_bloecke_stored" GROUP BY blknr HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Stored blocks contain duplicate stable blknr IDs.';
  END IF;

  FOR source_block IN
    SELECT blknr::bigint AS blk_id, geom, plr::bigint AS planning_area_no,
           11000000 + bez::bigint AS in_district,
           datum::timestamp AT TIME ZONE 'UTC' AS validity_start,
           CASE WHEN public.ST_Covers(geom, public.ST_Centroid(geom))
             THEN public.ST_Centroid(geom)
             ELSE public.ST_PointOnSurface(geom)
           END AS centroid
    FROM mirror."bloecke:rbs_bloecke_stored"
    ORDER BY blknr::bigint
  LOOP
    SELECT * INTO current_block FROM utt.block
    WHERE block_id_official = source_block.blk_id AND upper_inf(utt_txn);

    IF FOUND THEN
      IF current_block.source_valid IS NULL THEN
        RAISE EXCEPTION 'Current block % has no source-valid range.', source_block.blk_id;
      END IF;

      content_changed := current_block.planning_area_no IS DISTINCT FROM source_block.planning_area_no
        OR current_block.mostly_district_id_official IS DISTINCT FROM source_block.in_district
        OR public.ST_AsEWKB(current_block.geom) IS DISTINCT FROM public.ST_AsEWKB(source_block.geom)
        OR public.ST_AsEWKB(current_block.centroid) IS DISTINCT FROM public.ST_AsEWKB(source_block.centroid);
      IF NOT content_changed THEN
        CONTINUE;
      END IF;

      IF source_block.validity_start < lower(current_block.source_valid) THEN
        RAISE EXCEPTION 'Changed block % has source validity %, before current validity %.',
          source_block.blk_id, source_block.validity_start, lower(current_block.source_valid);
      END IF;

      UPDATE utt.block
      SET source_valid = CASE WHEN source_block.validity_start > lower(source_valid)
            THEN tstzrange(lower(source_valid), source_block.validity_start, '[)')
            ELSE source_valid END,
          utt_txn = tstzrange(lower(utt_txn), recorded_at, '[)')
      WHERE row_id = current_block.row_id;
    END IF;

    INSERT INTO utt.block (
      block_id_official, geom, planning_area_no, mostly_district_id_official, centroid, source_valid, utt_txn
    ) VALUES (
      source_block.blk_id, source_block.geom, source_block.planning_area_no,
      source_block.in_district, source_block.centroid,
      tstzrange(source_block.validity_start, NULL, '[)'),
      tstzrange(recorded_at, NULL, '[)')
    );
    inserted_count := inserted_count + 1;
  END LOOP;

  RETURN inserted_count;
END;
$$;

REVOKE ALL ON FUNCTION utt_pkg.curate_block()
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON FUNCTION utt_pkg.curate_block() TO uttdb_dba, uttdb_pipeline;
COMMENT ON FUNCTION utt_pkg.curate_block() IS
  'DBA/pipeline invoker-security curation of Berlin statistical blocks from mirror."bloecke:rbs_bloecke_stored" into utt.block: numeric blknr becomes stable block_id_official, plr becomes planning_area_no, bez becomes the long Berlin district ID, datum starts source_valid at midnight UTC, and geometry retains its source CRS. Centroid is the geometric centroid when covered by the block, otherwise ST_PointOnSurface provides an interior representative point. Requires a successfully imported registry entry. No temporal input is accepted from the caller. Geometry, derived centroid, planning area or district changes create versions under the shared temporal curation model; a changed datum without a content change leaves the current version untouched. Returns the number of inserted block versions, including first imports. Missing source objects are not closed or deleted. Requires registry/source SELECT and target SELECT/INSERT/UPDATE plus row/table-lock privileges. Example: SELECT utt_pkg.curate_block();';

CREATE FUNCTION utt_pkg.curate_plot()
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
DECLARE
  source_plot record;
  current_plot utt.plot%ROWTYPE;
  imported_at timestamptz;
  recorded_at timestamptz;
  content_changed boolean;
  inserted_count integer := 0;
BEGIN
  SELECT r.last_imported_at INTO STRICT imported_at
  FROM mirror.registry r
  WHERE r.source_name = 'berlin_alkis' AND r.layer_name = 'alkis:flurstuecke'
    AND r.last_imported_at IS NOT NULL
  FOR SHARE;

  LOCK TABLE utt.plot IN SHARE ROW EXCLUSIVE MODE;
  recorded_at := clock_timestamp();

  IF NOT EXISTS (SELECT FROM mirror."alkis:flurstuecke_stored") THEN
    RAISE EXCEPTION 'Stored berlin_alkis.alkis:flurstuecke contains no plots.';
  END IF;
  IF EXISTS (
    SELECT FROM mirror."alkis:flurstuecke_stored"
    WHERE fsko IS NULL OR fsko !~ '^[0-9]+_*$'
      OR rtrim(fsko, '_') = ''
      OR zae IS NULL OR zae !~ '^[0-9]+$'
      OR gmk IS NULL OR gmk !~ '^[0-9]+$'
      OR fln IS NULL OR fln !~ '^[0-9]+$'
      OR gdz IS NULL OR gdz !~ '^[0-9]+$'
      OR beg IS NULL OR geom IS NULL OR public.ST_IsEmpty(geom)
  ) THEN
    RAISE EXCEPTION 'Stored plots require a numeric fsko with optional trailing underscores, numeric zae, gmk, fln and gdz, plus beg and nonempty geometry.';
  END IF;
  IF EXISTS (
    SELECT FROM mirror."alkis:flurstuecke_stored"
    GROUP BY rtrim(fsko, '_')::bigint HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Stored plots contain duplicate stable fsko IDs after removing padding.';
  END IF;

  FOR source_plot IN
    SELECT rtrim(fsko, '_')::bigint AS fsko, geom,
           zae::bigint AS zae, gmk::bigint AS gmk, fln::bigint AS fln,
           gdz::bigint AS in_district,
           beg::timestamp AT TIME ZONE 'UTC' AS validity_start
    FROM mirror."alkis:flurstuecke_stored"
    ORDER BY rtrim(fsko, '_')::bigint
  LOOP
    SELECT * INTO current_plot FROM utt.plot
    WHERE plot_id_official = source_plot.fsko AND upper_inf(utt_txn);

    IF FOUND THEN
      IF current_plot.source_valid IS NULL THEN
        RAISE EXCEPTION 'Current plot % has no source-valid range.', source_plot.fsko;
      END IF;

      content_changed :=
        public.ST_AsEWKB(current_plot.geom) IS DISTINCT FROM public.ST_AsEWKB(source_plot.geom)
        OR current_plot.parcel_number_numerator IS DISTINCT FROM source_plot.zae
        OR current_plot.cadastral_district_code IS DISTINCT FROM source_plot.gmk
        OR current_plot.cadastral_field_number IS DISTINCT FROM source_plot.fln
        OR current_plot.district_id_official IS DISTINCT FROM source_plot.in_district;
      IF NOT content_changed THEN
        CONTINUE;
      END IF;

      IF source_plot.validity_start < lower(current_plot.source_valid) THEN
        RAISE EXCEPTION 'Changed plot % has source validity %, before current validity %.',
          source_plot.fsko, source_plot.validity_start,
          lower(current_plot.source_valid);
      END IF;

      UPDATE utt.plot
      SET source_valid = CASE WHEN source_plot.validity_start > lower(source_valid)
            THEN tstzrange(lower(source_valid), source_plot.validity_start, '[)')
            ELSE source_valid END,
          utt_txn = tstzrange(lower(utt_txn), recorded_at, '[)')
      WHERE row_id = current_plot.row_id;
    END IF;

    INSERT INTO utt.plot (
      plot_id_official, geom, parcel_number_numerator, cadastral_district_code, cadastral_field_number, district_id_official, source_valid, utt_txn
    ) VALUES (
      source_plot.fsko, source_plot.geom, source_plot.zae, source_plot.gmk,
      source_plot.fln, source_plot.in_district,
      tstzrange(source_plot.validity_start, NULL, '[)'),
      tstzrange(recorded_at, NULL, '[)')
    );
    inserted_count := inserted_count + 1;
  END LOOP;

  RETURN inserted_count;
END;
$$;

REVOKE ALL ON FUNCTION utt_pkg.curate_plot()
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON FUNCTION utt_pkg.curate_plot() TO uttdb_dba, uttdb_pipeline;
COMMENT ON FUNCTION utt_pkg.curate_plot() IS
  'DBA/pipeline invoker-security curation of Berlin cadastral plots from mirror."alkis:flurstuecke_stored" into utt.plot. The numeric portion of fsko becomes the stable plot_id_official; trailing source padding is removed. Geometry, zae, gmk, fln and district code gdz are copied, and beg starts source_valid at midnight UTC. Geometry or mapped cadastral changes create versions under the shared temporal model; changed beg alone creates no version. Returns the number of inserted versions, including first imports. Missing source objects are not closed or deleted. Requires registry/source SELECT and target SELECT/INSERT/UPDATE plus row/table-lock privileges. Example: SELECT utt_pkg.curate_plot();';

CREATE FUNCTION utt_pkg.curate_address()
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
DECLARE
  source_address record;
  current_address utt.address%ROWTYPE;
  imported_at timestamptz;
  recorded_at timestamptz;
  content_changed boolean;
  inserted_count integer := 0;
BEGIN
  SELECT r.last_imported_at INTO STRICT imported_at
  FROM mirror.registry r
  WHERE r.source_name = 'berlin_adressen'
    AND r.layer_name = 'adressen_rbs:adressen_rbs'
    AND r.last_imported_at IS NOT NULL
  FOR SHARE;

  LOCK TABLE utt.address IN SHARE ROW EXCLUSIVE MODE;
  recorded_at := clock_timestamp();

  IF NOT EXISTS (
    SELECT FROM mirror."adressen_rbs:adressen_rbs_stored"
  ) THEN
    RAISE EXCEPTION 'Stored berlin_adressen.adressen_rbs:adressen_rbs contains no address records.';
  END IF;
  IF EXISTS (
    SELECT FROM mirror."adressen_rbs:adressen_rbs_stored"
    WHERE adr_ident IS NULL OR adr_ident !~ '^[0-9]+$'
      OR aufn_dt IS NULL OR geom IS NULL OR public.ST_IsEmpty(geom)
      OR hausnr IS NULL OR hausnr !~ '^[0-9]+$'
      OR strnam IS NULL OR btrim(strnam) = ''
      OR strnr IS NULL OR btrim(strnr) = ''
      OR postleit IS NULL OR postleit !~ '^[0-9]+$'
      OR bez IS NULL OR bez !~ '^[0-9]+$'
      OR plr IS NULL OR plr !~ '^[0-9]+$'
      OR blk IS NULL OR blk !~ '^[0-9]+$'
  ) THEN
    RAISE EXCEPTION 'Stored RBS records require numeric adr_ident, hausnr, postleit, bez, plr and blk, plus aufn_dt and nonempty street and geometry data.';
  END IF;
  IF EXISTS (
    SELECT FROM mirror."adressen_rbs:adressen_rbs_stored"
    GROUP BY adr_ident::bigint HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Stored RBS records contain duplicate stable adr_ident values.';
  END IF;

  FOR source_address IN
    SELECT adr_ident::bigint AS address_id, geom,
           strnam AS street_name, strnr AS street_id,
           hausnr::integer AS house_no, hausnrz AS house_no_suffix,
           postleit::bigint AS pca_id, blk::bigint AS blk_id,
           11000000 + bez::bigint AS district_id,
           bez_name AS district_name, ot AS place_id,
           ot_name AS place_name, plr::bigint AS planning_area_no,
           plr_name AS planning_area_name, aufn_dt::timestamp AS address_date,
           str_typ AS type,
           aufn_dt::timestamp AT TIME ZONE 'UTC' AS validity_start
    FROM mirror."adressen_rbs:adressen_rbs_stored"
    ORDER BY adr_ident::bigint
  LOOP
    SELECT * INTO current_address FROM utt.address
    WHERE address_id_official = source_address.address_id AND upper_inf(utt_txn);

    IF FOUND THEN
      IF current_address.source_valid IS NULL THEN
        RAISE EXCEPTION 'Current address % has no source-valid range.', source_address.address_id;
      END IF;

      content_changed :=
        public.ST_AsEWKB(current_address.geom) IS DISTINCT FROM public.ST_AsEWKB(source_address.geom)
        OR current_address.street_name IS DISTINCT FROM source_address.street_name
        OR current_address.street_id IS DISTINCT FROM source_address.street_id
        OR current_address.house_number IS DISTINCT FROM source_address.house_no
        OR current_address.house_number_suffix IS DISTINCT FROM source_address.house_no_suffix
        OR current_address.pca_id IS DISTINCT FROM source_address.pca_id
        OR current_address.block_id_official IS DISTINCT FROM source_address.blk_id
        OR current_address.district_id_official IS DISTINCT FROM source_address.district_id
        OR current_address.district_name IS DISTINCT FROM source_address.district_name
        OR current_address.place_id IS DISTINCT FROM source_address.place_id
        OR current_address.place_name IS DISTINCT FROM source_address.place_name
        OR current_address.planning_area_no IS DISTINCT FROM source_address.planning_area_no
        OR current_address.planning_area_name IS DISTINCT FROM source_address.planning_area_name
        OR current_address.type IS DISTINCT FROM source_address.type;
      IF NOT content_changed THEN
        CONTINUE;
      END IF;

      IF source_address.validity_start < lower(current_address.source_valid) THEN
        RAISE EXCEPTION 'Changed address % has source validity %, before current validity %.',
          source_address.address_id, source_address.validity_start,
          lower(current_address.source_valid);
      END IF;

      UPDATE utt.address
      SET source_valid = CASE WHEN source_address.validity_start > lower(source_valid)
            THEN tstzrange(lower(source_valid), source_address.validity_start, '[)')
            ELSE source_valid END,
          utt_txn = tstzrange(lower(utt_txn), recorded_at, '[)')
      WHERE row_id = current_address.row_id;
    END IF;

    INSERT INTO utt.address (
      address_id_official, geom, street_name, street_id, house_number, house_number_suffix,
      pca_id, block_id_official, district_id_official, district_name, place_id, place_name,
      planning_area_no, planning_area_name, address_date,
      type, source_valid, utt_txn
    ) VALUES (
      source_address.address_id, source_address.geom, source_address.street_name,
      source_address.street_id, source_address.house_no, source_address.house_no_suffix,
      source_address.pca_id, source_address.blk_id, source_address.district_id,
      source_address.district_name, source_address.place_id, source_address.place_name,
      source_address.planning_area_no, source_address.planning_area_name,
      source_address.address_date,
      source_address.type,
      tstzrange(source_address.validity_start, NULL, '[)'),
      tstzrange(recorded_at, NULL, '[)')
    );
    inserted_count := inserted_count + 1;
  END LOOP;

  RETURN inserted_count;
END;
$$;

REVOKE ALL ON FUNCTION utt_pkg.curate_address()
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON FUNCTION utt_pkg.curate_address() TO uttdb_dba, uttdb_pipeline;
COMMENT ON FUNCTION utt_pkg.curate_address() IS
  'DBA/pipeline invoker-security curation of Berlin RBS address records from mirror."adressen_rbs:adressen_rbs_stored" into utt.address. Numeric adr_ident is the stable address_id_official; source address and location fields are copied; str_typ becomes type; bez is expanded to the long Berlin district ID; aufn_dt starts source_valid at midnight UTC. Geometry or mapped descriptive/location changes create versions under the shared temporal model; changed aufn_dt alone creates no version. This routine leaves building_id_official and plot_id_official NULL. Returns the number of inserted versions, including first imports. Missing source objects are not closed or deleted. Requires registry/source SELECT and target SELECT/INSERT/UPDATE plus row/table-lock privileges. Example: SELECT utt_pkg.curate_address();';

CREATE FUNCTION utt_pkg.curate_relation(relation_name text)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
DECLARE
  inserted_count integer;
BEGIN
  CASE relation_name
    WHEN 'building_block' THEN
      LOCK TABLE utt.relation_bldg_block IN SHARE ROW EXCLUSIVE MODE;
      WITH candidates AS (
        SELECT b.row_id AS building_row_id, k.row_id AS block_row_id,
               round((public.ST_Area(public.ST_Intersection(b.geom, k.geom))
                 / public.ST_Area(b.geom))::numeric, 3) AS relative_intersection
        FROM utt.building b
        JOIN utt.block k ON public.ST_Intersects(b.geom, k.geom)
        WHERE upper_inf(b.utt_txn) AND upper_inf(k.utt_txn)
          AND b.geom IS NOT NULL AND k.geom IS NOT NULL
          AND NOT public.ST_IsEmpty(b.geom) AND NOT public.ST_IsEmpty(k.geom)
          AND public.ST_Area(b.geom) > 0
      )
      INSERT INTO utt.relation_bldg_block (
        building_row_id, block_row_id, relative_intersection
      )
      SELECT building_row_id, block_row_id, relative_intersection
      FROM candidates
      WHERE relative_intersection > 0.02 AND relative_intersection <= 1
      ON CONFLICT DO NOTHING;

    WHEN 'building_plot' THEN
      LOCK TABLE utt.relation_bldg_plot IN SHARE ROW EXCLUSIVE MODE;
      WITH candidates AS (
        SELECT b.row_id AS building_row_id, p.row_id AS plot_row_id,
               round((public.ST_Area(public.ST_Intersection(b.geom, p.geom))
                 / public.ST_Area(b.geom))::numeric, 3) AS relative_intersection
        FROM utt.building b
        JOIN utt.plot p ON public.ST_Intersects(b.geom, p.geom)
        WHERE upper_inf(b.utt_txn) AND upper_inf(p.utt_txn)
          AND b.geom IS NOT NULL AND p.geom IS NOT NULL
          AND NOT public.ST_IsEmpty(b.geom) AND NOT public.ST_IsEmpty(p.geom)
          AND public.ST_Area(b.geom) > 0
      )
      INSERT INTO utt.relation_bldg_plot (
        building_row_id, plot_row_id, relative_intersection
      )
      SELECT building_row_id, plot_row_id, relative_intersection
      FROM candidates
      WHERE relative_intersection > 0.02 AND relative_intersection <= 1
      ON CONFLICT DO NOTHING;

    WHEN 'plot_block' THEN
      LOCK TABLE utt.relation_plot_block IN SHARE ROW EXCLUSIVE MODE;
      WITH candidates AS (
        SELECT p.row_id AS plot_row_id, k.row_id AS block_row_id,
               round((public.ST_Area(public.ST_Intersection(p.geom, k.geom))
                 / public.ST_Area(p.geom))::numeric, 3) AS relative_intersection
        FROM utt.plot p
        JOIN utt.block k ON public.ST_Intersects(p.geom, k.geom)
        WHERE upper_inf(p.utt_txn) AND upper_inf(k.utt_txn)
          AND p.geom IS NOT NULL AND k.geom IS NOT NULL
          AND NOT public.ST_IsEmpty(p.geom) AND NOT public.ST_IsEmpty(k.geom)
          AND public.ST_Area(p.geom) > 0
      )
      INSERT INTO utt.relation_plot_block (
        plot_row_id, block_row_id, relative_intersection
      )
      SELECT plot_row_id, block_row_id, relative_intersection
      FROM candidates
      WHERE relative_intersection > 0.02 AND relative_intersection <= 1
      ON CONFLICT DO NOTHING;

    ELSE
      RAISE EXCEPTION 'Unsupported relation %. Use building_block, building_plot or plot_block.',
        relation_name;
  END CASE;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$$;

REVOKE ALL ON FUNCTION utt_pkg.curate_relation(text)
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON FUNCTION utt_pkg.curate_relation(text) TO uttdb_dba, uttdb_pipeline;
COMMENT ON FUNCTION utt_pkg.curate_relation(text) IS
  'DBA/pipeline invoker-security calculation of one supported spatial relation between current immutable UTT entity versions. relation_name must be building_block, building_plot or plot_block. The stored fraction is intersection area divided by the first entity area (building or plot), rounded to three decimals; values at or below 0.02 are omitted. Existing pairs are left unchanged, so reruns insert only relations for newly curated versions. Relation rows reference endpoint row_id values and have no separate temporal ranges; their temporal context comes from those immutable versions. Returns the number of inserted pairs. Examples: SELECT utt_pkg.curate_relation(''building_block''); SELECT utt_pkg.curate_relation(''building_plot''); SELECT utt_pkg.curate_relation(''plot_block'');';

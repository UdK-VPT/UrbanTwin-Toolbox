-- Example project: Berlin snapshot tables and SQL curation procedures.
-- Fresh initialization only; mirror is independently usable without this file.

-- Ordinary Berlin snapshot tables. Fresh initialization only.
CREATE SCHEMA curation;
COMMENT ON SCHEMA curation IS 'Project-specific snapshot recipes, output tables and current build identity.';

-- address

CREATE TABLE curation.berlin_address (
    row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    address_id_official bigint NOT NULL,
    geom public.geometry,
    plot_id_official bigint,
    street_name character varying,
    street_id character varying,
    house_number integer,
    house_number_suffix character varying,
    pca_id bigint,
    block_id_official bigint,
    district_id_official bigint,
    district_name character varying,
    place_id character varying,
    place_name character varying,
    planning_area_no bigint,
    planning_area_name character varying,
    address_date timestamp without time zone,
    type character varying,
    building_id_official character varying,
    CONSTRAINT berlin_address_official_identity UNIQUE (address_id_official)
);

COMMENT ON COLUMN curation.berlin_address.row_id IS 'Snapshot-local identifier of this address row.';


COMMENT ON COLUMN curation.berlin_address.address_id_official IS 'Official external logical object identifier (adr_ident); unique within this curated snapshot.';

COMMENT ON COLUMN curation.berlin_address.geom IS 'Punkt im Koordinatensystem; Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN curation.berlin_address.plot_id_official IS 'Official plot identifier (FSKO); logical reference to curation.berlin_plot.plot_id_official. Not currently populated by curation.';

COMMENT ON COLUMN curation.berlin_address.street_name IS 'Straßenname (strnam); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN curation.berlin_address.street_id IS 'Straßennummer (strnr); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN curation.berlin_address.house_number IS 'Hausnummer (hausnr); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN curation.berlin_address.house_number_suffix IS 'Hausnummer-Zusatz (hausnrz); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN curation.berlin_address.pca_id IS 'Postleitzahl (postleit); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN curation.berlin_address.block_id_official IS 'Official block identifier (blknr in the block source); populated from RBS blk by curation.curate_berlin_address_20261101().';

COMMENT ON COLUMN curation.berlin_address.district_id_official IS 'Official district identifier; derived as 11000000 + source bez by curation.curate_berlin_address_20261101().';

COMMENT ON COLUMN curation.berlin_address.district_name IS 'Bezirk (bez_name); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN curation.berlin_address.place_id IS 'Ortsteilschlüssel (ot); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN curation.berlin_address.place_name IS 'Ortsteil (ot_name); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN curation.berlin_address.planning_area_no IS 'Planungsraum-Schlüssel (plr); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN curation.berlin_address.planning_area_name IS 'Planungsraum (plr_name); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN curation.berlin_address.address_date IS 'Aufnahmedatum der Adresse (aufn_dt); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN curation.berlin_address.type IS 'Straßentyp (str_typ); distinguishes RBS streets, places and other object types.';

COMMENT ON COLUMN curation.berlin_address.building_id_official IS 'Official external building identifier (ALKIS uuid); logical reference to curation.berlin_building.building_id_official. Not currently populated by curation.';

CREATE INDEX berlin_address_geom_idx ON curation.berlin_address USING gist (geom);

-- block

CREATE TABLE curation.berlin_block (
    row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    block_id_official bigint NOT NULL,
    geom public.geometry,
    planning_area_no bigint,
    mostly_district_id_official bigint,
    centroid public.geometry,
    source_date timestamp without time zone,
    CONSTRAINT berlin_block_official_identity UNIQUE (block_id_official)
);

COMMENT ON COLUMN curation.berlin_block.row_id IS 'Snapshot-local identifier of this block row.';


COMMENT ON COLUMN curation.berlin_block.block_id_official IS 'Official external logical object identifier (blknr); unique within this curated snapshot.';

COMMENT ON COLUMN curation.berlin_block.geom IS 'Polygon des Umrings';

COMMENT ON COLUMN curation.berlin_block.centroid IS 'Derived representative point: geometric centroid when covered by geom, otherwise ST_PointOnSurface so the point lies within the block.';

COMMENT ON COLUMN curation.berlin_block.planning_area_no IS 'Planungsraum plr; populated from source plr by curation.curate_berlin_block_20261101().';

COMMENT ON COLUMN curation.berlin_block.mostly_district_id_official IS 'hauptsächlich in Bezirk';

CREATE INDEX berlin_block_geom_idx ON curation.berlin_block USING gist (geom);
CREATE INDEX berlin_block_centroid_idx ON curation.berlin_block USING gist (centroid);

-- building

CREATE TABLE curation.berlin_building (
    row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_fid bigint,
    building_id_official character varying NOT NULL,
    geom public.geometry,
    building_function integer,
    building_function_description character varying,
    position_relative_to_ground integer,
    position_relative_to_ground_description character varying,
    storeys_above_ground integer,
    storeys_below_ground integer,
    highrise boolean,
    building_component_type integer,
    building_component_type_description character varying,
    name character varying,
    building_configuration integer,
    building_configuration_description character varying,
    building_condition integer,
    building_condition_description character varying,
    street_code character varying,
    street_name character varying,
    house_number character varying,
    pseudo_house_number character varying,
    building_association_number character varying,
    aaa_description character varying,
    heritage_id character varying,
    heritage_type character varying,
    building_height numeric,
    roof_type character varying,
    roof_description character varying,
    heated boolean,
    usage_type text,
    building_type text,
    CONSTRAINT berlin_building_official_identity UNIQUE (building_id_official)
);

COMMENT ON COLUMN curation.berlin_building.row_id IS 'Snapshot-local identifier of this building row.';


COMMENT ON COLUMN curation.berlin_building.source_fid IS 'Technical source key (fid); retained as source metadata, not used for internal logical building references.';

COMMENT ON COLUMN curation.berlin_building.building_id_official IS 'Official external logical object identifier (ALKIS uuid); unique within this curated snapshot.';

COMMENT ON COLUMN curation.berlin_building.geom IS 'Polygon des Umrings';

COMMENT ON COLUMN curation.berlin_building.building_function IS 'Gebäudefunktion GFK, Schlüssel';

COMMENT ON COLUMN curation.berlin_building.building_function_description IS 'Gebäudefunktion GFK, Bezeichnung';

COMMENT ON COLUMN curation.berlin_building.position_relative_to_ground IS 'Lage zur Erdoberfläche, Schlüssel';

COMMENT ON COLUMN curation.berlin_building.position_relative_to_ground_description IS 'Lage zur Erdoberfläche, Name';

COMMENT ON COLUMN curation.berlin_building.storeys_above_ground IS 'Anzahl der Obergeschosse AOG';

COMMENT ON COLUMN curation.berlin_building.storeys_below_ground IS 'Anzahl der Untergeschosse AUG';

COMMENT ON COLUMN curation.berlin_building.highrise IS 'Hochhaus HOH';

COMMENT ON COLUMN curation.berlin_building.building_component_type IS 'Bauart BAT, Schlüssel';

COMMENT ON COLUMN curation.berlin_building.building_component_type_description IS 'Bauart BAT, Bezeichnung';

COMMENT ON COLUMN curation.berlin_building.name IS 'Gebäudename';

COMMENT ON COLUMN curation.berlin_building.building_configuration IS 'Bauweise BAW, Schlüssel';

COMMENT ON COLUMN curation.berlin_building.building_configuration_description IS 'Bauweise BAW, Bezeichnung';

COMMENT ON COLUMN curation.berlin_building.building_condition IS 'Zustand ZUS, Schlüssel';

COMMENT ON COLUMN curation.berlin_building.building_condition_description IS 'Zustand ZUS, Bezeichnung';

COMMENT ON COLUMN curation.berlin_building.street_code IS 'Straßenschlüssel LAG';

COMMENT ON COLUMN curation.berlin_building.street_name IS 'Straßenname NAMLAG';

COMMENT ON COLUMN curation.berlin_building.house_number IS 'Hausnummer HNR';

COMMENT ON COLUMN curation.berlin_building.pseudo_house_number IS 'Pseudo-Hausnummer PNR';

COMMENT ON COLUMN curation.berlin_building.building_association_number IS 'Laufende Nummer LNR, nicht eindeutig';

COMMENT ON COLUMN curation.berlin_building.aaa_description IS 'AAA-Beschreibung, AFIS–ALKIS–ATKIS';

COMMENT ON COLUMN curation.berlin_building.heritage_id IS 'ID in Denkmalliste';

COMMENT ON COLUMN curation.berlin_building.heritage_type IS 'Art des Denkmals';

COMMENT ON COLUMN curation.berlin_building.building_height IS 'Gebäudehöhe';

COMMENT ON COLUMN curation.berlin_building.roof_type IS 'Dachart';

COMMENT ON COLUMN curation.berlin_building.roof_description IS 'Dachartbeschreibung';

COMMENT ON COLUMN curation.berlin_building.heated IS 'Assumption whether a building is heated. Not currently populated by curation.';

COMMENT ON COLUMN curation.berlin_building.usage_type IS 'Residential (WG) or non-residential (NWG) building use. Not currently populated by curation.';

COMMENT ON COLUMN curation.berlin_building.building_type IS 'Detaillierter Gebäudetyp für projektspezifische Anwendungen';

CREATE INDEX berlin_building_geom_idx ON curation.berlin_building USING gist (geom);

-- The unique official-identity constraint already supplies the building ID index.

-- city

CREATE TABLE curation.berlin_city (
    row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    city_id_official bigint NOT NULL,
    name character varying,
    geom public.geometry,
    CONSTRAINT berlin_city_official_identity UNIQUE (city_id_official)
);

COMMENT ON COLUMN curation.berlin_city.row_id IS 'Snapshot-local identifier of this city row.';


COMMENT ON COLUMN curation.berlin_city.city_id_official IS 'Official external logical object identifier (lan); unique within this curated snapshot.';

COMMENT ON COLUMN curation.berlin_city.name IS 'Name der Stadt';

COMMENT ON COLUMN curation.berlin_city.geom IS 'Polygon des Umrings';

CREATE INDEX berlin_city_geom_idx ON curation.berlin_city USING gist (geom);

-- district

CREATE TABLE curation.berlin_district (
    row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    district_id_official bigint NOT NULL,
    name character varying,
    geom public.geometry,
    CONSTRAINT berlin_district_official_identity UNIQUE (district_id_official)
);

COMMENT ON COLUMN curation.berlin_district.row_id IS 'Snapshot-local identifier of this district row.';


COMMENT ON COLUMN curation.berlin_district.district_id_official IS 'Official external logical object identifier (district identifier); unique within this curated snapshot.';

COMMENT ON COLUMN curation.berlin_district.name IS 'Name des Bezirks';

COMMENT ON COLUMN curation.berlin_district.geom IS 'Polygon des Umrings';

CREATE INDEX berlin_district_geom_idx ON curation.berlin_district USING gist (geom);

-- plot

CREATE TABLE curation.berlin_plot (
    row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plot_id_official bigint NOT NULL,
    geom public.geometry,
    parcel_number_numerator bigint,
    cadastral_district_code bigint,
    cadastral_field_number bigint,
    source_date timestamp without time zone,
    district_id_official bigint,
    CONSTRAINT berlin_plot_official_identity UNIQUE (plot_id_official)
);

COMMENT ON COLUMN curation.berlin_plot.row_id IS 'Snapshot-local identifier of this plot row.';


COMMENT ON COLUMN curation.berlin_plot.plot_id_official IS 'Official external logical object identifier (FSKO); unique within this curated snapshot.';

COMMENT ON COLUMN curation.berlin_plot.geom IS 'Polygon des Umrings';

COMMENT ON COLUMN curation.berlin_plot.parcel_number_numerator IS 'Flurstückskennzeichen (Zähler) ZAE';

COMMENT ON COLUMN curation.berlin_plot.cadastral_district_code IS 'Gemarkungsschlüssel GMK';

COMMENT ON COLUMN curation.berlin_plot.cadastral_field_number IS 'Flurnummer FLN';

COMMENT ON COLUMN curation.berlin_plot.district_id_official IS 'Official district identifier; populated from source gdz by curation.curate_berlin_plot_20261101().';

CREATE INDEX berlin_plot_geom_idx ON curation.berlin_plot USING gist (geom);


CREATE TABLE curation.berlin_relation_building_block (
    building_row_id bigint NOT NULL REFERENCES curation.berlin_building(row_id),
    block_row_id bigint NOT NULL REFERENCES curation.berlin_block(row_id),
    relative_intersection numeric NOT NULL CHECK (relative_intersection > 0.02 AND relative_intersection <= 1),
    PRIMARY KEY (building_row_id,block_row_id)
);
COMMENT ON TABLE curation.berlin_relation_building_block IS 'Snapshot n:m building/block matches; intersection area divided by building area, rounded to three decimals and retained above 0.02.';

CREATE TABLE curation.berlin_relation_building_plot (
    building_row_id bigint NOT NULL REFERENCES curation.berlin_building(row_id),
    plot_row_id bigint NOT NULL REFERENCES curation.berlin_plot(row_id),
    relative_intersection numeric NOT NULL CHECK (relative_intersection > 0.02 AND relative_intersection <= 1),
    PRIMARY KEY (building_row_id,plot_row_id)
);
COMMENT ON TABLE curation.berlin_relation_building_plot IS 'Snapshot n:m building/plot matches; intersection area divided by building area, rounded to three decimals and retained above 0.02.';

CREATE TABLE curation.berlin_relation_plot_block (
    plot_row_id bigint NOT NULL REFERENCES curation.berlin_plot(row_id),
    block_row_id bigint NOT NULL REFERENCES curation.berlin_block(row_id),
    relative_intersection numeric NOT NULL CHECK (relative_intersection > 0.02 AND relative_intersection <= 1),
    PRIMARY KEY (plot_row_id,block_row_id)
);
COMMENT ON TABLE curation.berlin_relation_plot_block IS 'Snapshot n:m plot/block matches; intersection area divided by plot area, rounded to three decimals and retained above 0.02.';

CREATE TABLE curation.dataset_build (
    dataset_name text PRIMARY KEY CHECK (btrim(dataset_name) <> ''),
    recipe_name text NOT NULL,
    git_revision text,
    mirror_snapshot timestamptz NOT NULL CHECK (isfinite(mirror_snapshot)),
    region public.geometry,
    completed_at timestamptz NOT NULL
);
COMMENT ON TABLE curation.dataset_build IS 'System-maintained identity of each current complete successful dataset, replaced atomically with its tables. region NULL means the whole registered scope. No execution history; failed builds preserve this row.';
COMMENT ON COLUMN curation.dataset_build.git_revision IS 'Caller-supplied SQL Git revision, NULL when unknown; not independently verified by PostgreSQL.';
COMMENT ON COLUMN curation.dataset_build.mirror_snapshot IS 'Actual mirror system-time selection used for all inputs; not a temporal axis on curated rows.';

COMMENT ON COLUMN curation.berlin_block.source_date IS 'Original source datum, an ordinary attribute without valid-time inference.';
COMMENT ON COLUMN curation.berlin_plot.source_date IS 'Original source beg, an ordinary attribute without valid-time inference.';

-- Snapshot recipe procedures

-- One functional Berlin recipe; no generic mapping or record-history framework.
-- Helpers have no execution grants outside the owner/DBA boundary.
CREATE FUNCTION curation.curation_berlin_source(source_name text,layer_name text,
    snapshot_at timestamptz,required_columns text[]) RETURNS regclass
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE registration mirror.registry%ROWTYPE; structure bigint;
BEGIN
    SELECT r.* INTO STRICT registration FROM mirror.registry r
      WHERE r.source_name=curation_berlin_source.source_name
        AND r.layer_name=curation_berlin_source.layer_name AND r.storage_mode='rows';
    SELECT i.structure_version INTO structure FROM mirror.import i
      WHERE i.registry_row_id=registration.row_id AND i.status='accepted'
        AND i.accepted_at<=snapshot_at ORDER BY i.accepted_at DESC,i.import_id DESC LIMIT 1;
    IF structure IS NULL THEN
      RAISE EXCEPTION 'No accepted snapshot for %.% at %',source_name,layer_name,snapshot_at;
    END IF;
    IF EXISTS(SELECT FROM unnest(required_columns) c WHERE NOT EXISTS(
      SELECT FROM mirror.source_columns sc WHERE sc.registry_row_id=registration.row_id
        AND sc.structure_version=structure AND sc.column_name=c)) THEN
      RAISE EXCEPTION 'Required recipe columns absent from %.% at %',source_name,layer_name,snapshot_at;
    END IF;
    RETURN to_regclass(format('mirror.%I',registration.stored_table));
END;
$$;
COMMENT ON FUNCTION curation.curation_berlin_source(text,text,timestamptz,text[]) IS 'Internal helper called by Berlin entity procedures. Checks accepted schema at the requested snapshot, including removed columns, and returns the stored source relation; writes nothing. Example: SELECT curation.curation_berlin_source(''berlin_alkis'',''alkis:land'',''2026-11-01 UTC'',ARRAY[''lan'',''namlan'',''geom'']);';

CREATE PROCEDURE curation.curate_berlin_city_20261101(
    snapshot_at timestamptz DEFAULT TIMESTAMPTZ '2026-11-01 00:00:00+00',
    region public.geometry DEFAULT NULL)
LANGUAGE plpgsql SET search_path=pg_catalog SET TimeZone='UTC' AS $$
DECLARE source_relation regclass;
BEGIN
    source_relation:=curation.curation_berlin_source('berlin_alkis','alkis:land',snapshot_at,ARRAY['lan','namlan','geom']);
    DROP TABLE IF EXISTS pg_temp.berlin_city_working;
    CREATE TEMP TABLE berlin_city_working (LIKE curation.berlin_city INCLUDING ALL) ON COMMIT DROP;
    EXECUTE format($query$
      INSERT INTO pg_temp.berlin_city_working (
        city_id_official,
        name,
        geom
      )
      SELECT
        (lan)::bigint,
        (namlan)::character varying,
        (geom)::public.geometry
      FROM %s
      WHERE utt_txn @> $1 AND geom IS NOT NULL AND NOT public.ST_IsEmpty(geom)
        AND public.ST_SRID(geom)>0
        AND ($2 IS NULL OR public.ST_Intersects(geom,$2))
      ORDER BY utt_key
    $query$,source_relation) USING snapshot_at,region;
    ANALYZE pg_temp.berlin_city_working;
END;
$$;
COMMENT ON PROCEDURE curation.curate_berlin_city_20261101(timestamptz,public.geometry) IS 'Internal SQL build step called by curate_berlin_20261101 in the same transaction. Reads the exact mirror snapshot and creates an indexed temporary city table, preserving nullable descriptive values and source dates. Does not install output or commit. Example inside the orchestrator transaction: CALL curation.curate_berlin_city_20261101(''2026-11-01 UTC'',NULL);';

CREATE PROCEDURE curation.curate_berlin_district_20261101(
    snapshot_at timestamptz DEFAULT TIMESTAMPTZ '2026-11-01 00:00:00+00',
    region public.geometry DEFAULT NULL)
LANGUAGE plpgsql SET search_path=pg_catalog SET TimeZone='UTC' AS $$
DECLARE source_relation regclass;
BEGIN
    source_relation:=curation.curation_berlin_source('berlin_alkis','alkis:bezirk',snapshot_at,ARRAY['name','namgem','geom']);
    DROP TABLE IF EXISTS pg_temp.berlin_district_working;
    CREATE TEMP TABLE berlin_district_working (LIKE curation.berlin_district INCLUDING ALL) ON COMMIT DROP;
    EXECUTE format($query$
      INSERT INTO pg_temp.berlin_district_working (
        district_id_official,
        name,
        geom
      )
      SELECT
        (name)::bigint,
        (namgem)::character varying,
        (geom)::public.geometry
      FROM %s
      WHERE utt_txn @> $1 AND geom IS NOT NULL AND NOT public.ST_IsEmpty(geom)
        AND public.ST_SRID(geom)>0
        AND ($2 IS NULL OR public.ST_Intersects(geom,$2))
      ORDER BY utt_key
    $query$,source_relation) USING snapshot_at,region;
    ANALYZE pg_temp.berlin_district_working;
END;
$$;
COMMENT ON PROCEDURE curation.curate_berlin_district_20261101(timestamptz,public.geometry) IS 'Internal SQL build step called by curate_berlin_20261101 in the same transaction. Reads the exact mirror snapshot and creates an indexed temporary district table, preserving nullable descriptive values and source dates. Does not install output or commit. Example inside the orchestrator transaction: CALL curation.curate_berlin_district_20261101(''2026-11-01 UTC'',NULL);';

CREATE PROCEDURE curation.curate_berlin_block_20261101(
    snapshot_at timestamptz DEFAULT TIMESTAMPTZ '2026-11-01 00:00:00+00',
    region public.geometry DEFAULT NULL)
LANGUAGE plpgsql SET search_path=pg_catalog SET TimeZone='UTC' AS $$
DECLARE source_relation regclass;
BEGIN
    source_relation:=curation.curation_berlin_source('berlin_bloecke','bloecke:rbs_bloecke',snapshot_at,ARRAY['blknr','geom','plr','bez','datum']);
    DROP TABLE IF EXISTS pg_temp.berlin_block_working;
    CREATE TEMP TABLE berlin_block_working (LIKE curation.berlin_block INCLUDING ALL) ON COMMIT DROP;
    EXECUTE format($query$
      INSERT INTO pg_temp.berlin_block_working (
        block_id_official,
        geom,
        planning_area_no,
        mostly_district_id_official,
        centroid,
        source_date
      )
      SELECT
        (blknr)::bigint,
        (geom)::public.geometry,
        (plr)::bigint,
        (11000000 + bez::bigint)::bigint,
        (CASE WHEN public.ST_Covers(geom,public.ST_Centroid(geom)) THEN public.ST_Centroid(geom) ELSE public.ST_PointOnSurface(geom) END)::public.geometry,
        (datum::timestamp)::timestamp without time zone
      FROM %s
      WHERE utt_txn @> $1 AND geom IS NOT NULL AND NOT public.ST_IsEmpty(geom)
        AND public.ST_SRID(geom)>0
        AND ($2 IS NULL OR public.ST_Intersects(geom,$2))
      ORDER BY utt_key
    $query$,source_relation) USING snapshot_at,region;
    ANALYZE pg_temp.berlin_block_working;
END;
$$;
COMMENT ON PROCEDURE curation.curate_berlin_block_20261101(timestamptz,public.geometry) IS 'Internal SQL build step called by curate_berlin_20261101 in the same transaction. Reads the exact mirror snapshot and creates an indexed temporary block table, preserving nullable descriptive values and source dates. Does not install output or commit. Example inside the orchestrator transaction: CALL curation.curate_berlin_block_20261101(''2026-11-01 UTC'',NULL);';

CREATE PROCEDURE curation.curate_berlin_plot_20261101(
    snapshot_at timestamptz DEFAULT TIMESTAMPTZ '2026-11-01 00:00:00+00',
    region public.geometry DEFAULT NULL)
LANGUAGE plpgsql SET search_path=pg_catalog SET TimeZone='UTC' AS $$
DECLARE source_relation regclass;
BEGIN
    source_relation:=curation.curation_berlin_source('berlin_alkis','alkis:flurstuecke',snapshot_at,ARRAY['fsko','geom','zae','gmk','fln','gdz','beg']);
    DROP TABLE IF EXISTS pg_temp.berlin_plot_working;
    CREATE TEMP TABLE berlin_plot_working (LIKE curation.berlin_plot INCLUDING ALL) ON COMMIT DROP;
    EXECUTE format($query$
      INSERT INTO pg_temp.berlin_plot_working (
        plot_id_official,
        geom,
        parcel_number_numerator,
        cadastral_district_code,
        cadastral_field_number,
        district_id_official,
        source_date
      )
      SELECT
        (rtrim(fsko, '_'))::bigint,
        (geom)::public.geometry,
        (zae)::bigint,
        (gmk)::bigint,
        (fln)::bigint,
        (gdz)::bigint,
        (beg::timestamp)::timestamp without time zone
      FROM %s
      WHERE utt_txn @> $1 AND geom IS NOT NULL AND NOT public.ST_IsEmpty(geom)
        AND public.ST_SRID(geom)>0
        AND ($2 IS NULL OR public.ST_Intersects(geom,$2))
      ORDER BY utt_key
    $query$,source_relation) USING snapshot_at,region;
    ANALYZE pg_temp.berlin_plot_working;
END;
$$;
COMMENT ON PROCEDURE curation.curate_berlin_plot_20261101(timestamptz,public.geometry) IS 'Internal SQL build step called by curate_berlin_20261101 in the same transaction. Reads the exact mirror snapshot and creates an indexed temporary plot table, preserving nullable descriptive values and source dates. Does not install output or commit. Example inside the orchestrator transaction: CALL curation.curate_berlin_plot_20261101(''2026-11-01 UTC'',NULL);';

CREATE PROCEDURE curation.curate_berlin_building_20261101(
    snapshot_at timestamptz DEFAULT TIMESTAMPTZ '2026-11-01 00:00:00+00',
    region public.geometry DEFAULT NULL)
LANGUAGE plpgsql SET search_path=pg_catalog SET TimeZone='UTC' AS $$
DECLARE source_relation regclass;
BEGIN
    source_relation:=curation.curation_berlin_source('berlin_alkis_gebaeude','alkis_gebaeude:gebaeude',snapshot_at,ARRAY['uuid','fid','geom','gfk','bezgfk','ofl','bezofl','aog','aug','hoh','bat','bezbat','nam','baw','bezbaw','zus','bezzus','lag','namlag','hnr','pnr','lnr','bezeich']);
    DROP TABLE IF EXISTS pg_temp.berlin_building_working;
    CREATE TEMP TABLE berlin_building_working (LIKE curation.berlin_building INCLUDING ALL) ON COMMIT DROP;
    EXECUTE format($query$
      INSERT INTO pg_temp.berlin_building_working (
        building_id_official,
        source_fid,
        geom,
        building_function,
        building_function_description,
        position_relative_to_ground,
        position_relative_to_ground_description,
        storeys_above_ground,
        storeys_below_ground,
        highrise,
        building_component_type,
        building_component_type_description,
        name,
        building_configuration,
        building_configuration_description,
        building_condition,
        building_condition_description,
        street_code,
        street_name,
        house_number,
        pseudo_house_number,
        building_association_number,
        aaa_description
      )
      SELECT
        (uuid)::text,
        (fid)::bigint,
        (geom)::public.geometry,
        (gfk)::integer,
        (bezgfk)::character varying,
        (ofl)::integer,
        (bezofl)::character varying,
        (aog)::integer,
        (aug)::integer,
        (nullif(btrim(hoh), '')::boolean)::boolean,
        (bat)::integer,
        (bezbat)::character varying,
        (nam)::character varying,
        (baw)::integer,
        (bezbaw)::character varying,
        (zus)::integer,
        (bezzus)::character varying,
        (lag)::character varying,
        (namlag)::character varying,
        (hnr)::character varying,
        (pnr)::character varying,
        (lnr)::character varying,
        (bezeich)::character varying
      FROM %s
      WHERE utt_txn @> $1 AND geom IS NOT NULL AND NOT public.ST_IsEmpty(geom)
        AND public.ST_SRID(geom)>0
        AND ($2 IS NULL OR public.ST_Intersects(geom,$2))
      ORDER BY utt_key
    $query$,source_relation) USING snapshot_at,region;
    ANALYZE pg_temp.berlin_building_working;
END;
$$;
COMMENT ON PROCEDURE curation.curate_berlin_building_20261101(timestamptz,public.geometry) IS 'Internal SQL build step called by curate_berlin_20261101 in the same transaction. Reads the exact mirror snapshot and creates an indexed temporary building table, preserving nullable descriptive values and source dates. Does not install output or commit. Example inside the orchestrator transaction: CALL curation.curate_berlin_building_20261101(''2026-11-01 UTC'',NULL);';

CREATE PROCEDURE curation.curate_berlin_address_20261101(
    snapshot_at timestamptz DEFAULT TIMESTAMPTZ '2026-11-01 00:00:00+00',
    region public.geometry DEFAULT NULL)
LANGUAGE plpgsql SET search_path=pg_catalog SET TimeZone='UTC' AS $$
DECLARE source_relation regclass;
BEGIN
    source_relation:=curation.curation_berlin_source('berlin_adressen','adressen_rbs:adressen_rbs',snapshot_at,ARRAY['adr_ident','geom','strnam','strnr','hausnr','hausnrz','postleit','blk','bez','bez_name','ot','ot_name','plr','plr_name','aufn_dt','str_typ']);
    DROP TABLE IF EXISTS pg_temp.berlin_address_working;
    CREATE TEMP TABLE berlin_address_working (LIKE curation.berlin_address INCLUDING ALL) ON COMMIT DROP;
    EXECUTE format($query$
      INSERT INTO pg_temp.berlin_address_working (
        address_id_official,
        geom,
        street_name,
        street_id,
        house_number,
        house_number_suffix,
        pca_id,
        block_id_official,
        district_id_official,
        district_name,
        place_id,
        place_name,
        planning_area_no,
        planning_area_name,
        address_date,
        type
      )
      SELECT
        (adr_ident)::bigint,
        (geom)::public.geometry,
        (strnam)::character varying,
        (strnr)::character varying,
        (hausnr)::integer,
        (hausnrz)::character varying,
        (postleit)::bigint,
        (blk)::bigint,
        (11000000 + bez::bigint)::bigint,
        (bez_name)::character varying,
        (ot)::character varying,
        (ot_name)::character varying,
        (plr)::bigint,
        (plr_name)::character varying,
        (aufn_dt::timestamp)::timestamp without time zone,
        (str_typ)::character varying
      FROM %s
      WHERE utt_txn @> $1 AND geom IS NOT NULL AND NOT public.ST_IsEmpty(geom)
        AND public.ST_SRID(geom)>0
        AND ($2 IS NULL OR public.ST_Intersects(geom,$2))
      ORDER BY utt_key
    $query$,source_relation) USING snapshot_at,region;
    ANALYZE pg_temp.berlin_address_working;
END;
$$;
COMMENT ON PROCEDURE curation.curate_berlin_address_20261101(timestamptz,public.geometry) IS 'Internal SQL build step called by curate_berlin_20261101 in the same transaction. Reads the exact mirror snapshot and creates an indexed temporary address table, preserving nullable descriptive values and source dates. Does not install output or commit. Example inside the orchestrator transaction: CALL curation.curate_berlin_address_20261101(''2026-11-01 UTC'',NULL);';

CREATE PROCEDURE curation.curate_berlin_relations_20261101()
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN

    DROP TABLE IF EXISTS pg_temp.berlin_relation_building_block_working;
    CREATE TEMP TABLE berlin_relation_building_block_working (
      building_row_id bigint NOT NULL,block_row_id bigint NOT NULL,
      relative_intersection numeric NOT NULL,
      PRIMARY KEY (building_row_id,block_row_id)) ON COMMIT DROP;
    INSERT INTO pg_temp.berlin_relation_building_block_working
    SELECT a.row_id,b.row_id,fraction.value
    FROM pg_temp.berlin_building_working a
    CROSS JOIN LATERAL (
      SELECT candidate.row_id,candidate.geom FROM pg_temp.berlin_block_working candidate
      WHERE candidate.geom OPERATOR(public.&&) a.geom OFFSET 0
    ) b
    CROSS JOIN LATERAL (
      SELECT round((public.ST_Area(public.ST_Intersection(a.geom,b.geom))
        /NULLIF(public.ST_Area(a.geom),0))::numeric,3) AS value OFFSET 0
    ) fraction
    WHERE fraction.value>0.02;

    DROP TABLE IF EXISTS pg_temp.berlin_relation_building_plot_working;
    CREATE TEMP TABLE berlin_relation_building_plot_working (
      building_row_id bigint NOT NULL,plot_row_id bigint NOT NULL,
      relative_intersection numeric NOT NULL,
      PRIMARY KEY (building_row_id,plot_row_id)) ON COMMIT DROP;
    INSERT INTO pg_temp.berlin_relation_building_plot_working
    SELECT a.row_id,b.row_id,fraction.value
    FROM pg_temp.berlin_building_working a
    CROSS JOIN LATERAL (
      SELECT candidate.row_id,candidate.geom FROM pg_temp.berlin_plot_working candidate
      WHERE candidate.geom OPERATOR(public.&&) a.geom OFFSET 0
    ) b
    CROSS JOIN LATERAL (
      SELECT round((public.ST_Area(public.ST_Intersection(a.geom,b.geom))
        /NULLIF(public.ST_Area(a.geom),0))::numeric,3) AS value OFFSET 0
    ) fraction
    WHERE fraction.value>0.02;

    DROP TABLE IF EXISTS pg_temp.berlin_relation_plot_block_working;
    CREATE TEMP TABLE berlin_relation_plot_block_working (
      plot_row_id bigint NOT NULL,block_row_id bigint NOT NULL,
      relative_intersection numeric NOT NULL,
      PRIMARY KEY (plot_row_id,block_row_id)) ON COMMIT DROP;
    INSERT INTO pg_temp.berlin_relation_plot_block_working
    SELECT a.row_id,b.row_id,fraction.value
    FROM pg_temp.berlin_plot_working a
    CROSS JOIN LATERAL (
      SELECT candidate.row_id,candidate.geom FROM pg_temp.berlin_block_working candidate
      WHERE candidate.geom OPERATOR(public.&&) a.geom OFFSET 0
    ) b
    CROSS JOIN LATERAL (
      SELECT round((public.ST_Area(public.ST_Intersection(a.geom,b.geom))
        /NULLIF(public.ST_Area(a.geom),0))::numeric,3) AS value OFFSET 0
    ) fraction
    WHERE fraction.value>0.02;
END;
$$;
COMMENT ON PROCEDURE curation.curate_berlin_relations_20261101() IS 'Internal chained curation step called after all entity working tables have been built by the Berlin orchestrator for one snapshot. Creates three temporary n:m relationship tables with one fraction per spatial pair; no historical combinations. Does not install or commit. Example in that build transaction: CALL curation.curate_berlin_relations_20261101();';

CREATE PROCEDURE curation.curate_berlin_20261101(
    snapshot_at timestamptz DEFAULT TIMESTAMPTZ '2026-11-01 00:00:00+00',
    region public.geometry DEFAULT NULL,git_revision text DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog SET TimeZone='UTC' AS $$
DECLARE entity text; output_name text; columns_sql text;
BEGIN
    IF snapshot_at IS NULL OR NOT isfinite(snapshot_at) OR snapshot_at>clock_timestamp() THEN
      RAISE EXCEPTION 'Choose a finite mirror snapshot at or before build time.';
    END IF;
    IF region IS NOT NULL AND (public.ST_IsEmpty(region) OR NOT public.ST_IsValid(region)
      OR public.ST_SRID(region)<=0) THEN RAISE EXCEPTION 'Region requires valid nonempty geometry with an explicit source-compatible CRS.'; END IF;
    PERFORM pg_advisory_xact_lock(70303,1);
    -- Prevent source publication/schema changes during the cooperating input selection.
    LOCK TABLE mirror.registry IN EXCLUSIVE MODE;
    CALL curation.curate_berlin_city_20261101(snapshot_at,region);
    CALL curation.curate_berlin_district_20261101(snapshot_at,region);
    CALL curation.curate_berlin_block_20261101(snapshot_at,region);
    CALL curation.curate_berlin_plot_20261101(snapshot_at,region);
    CALL curation.curate_berlin_building_20261101(snapshot_at,region);
    CALL curation.curate_berlin_address_20261101(snapshot_at,region);
    CALL curation.curate_berlin_relations_20261101();
    -- Keep output object identities stable for dependent queries and constraints.
    -- DELETE/INSERT is MVCC-safe for readers; all replacements commit together.
    LOCK TABLE curation.berlin_city,curation.berlin_district,curation.berlin_block,
      curation.berlin_plot,curation.berlin_building,curation.berlin_address,
      curation.berlin_relation_building_block,curation.berlin_relation_building_plot,curation.berlin_relation_plot_block,
      curation.dataset_build IN EXCLUSIVE MODE;
    DELETE FROM curation.berlin_relation_building_block;
    DELETE FROM curation.berlin_relation_building_plot;
    DELETE FROM curation.berlin_relation_plot_block;
    FOREACH entity IN ARRAY ARRAY['city','district','block','plot','building','address',
      'relation_building_block','relation_building_plot','relation_plot_block'] LOOP
      output_name:='berlin_'||entity;
      SELECT string_agg(quote_ident(attname),',' ORDER BY attnum) INTO columns_sql
        FROM pg_attribute WHERE attrelid=to_regclass('curation.'||output_name)
          AND attnum>0 AND NOT attisdropped;
      EXECUTE format('DELETE FROM curation.%I',output_name);
      EXECUTE format('INSERT INTO curation.%I (%s) OVERRIDING SYSTEM VALUE SELECT %s FROM pg_temp.%I',
        output_name,columns_sql,columns_sql,output_name||'_working');
      EXECUTE format('ANALYZE curation.%I',output_name);
    END LOOP;
    INSERT INTO curation.dataset_build(dataset_name,recipe_name,git_revision,mirror_snapshot,region,completed_at)
      VALUES('berlin','curation.curate_berlin_20261101',git_revision,snapshot_at,region,clock_timestamp())
      ON CONFLICT(dataset_name) DO UPDATE SET recipe_name=excluded.recipe_name,
        git_revision=excluded.git_revision,mirror_snapshot=excluded.mirror_snapshot,
        region=excluded.region,completed_at=excluded.completed_at;
END;
$$;
COMMENT ON PROCEDURE curation.curate_berlin_20261101(timestamptz,public.geometry,text) IS 'Pipeline/DBA entry point: reconstructs six Berlin entity tables and three n:m relationship tables from one accepted mirror snapshot, then installs all results and the current dataset_build row in one caller transaction. Uses indexed temporary tables; failure preserves the previous complete dataset. No internal commits, publication interface or curated history. NULL region selects full scope; explicit regions must use source-compatible CRS. Git revision is caller-supplied and nullable. Default snapshot is pinned, never latest. Example: BEGIN; CALL curation.curate_berlin_20261101(snapshot_at=>''2026-11-01 00:00:00+00'',git_revision=>NULL); COMMIT;';

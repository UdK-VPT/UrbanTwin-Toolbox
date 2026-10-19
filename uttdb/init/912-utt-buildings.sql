-- Selected EnergyMap table structures, moved from emc to utt.
-- Fresh initialization only; no source data or EnergyMap workflows are imported.
-- Column names and comments follow the reviewed UTT data model; retain UTT integrity constraints.
-- Access follows the UTT group-role defaults established by 902.

-- address

CREATE TABLE utt.address (
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
    source_valid tstzrange,
    utt_txn tstzrange NOT NULL,
    CONSTRAINT address_source_valid_nonempty CHECK (source_valid IS NULL OR NOT isempty(source_valid)),
    CONSTRAINT address_utt_txn_nonempty CHECK (NOT isempty(utt_txn)),
    CONSTRAINT address_utt_txn_no_overlap EXCLUDE USING gist
        (address_id_official WITH =, utt_txn WITH &&),
    CONSTRAINT address_source_valid_no_overlap EXCLUDE USING gist
        (address_id_official WITH =, source_valid WITH &&, utt_txn WITH &&)
        WHERE (source_valid IS NOT NULL)
);

COMMENT ON COLUMN utt.address.row_id IS 'UTT-internal immutable identifier of this stored address version.';

COMMENT ON COLUMN utt.address.source_valid IS 'Optional source-valid time. Address curation derives it from the RBS source field aufn_dt; NULL means the source supplies no usable validity information.';

COMMENT ON COLUMN utt.address.utt_txn IS 'System time when UTT considered this version current. Managed by curation as a half-open range with an unbounded end for the current version.';

COMMENT ON COLUMN utt.address.address_id_official IS 'Official external logical object identifier (adr_ident); unique per object within the source, repeated across temporal versions.';

COMMENT ON COLUMN utt.address.geom IS 'Punkt im Koordinatensystem; Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.plot_id_official IS 'Official plot identifier (FSKO); logical reference to utt.plot.plot_id_official. Not currently populated by curation.';

COMMENT ON COLUMN utt.address.street_name IS 'Straßenname (strnam); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.street_id IS 'Straßennummer (strnr); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.house_number IS 'Hausnummer (hausnr); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.house_number_suffix IS 'Hausnummer-Zusatz (hausnrz); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.pca_id IS 'Postleitzahl (postleit); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.block_id_official IS 'Official block identifier (blknr in the block source); populated from RBS blk by utt_pkg.curate_address().';

COMMENT ON COLUMN utt.address.district_id_official IS 'Official district identifier; derived as 11000000 + source bez by utt_pkg.curate_address().';

COMMENT ON COLUMN utt.address.district_name IS 'Bezirk (bez_name); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.place_id IS 'Ortsteilschlüssel (ot); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.place_name IS 'Ortsteil (ot_name); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.planning_area_no IS 'Planungsraum-Schlüssel (plr); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.planning_area_name IS 'Planungsraum (plr_name); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.address_date IS 'Aufnahmedatum der Adresse (aufn_dt); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.type IS 'Straßentyp (str_typ); distinguishes RBS streets, places and other object types.';

COMMENT ON COLUMN utt.address.building_id_official IS 'Official external building identifier (ALKIS uuid); logical reference to utt.building.building_id_official. Not currently populated by curation.';

CREATE INDEX address_geom_idx ON utt.address USING gist (geom);

-- block

CREATE TABLE utt.block (
    row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    block_id_official bigint NOT NULL,
    geom public.geometry,
    planning_area_no bigint,
    mostly_district_id_official bigint,
    centroid public.geometry,
    source_valid tstzrange,
    utt_txn tstzrange NOT NULL,
    CONSTRAINT block_source_valid_nonempty CHECK (source_valid IS NULL OR NOT isempty(source_valid)),
    CONSTRAINT block_utt_txn_nonempty CHECK (NOT isempty(utt_txn)),
    CONSTRAINT block_utt_txn_no_overlap EXCLUDE USING gist
        (block_id_official WITH =, utt_txn WITH &&),
    CONSTRAINT block_source_valid_no_overlap EXCLUDE USING gist
        (block_id_official WITH =, source_valid WITH &&, utt_txn WITH &&)
        WHERE (source_valid IS NOT NULL)
);

COMMENT ON COLUMN utt.block.row_id IS 'UTT-internal immutable identifier of this stored block version.';

COMMENT ON COLUMN utt.block.source_valid IS 'Optional source-valid time. Block curation derives it from the source datum field; NULL means the source supplies no usable validity information.';

COMMENT ON COLUMN utt.block.utt_txn IS 'System time when UTT considered this version current. Managed by curation as a half-open range with an unbounded end for the current version.';

COMMENT ON COLUMN utt.block.block_id_official IS 'Official external logical object identifier (blknr); unique per object within the source, repeated across temporal versions.';

COMMENT ON COLUMN utt.block.geom IS 'Polygon des Umrings';

COMMENT ON COLUMN utt.block.centroid IS 'Derived representative point: geometric centroid when covered by geom, otherwise ST_PointOnSurface so the point lies within the block.';

COMMENT ON COLUMN utt.block.planning_area_no IS 'Planungsraum plr; populated from source plr by utt_pkg.curate_block().';

COMMENT ON COLUMN utt.block.mostly_district_id_official IS 'hauptsächlich in Bezirk';

CREATE INDEX block_geom_idx ON utt.block USING gist (geom);
CREATE INDEX block_centroid_idx ON utt.block USING gist (centroid);

-- building

CREATE TABLE utt.building (
    row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_fid bigint NOT NULL,
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
    source_valid tstzrange,
    utt_txn tstzrange NOT NULL,
    CONSTRAINT building_source_valid_nonempty CHECK (source_valid IS NULL OR NOT isempty(source_valid)),
    CONSTRAINT building_utt_txn_nonempty CHECK (NOT isempty(utt_txn)),
    CONSTRAINT building_utt_txn_no_overlap EXCLUDE USING gist
        (building_id_official WITH =, utt_txn WITH &&),
    CONSTRAINT building_source_valid_no_overlap EXCLUDE USING gist
        (building_id_official WITH =, source_valid WITH &&, utt_txn WITH &&)
        WHERE (source_valid IS NOT NULL)
);

COMMENT ON COLUMN utt.building.row_id IS 'UTT-internal immutable identifier of this stored building version.';

COMMENT ON COLUMN utt.building.source_valid IS 'Optional source-valid time. Building curation derives it from source-backed revision metadata; NULL means the source supplies no usable validity information.';

COMMENT ON COLUMN utt.building.utt_txn IS 'System time when UTT considered this version current. Managed by curation as a half-open range with an unbounded end for the current version.';

COMMENT ON COLUMN utt.building.source_fid IS 'Technical source key (fid); retained as source metadata, not used for internal logical building references.';

COMMENT ON COLUMN utt.building.building_id_official IS 'Official external logical object identifier (ALKIS uuid); unique per object within the source, repeated across temporal versions.';

COMMENT ON COLUMN utt.building.geom IS 'Polygon des Umrings';

COMMENT ON COLUMN utt.building.building_function IS 'Gebäudefunktion GFK, Schlüssel';

COMMENT ON COLUMN utt.building.building_function_description IS 'Gebäudefunktion GFK, Bezeichnung';

COMMENT ON COLUMN utt.building.position_relative_to_ground IS 'Lage zur Erdoberfläche, Schlüssel';

COMMENT ON COLUMN utt.building.position_relative_to_ground_description IS 'Lage zur Erdoberfläche, Name';

COMMENT ON COLUMN utt.building.storeys_above_ground IS 'Anzahl der Obergeschosse AOG';

COMMENT ON COLUMN utt.building.storeys_below_ground IS 'Anzahl der Untergeschosse AUG';

COMMENT ON COLUMN utt.building.highrise IS 'Hochhaus HOH';

COMMENT ON COLUMN utt.building.building_component_type IS 'Bauart BAT, Schlüssel';

COMMENT ON COLUMN utt.building.building_component_type_description IS 'Bauart BAT, Bezeichnung';

COMMENT ON COLUMN utt.building.name IS 'Gebäudename';

COMMENT ON COLUMN utt.building.building_configuration IS 'Bauweise BAW, Schlüssel';

COMMENT ON COLUMN utt.building.building_configuration_description IS 'Bauweise BAW, Bezeichnung';

COMMENT ON COLUMN utt.building.building_condition IS 'Zustand ZUS, Schlüssel';

COMMENT ON COLUMN utt.building.building_condition_description IS 'Zustand ZUS, Bezeichnung';

COMMENT ON COLUMN utt.building.street_code IS 'Straßenschlüssel LAG';

COMMENT ON COLUMN utt.building.street_name IS 'Straßenname NAMLAG';

COMMENT ON COLUMN utt.building.house_number IS 'Hausnummer HNR';

COMMENT ON COLUMN utt.building.pseudo_house_number IS 'Pseudo-Hausnummer PNR';

COMMENT ON COLUMN utt.building.building_association_number IS 'Laufende Nummer LNR, nicht eindeutig';

COMMENT ON COLUMN utt.building.aaa_description IS 'AAA-Beschreibung, AFIS–ALKIS–ATKIS';

COMMENT ON COLUMN utt.building.heritage_id IS 'ID in Denkmalliste';

COMMENT ON COLUMN utt.building.heritage_type IS 'Art des Denkmals';

COMMENT ON COLUMN utt.building.building_height IS 'Gebäudehöhe';

COMMENT ON COLUMN utt.building.roof_type IS 'Dachart';

COMMENT ON COLUMN utt.building.roof_description IS 'Dachartbeschreibung';

COMMENT ON COLUMN utt.building.heated IS 'Assumption whether a building is heated. Not currently populated by curation.';

COMMENT ON COLUMN utt.building.usage_type IS 'Residential (WG) or non-residential (NWG) building use. Not currently populated by curation.';

COMMENT ON COLUMN utt.building.building_type IS 'Detaillierter Gebäudetyp für projektspezifische Anwendungen';

CREATE INDEX bldg_geom_idx ON utt.building USING gist (geom);

CREATE INDEX idx_building_uuid ON utt.building USING btree (building_id_official);

-- city

CREATE TABLE utt.city (
    row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    city_id_official bigint NOT NULL,
    name character varying NOT NULL,
    geom public.geometry,
    source_valid tstzrange,
    utt_txn tstzrange NOT NULL,
    CONSTRAINT city_source_valid_nonempty CHECK (source_valid IS NULL OR NOT isempty(source_valid)),
    CONSTRAINT city_utt_txn_nonempty CHECK (NOT isempty(utt_txn)),
    CONSTRAINT city_utt_txn_no_overlap EXCLUDE USING gist
        (city_id_official WITH =, utt_txn WITH &&),
    CONSTRAINT city_source_valid_no_overlap EXCLUDE USING gist
        (city_id_official WITH =, source_valid WITH &&, utt_txn WITH &&)
        WHERE (source_valid IS NOT NULL)
);

COMMENT ON COLUMN utt.city.row_id IS 'UTT-internal immutable identifier of this stored city version.';

COMMENT ON COLUMN utt.city.source_valid IS 'Optional source-valid time. City curation derives it from source-backed revision metadata; NULL means the source supplies no usable validity information.';

COMMENT ON COLUMN utt.city.utt_txn IS 'System time when UTT considered this version current. Managed by curation as a half-open range with an unbounded end for the current version.';

COMMENT ON COLUMN utt.city.city_id_official IS 'Official external logical object identifier (lan); unique per object within the source, repeated across temporal versions.';

COMMENT ON COLUMN utt.city.name IS 'Name der Stadt';

COMMENT ON COLUMN utt.city.geom IS 'Polygon des Umrings';

CREATE INDEX city_geom_idx ON utt.city USING gist (geom);

-- district

CREATE TABLE utt.district (
    row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    district_id_official bigint NOT NULL,
    name character varying NOT NULL,
    geom public.geometry,
    source_valid tstzrange,
    utt_txn tstzrange NOT NULL,
    CONSTRAINT district_source_valid_nonempty CHECK (source_valid IS NULL OR NOT isempty(source_valid)),
    CONSTRAINT district_utt_txn_nonempty CHECK (NOT isempty(utt_txn)),
    CONSTRAINT district_utt_txn_no_overlap EXCLUDE USING gist
        (district_id_official WITH =, utt_txn WITH &&),
    CONSTRAINT district_source_valid_no_overlap EXCLUDE USING gist
        (district_id_official WITH =, source_valid WITH &&, utt_txn WITH &&)
        WHERE (source_valid IS NOT NULL)
);

COMMENT ON COLUMN utt.district.row_id IS 'UTT-internal immutable identifier of this stored district version.';

COMMENT ON COLUMN utt.district.source_valid IS 'Optional source-valid time. District curation derives it from source-backed revision metadata; NULL means the source supplies no usable validity information.';

COMMENT ON COLUMN utt.district.utt_txn IS 'System time when UTT considered this version current. Managed by curation as a half-open range with an unbounded end for the current version.';

COMMENT ON COLUMN utt.district.district_id_official IS 'Official external logical object identifier (district identifier); unique per object within the source, repeated across temporal versions.';

COMMENT ON COLUMN utt.district.name IS 'Name des Bezirks';

COMMENT ON COLUMN utt.district.geom IS 'Polygon des Umrings';

CREATE INDEX district_geom_idx ON utt.district USING gist (geom);

-- plot

CREATE TABLE utt.plot (
    row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plot_id_official bigint NOT NULL,
    geom public.geometry,
    parcel_number_numerator bigint,
    cadastral_district_code bigint,
    cadastral_field_number bigint,
    district_id_official bigint,
    source_valid tstzrange,
    utt_txn tstzrange NOT NULL,
    CONSTRAINT plot_source_valid_nonempty CHECK (source_valid IS NULL OR NOT isempty(source_valid)),
    CONSTRAINT plot_utt_txn_nonempty CHECK (NOT isempty(utt_txn)),
    CONSTRAINT plot_utt_txn_no_overlap EXCLUDE USING gist
        (plot_id_official WITH =, utt_txn WITH &&),
    CONSTRAINT plot_source_valid_no_overlap EXCLUDE USING gist
        (plot_id_official WITH =, source_valid WITH &&, utt_txn WITH &&)
        WHERE (source_valid IS NOT NULL)
);

COMMENT ON COLUMN utt.plot.row_id IS 'UTT-internal immutable identifier of this stored plot version.';

COMMENT ON COLUMN utt.plot.source_valid IS 'Optional source-valid time. Plot curation derives its opening from the ALKIS feature beg date; NULL means the source supplies no usable validity information.';

COMMENT ON COLUMN utt.plot.utt_txn IS 'System time when UTT considered this version current. Managed by curation as a half-open range with an unbounded end for the current version.';

COMMENT ON COLUMN utt.plot.plot_id_official IS 'Official external logical object identifier (FSKO); unique per object within the source, repeated across temporal versions.';

COMMENT ON COLUMN utt.plot.geom IS 'Polygon des Umrings';

COMMENT ON COLUMN utt.plot.parcel_number_numerator IS 'Flurstückskennzeichen (Zähler) ZAE';

COMMENT ON COLUMN utt.plot.cadastral_district_code IS 'Gemarkungsschlüssel GMK';

COMMENT ON COLUMN utt.plot.cadastral_field_number IS 'Flurnummer FLN';

COMMENT ON COLUMN utt.plot.district_id_official IS 'Official district identifier; populated from source gdz by utt_pkg.curate_plot().';

CREATE INDEX plot_geom_idx ON utt.plot USING gist (geom);

-- Relationships are added after all referenced tables exist.
-- NULL means unassigned. Referenced rows cannot be deleted or re-keyed while in use.
-- Normally checked per statement; a bulk import may use SET CONSTRAINTS ALL DEFERRED
-- inside its transaction, provided all referenced rows exist before COMMIT.
-- Stable building, plot, block and district identifiers may repeat across temporal
-- versions, so unversioned relationship columns do not reference them directly.
-- building.source_fid is a technical source key and is not a relationship target.
-- Other source identifiers have no corresponding UTT table yet.

-- Pairwise spatial relationships connect immutable entity versions. Their temporal
-- context comes from the referenced endpoint rows, so no third time axis is stored.

-- relation_bldg_block

CREATE TABLE utt.relation_bldg_block (
    building_row_id bigint NOT NULL REFERENCES utt.building (row_id),
    block_row_id bigint NOT NULL REFERENCES utt.block (row_id),
    relative_intersection numeric NOT NULL,
    CONSTRAINT relation_bldg_block_pkey PRIMARY KEY (building_row_id, block_row_id),
    CONSTRAINT relation_bldg_block_fraction CHECK
        (relative_intersection > 0 AND relative_intersection <= 1)
);

COMMENT ON COLUMN utt.relation_bldg_block.building_row_id IS 'Immutable UTT building version participating in this derived spatial relation.';
COMMENT ON COLUMN utt.relation_bldg_block.block_row_id IS 'Immutable UTT block version participating in this derived spatial relation.';
COMMENT ON COLUMN utt.relation_bldg_block.relative_intersection IS 'Intersection area divided by the building version area.';

-- relation_bldg_plot

CREATE TABLE utt.relation_bldg_plot (
    building_row_id bigint NOT NULL REFERENCES utt.building (row_id),
    plot_row_id bigint NOT NULL REFERENCES utt.plot (row_id),
    relative_intersection numeric NOT NULL,
    CONSTRAINT relation_bldg_plot_pkey PRIMARY KEY (building_row_id, plot_row_id),
    CONSTRAINT relation_bldg_plot_fraction CHECK
        (relative_intersection > 0 AND relative_intersection <= 1)
);

COMMENT ON COLUMN utt.relation_bldg_plot.building_row_id IS 'Immutable UTT building version participating in this derived spatial relation.';
COMMENT ON COLUMN utt.relation_bldg_plot.plot_row_id IS 'Immutable UTT plot version participating in this derived spatial relation.';
COMMENT ON COLUMN utt.relation_bldg_plot.relative_intersection IS 'Intersection area divided by the building version area.';

-- relation_plot_block

CREATE TABLE utt.relation_plot_block (
    plot_row_id bigint NOT NULL REFERENCES utt.plot (row_id),
    block_row_id bigint NOT NULL REFERENCES utt.block (row_id),
    relative_intersection numeric NOT NULL,
    CONSTRAINT relation_plot_block_pkey PRIMARY KEY (plot_row_id, block_row_id),
    CONSTRAINT relation_plot_block_fraction CHECK
        (relative_intersection > 0 AND relative_intersection <= 1)
);

COMMENT ON COLUMN utt.relation_plot_block.plot_row_id IS 'Immutable UTT plot version participating in this derived spatial relation.';
COMMENT ON COLUMN utt.relation_plot_block.block_row_id IS 'Immutable UTT block version participating in this derived spatial relation.';
COMMENT ON COLUMN utt.relation_plot_block.relative_intersection IS 'Intersection area divided by the plot version area.';

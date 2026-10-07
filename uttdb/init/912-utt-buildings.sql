-- Selected EnergyMap table structures, moved from emc to utt.
-- Fresh initialization only; no source data or EnergyMap workflows are imported.
-- Preserve original columns, comments, primary keys and indexes; add UTT integrity constraints.
-- Access follows the UTT group-role defaults established by 902.

-- address

CREATE TABLE utt.address (
    row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    address_id bigint NOT NULL,
    geom public.geometry,
    bldg_fid bigint,
    fsko bigint,
    street_name character varying,
    street_id character varying,
    house_no integer,
    house_no_suffix character varying,
    pca_id bigint,
    blk_id bigint,
    district_id bigint,
    district_name character varying,
    place_id character varying,
    place_name character varying,
    planning_area_no bigint,
    planning_area_name character varying,
    address_date timestamp without time zone,
    street_date timestamp without time zone,
    quality character varying,
    type character varying,
    hko_id character varying,
    ens_id bigint,
    bldg_uuid character varying,
    source_valid tstzrange,
    utt_txn tstzrange NOT NULL,
    CONSTRAINT address_source_valid_nonempty CHECK (source_valid IS NULL OR NOT isempty(source_valid)),
    CONSTRAINT address_utt_txn_nonempty CHECK (NOT isempty(utt_txn)),
    CONSTRAINT address_utt_txn_no_overlap EXCLUDE USING gist
        (address_id WITH =, utt_txn WITH &&),
    CONSTRAINT address_source_valid_no_overlap EXCLUDE USING gist
        (address_id WITH =, source_valid WITH &&, utt_txn WITH &&)
        WHERE (source_valid IS NOT NULL)
);

COMMENT ON COLUMN utt.address.row_id IS 'UTT-internal immutable identifier of this stored address version.';

COMMENT ON COLUMN utt.address.source_valid IS 'Optional source-valid time. Address curation derives it from the RBS source field aufn_dt; NULL means the source supplies no usable validity information.';

COMMENT ON COLUMN utt.address.utt_txn IS 'System time when UTT considered this version current. Managed by curation as a half-open range with an unbounded end for the current version.';

COMMENT ON COLUMN utt.address.address_id IS 'AdressID (adr_ident); Datenquelle: Adressen Regionales Bezugssystem (RBS), https://gdi.berlin.de/data/adressen_rbs/docs/Datenformatbeschreibung_RBS_Adressen.pdf';

COMMENT ON COLUMN utt.address.geom IS 'Punkt im Koordinatensystem; Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.bldg_fid IS 'ID des zugehörigen Gebäudes in emc.building; Datenquelle: POSTGIS (ST_WITHIN), Punkt in Polygon';

COMMENT ON COLUMN utt.address.fsko IS 'ID des zugehörigen Flurstücks; Datenquelle: POSTGIS (ST_WITHIN), Punkt in Polygon';

COMMENT ON COLUMN utt.address.street_name IS 'Straßenname (strnam); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.street_id IS 'Straßennummer (strnr); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.house_no IS 'Hausnummer (hausnr); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.house_no_suffix IS 'Hausnummer-Zusatz (hausnrz); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.pca_id IS 'Postleitzahl (postleit); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.blk_id IS 'Blocknummer (blk); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.district_id IS 'Langer Berliner Bezirksschlüssel, aus dem zweistelligen RBS-Feld bez abgeleitet.';

COMMENT ON COLUMN utt.address.district_name IS 'Bezirk (bez_name); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.place_id IS 'Ortsteilschlüssel (ot); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.place_name IS 'Ortsteil (ot_name); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.planning_area_no IS 'Planungsraum-Schlüssel (plr); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.planning_area_name IS 'Planungsraum (plr_name); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.address_date IS 'Aufnahmedatum der Adresse (aufn_dt); Datenquelle: Adressen Regionales Bezugssystem (RBS).';

COMMENT ON COLUMN utt.address.street_date IS 'Not supplied by the current RBS address source; remains NULL during address curation.';

COMMENT ON COLUMN utt.address.quality IS 'Not supplied by the current RBS address source; remains NULL during address curation.';

COMMENT ON COLUMN utt.address.type IS 'Straßentyp (str_typ); distinguishes RBS streets, places and other object types.';

COMMENT ON COLUMN utt.address.hko_id IS 'Not supplied by the current RBS address source; remains NULL during address curation.';

COMMENT ON COLUMN utt.address.ens_id IS 'ID des zugehörigen Ensembles; Datenquelle: POSTGIS (ST_WITHIN), Punkt in Polygon';

CREATE INDEX address_geom_idx ON utt.address USING gist (geom);

-- block

CREATE TABLE utt.block (
    row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    blk_id bigint NOT NULL,
    geom public.geometry,
    planning_area_no bigint,
    in_district bigint,
    population_density numeric,
    population integer,
    pop_age_under6 integer,
    pop_age_6_u10 integer,
    pop_age_10_u18 integer,
    pop_age_18_u65 integer,
    pop_age_65_u70 integer,
    pop_age_70_u75 integer,
    pop_age_75_u80 integer,
    pop_age_over80 integer,
    in_grosssiedlung character varying,
    wohnatlas_prognoseraum character varying,
    angebotsmieten_2020 numeric,
    aenderung_anteil_leistungsempfaenger numeric,
    anteil_leistungsempfaenger numeric,
    anteil_sozialwohnungen_2020 numeric,
    anteil_wohnungsgesellschaften numeric,
    entwicklung_2015_2020 numeric,
    wohndauer numeric,
    wohnungsumwandlungen numeric,
    wohnungsumwandlungen1520 numeric,
    wohnungsverkaeufe numeric,
    wohnungsverkaeufe1520 numeric,
    wohnatlas_schluessel character varying,
    esix_value_2022 numeric,
    esix_level_2022 integer,
    gesix_value_2022 numeric,
    gesix_level_2022 integer,
    woz integer,
    woz_name character varying,
    grz integer,
    grz_name character varying,
    ststrnr integer,
    ststrname character varying,
    typ integer,
    typklar character varying,
    nutz integer,
    nutzung character varying,
    social_index integer,
    social_index_dynamics integer,
    social_index_description character varying,
    gross_volume_bldgs numeric,
    volume_bldgs_per_block_area numeric,
    centroid public.geometry,
    source_valid tstzrange,
    utt_txn tstzrange NOT NULL,
    CONSTRAINT block_source_valid_nonempty CHECK (source_valid IS NULL OR NOT isempty(source_valid)),
    CONSTRAINT block_utt_txn_nonempty CHECK (NOT isempty(utt_txn)),
    CONSTRAINT block_utt_txn_no_overlap EXCLUDE USING gist
        (blk_id WITH =, utt_txn WITH &&),
    CONSTRAINT block_source_valid_no_overlap EXCLUDE USING gist
        (blk_id WITH =, source_valid WITH &&, utt_txn WITH &&)
        WHERE (source_valid IS NOT NULL)
);

COMMENT ON COLUMN utt.block.row_id IS 'UTT-internal immutable identifier of this stored block version.';

COMMENT ON COLUMN utt.block.source_valid IS 'Optional source-valid time. Block curation derives it from the source datum field; NULL means the source supplies no usable validity information.';

COMMENT ON COLUMN utt.block.utt_txn IS 'System time when UTT considered this version current. Managed by curation as a half-open range with an unbounded end for the current version.';

COMMENT ON COLUMN utt.block.blk_id IS 'ID des Blocks aus Datenquelle; Datenquelle: FIS Broker, ALKIS Berlin Statistische Blöcke';

COMMENT ON COLUMN utt.block.geom IS 'Polygon des Umrings; Datenquelle: FIS Broker, ALKIS Berlin Statistische Blöcke';

COMMENT ON COLUMN utt.block.centroid IS 'Derived representative point: geometric centroid when covered by geom, otherwise ST_PointOnSurface so the point lies within the block.';

COMMENT ON COLUMN utt.block.planning_area_no IS 'Planungsraum; Datenquelle: FIS Broker, ALKIS Berlin Statistische Blöcke';

COMMENT ON COLUMN utt.block.in_district IS 'hauptsächlich in Bezirk; Datenquelle: POSTGIS Prozedur emc.update_block';

COMMENT ON COLUMN utt.block.population_density IS 'Einwohnerdichte; Datenquelle: FIS Broker, Einwohnerdichte 2022, https://www.berlin.de/umweltatlas/nutzung/einwohnerdichte/';

COMMENT ON COLUMN utt.block.population IS 'Einwohner insgesamt; Datenquelle: FIS Broker, Einwohnerdichte 2022, https://www.berlin.de/umweltatlas/nutzung/einwohnerdichte/';

COMMENT ON COLUMN utt.block.pop_age_under6 IS 'Einwohner unter 6 Jahren; Datenquelle: FIS Broker, Einwohnerdichte 2022, https://www.berlin.de/umweltatlas/nutzung/einwohnerdichte/';

COMMENT ON COLUMN utt.block.pop_age_6_u10 IS 'Einwohner zwischen 6 und unter 10 Jahren; Datenquelle: FIS Broker, Einwohnerdichte 2022, https://www.berlin.de/umweltatlas/nutzung/einwohnerdichte/';

COMMENT ON COLUMN utt.block.pop_age_10_u18 IS 'Einwohner zwischen 10 und unter 18 Jahren; Datenquelle: FIS Broker, Einwohnerdichte 2022, https://www.berlin.de/umweltatlas/nutzung/einwohnerdichte/';

COMMENT ON COLUMN utt.block.pop_age_18_u65 IS 'Einwohner zwischen 18 und unter 65 Jahren; Datenquelle: FIS Broker, Einwohnerdichte 2022, https://www.berlin.de/umweltatlas/nutzung/einwohnerdichte/';

COMMENT ON COLUMN utt.block.pop_age_65_u70 IS 'Einwohner zwischen 65 und unter 70 Jahren; Datenquelle: FIS Broker, Einwohnerdichte 2022, https://www.berlin.de/umweltatlas/nutzung/einwohnerdichte/';

COMMENT ON COLUMN utt.block.pop_age_70_u75 IS 'Einwohner zwischen 70 und unter 75 Jahren; Datenquelle: FIS Broker, Einwohnerdichte 2022, https://www.berlin.de/umweltatlas/nutzung/einwohnerdichte/';

COMMENT ON COLUMN utt.block.pop_age_75_u80 IS 'Einwohner zwischen 75 und unter 80 Jahren; Datenquelle: FIS Broker, Einwohnerdichte 2022, https://www.berlin.de/umweltatlas/nutzung/einwohnerdichte/';

COMMENT ON COLUMN utt.block.pop_age_over80 IS 'Einwohner über 80 Jahre; Datenquelle: FIS Broker, Einwohnerdichte 2022, https://www.berlin.de/umweltatlas/nutzung/einwohnerdichte/';

COMMENT ON COLUMN utt.block.in_grosssiedlung IS 'Block ist Teil eines Großsiedlungsgebiets; Datenquelle: FIS Broker, Großsiedlungen und Fördergebiete, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/grossiedlung.html';

COMMENT ON COLUMN utt.block.wohnatlas_prognoseraum IS 'Block gehört zu diesem Prognoseraum; Datenquelle: FIS Broker, Wohnatlas 2020, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/wohnatlas/2020/wa_angebmiete20.html';

COMMENT ON COLUMN utt.block.angebotsmieten_2020 IS 'Angebotsmieten 2020 in Euro pro m2; Datenquelle: FIS Broker, Wohnatlas 2020, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/wohnatlas/2020/wa_angebmiete20.html';

COMMENT ON COLUMN utt.block.aenderung_anteil_leistungsempfaenger IS 'Änderungen am Teil der Leistungsempfänger 2020; Datenquelle: FIS Broker, Wohnatlas 2020, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/wohnatlas/2020/wa_SGBII_aend1520.html';

COMMENT ON COLUMN utt.block.anteil_leistungsempfaenger IS 'Anteil der Leistungsempfänger nach SGB II 2020; Datenquelle: FIS Broker, Wohnatlas 2020, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/wohnatlas/2020/wa_SGBII_ew20.html';

COMMENT ON COLUMN utt.block.anteil_sozialwohnungen_2020 IS 'Anteil der Sozialwohnungen am Wohnungsbestand 2020; Datenquelle: FIS Broker, Wohnatlas 2020, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/wohnatlas/2020/wa_anteil_sozialwhg20.html';

COMMENT ON COLUMN utt.block.anteil_wohnungsgesellschaften IS 'Anteil der Wohnungen von städtischen Wohnungsbaugesellschaften am Gesamtbestand 2020; Datenquelle: FIS Broker, Wohnatlas 2020, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/wohnatlas/2020/wa_anteil_staedt_we20.html';

COMMENT ON COLUMN utt.block.entwicklung_2015_2020 IS 'Prozentuale Veränderungen der Einwohnerzahlen 2015 - 2020; Datenquelle: FIS Broker, Wohnatlas 2020, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/wohnatlas/2020/wa_bevaend1520.html';

COMMENT ON COLUMN utt.block.wohndauer IS 'Anteil Einwohner mit mind. 5-jähriger Wohndauer am 31.12.2020; Datenquelle: FIS Broker, Wohnatlas 2020, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/wohnatlas/2020/wa_wohndauer520.html';

COMMENT ON COLUMN utt.block.wohnungsumwandlungen IS 'Umgewandelte Wohnungen 2020 von Miet- in Eigentumswohnungen; Datenquelle: FIS Broker, Wohnatlas 2020, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/wohnatlas/2020/wa_umwandlung20.html';

COMMENT ON COLUMN utt.block.wohnungsumwandlungen1520 IS 'Umgewandelte Wohnungen 2015 - 2020 pro 1.000 Wohnungen; Datenquelle: FIS Broker, Wohnatlas 2020, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/wohnatlas/2020/wa_umwandlung1520.html';

COMMENT ON COLUMN utt.block.wohnungsverkaeufe IS 'Wohnungsverkäufe 2020 pro 1.000 Wohnungen; Datenquelle: FIS Broker, Wohnatlas 2020, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/wohnatlas/2020/wa_verkaeufe20.html';

COMMENT ON COLUMN utt.block.wohnungsverkaeufe1520 IS 'Wohnungsverkäufe 2015 - 2020 pro 1.000 Wohnungen; Datenquelle: FIS Broker, Wohnatlas 2020, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/wohnatlas/2020/wa_verkaeufe1520.html';

COMMENT ON COLUMN utt.block.wohnatlas_schluessel IS 'Technischer Schlüssel in Datenquelle; Datenquelle: FIS Broker, Wohnatlas 2020, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/wohnatlas/2020/wa_angebmiete20.html';

COMMENT ON COLUMN utt.block.esix_value_2022 IS 'Erwerbs- und Sozialindex ESIX 2022 (Wert); Datenquelle: FIS Broker, Gesundheits- und Sozialstrukturindex 2022, https://www.berlin.de/sen/gesundheit/service/gesundheitsberichterstattung/gesundheit-und-sozialstruktur/';

COMMENT ON COLUMN utt.block.esix_level_2022 IS 'Erwerbs- und Sozialindex ESIX 2022 (Zugeordnete Schicht); Datenquelle: FIS Broker, Gesundheits- und Sozialstrukturindex 2022, https://www.berlin.de/sen/gesundheit/service/gesundheitsberichterstattung/gesundheit-und-sozialstruktur/';

COMMENT ON COLUMN utt.block.gesix_value_2022 IS 'Gesundheits- und Sozialindex ESIX 2022 (Wert); Datenquelle: FIS Broker, Gesundheits- und Sozialstrukturindex 2022, https://www.berlin.de/sen/gesundheit/service/gesundheitsberichterstattung/gesundheit-und-sozialstruktur/';

COMMENT ON COLUMN utt.block.gesix_level_2022 IS 'Gesundheits- und Sozialindex ESIX 2022 (Zugeordnete Schicht); Datenquelle: FIS Broker, Gesundheits- und Sozialstrukturindex 2022, https://www.berlin.de/sen/gesundheit/service/gesundheitsberichterstattung/gesundheit-und-sozialstruktur/';

COMMENT ON COLUMN utt.block.woz IS 'Nutzung der bebauten Fläche (Code); Datenquelle: FIS Broker, Flächentypen differenziert 2021, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/umweltatlas/datenformatbeschreibung/Datenformatbeschreibung_flaechennutzung_stadtstruktur2021.pdf';

COMMENT ON COLUMN utt.block.woz_name IS 'Nutzung der bebauten Fläche (Klartext); Datenquelle: FIS Broker, Flächentypen differenziert 2021, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/umweltatlas/datenformatbeschreibung/Datenformatbeschreibung_flaechennutzung_stadtstruktur2021.pdf';

COMMENT ON COLUMN utt.block.grz IS 'Grün- und Freiflächennutzung (Code); Datenquelle: FIS Broker, Flächentypen differenziert 2021, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/umweltatlas/datenformatbeschreibung/Datenformatbeschreibung_flaechennutzung_stadtstruktur2021.pdf';

COMMENT ON COLUMN utt.block.grz_name IS 'Grün- und Freiflächennutzung (Klartext); Datenquelle: FIS Broker, Flächentypen differenziert 2021, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/umweltatlas/datenformatbeschreibung/Datenformatbeschreibung_flaechennutzung_stadtstruktur2021.pdf';

COMMENT ON COLUMN utt.block.ststrnr IS 'Stadtstrukturtyp (Code); Datenquelle: FIS Broker, Flächentypen differenziert 2021, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/umweltatlas/datenformatbeschreibung/Datenformatbeschreibung_flaechennutzung_stadtstruktur2021.pdf';

COMMENT ON COLUMN utt.block.ststrname IS 'Stadtstrukturtyp (Klartext); Datenquelle: FIS Broker, Flächentypen differenziert 2021, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/umweltatlas/datenformatbeschreibung/Datenformatbeschreibung_flaechennutzung_stadtstruktur2021.pdf';

COMMENT ON COLUMN utt.block.typ IS 'Flächentyp (Code); Datenquelle: FIS Broker, Flächentypen differenziert 2021, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/umweltatlas/datenformatbeschreibung/Datenformatbeschreibung_flaechennutzung_stadtstruktur2021.pdf';

COMMENT ON COLUMN utt.block.typklar IS 'Flächentyp (Klartext); Datenquelle: FIS Broker, Flächentypen differenziert 2021, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/umweltatlas/datenformatbeschreibung/Datenformatbeschreibung_flaechennutzung_stadtstruktur2021.pdf';

COMMENT ON COLUMN utt.block.nutz IS 'Flächennutzung Grünvorrang (Code); Datenquelle: FIS Broker, Flächentypen differenziert 2021, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/umweltatlas/datenformatbeschreibung/Datenformatbeschreibung_flaechennutzung_stadtstruktur2021.pdf';

COMMENT ON COLUMN utt.block.nutzung IS 'Flächennutzung Grünvorrang (Klartext); Datenquelle: FIS Broker, Flächentypen differenziert 2021, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/umweltatlas/datenformatbeschreibung/Datenformatbeschreibung_flaechennutzung_stadtstruktur2021.pdf';

COMMENT ON COLUMN utt.block.social_index IS 'Status-Index (4 Gruppen: numerische Zuordnung); Datenquelle: FIS Broker, Monitoring Soziale Stadtentwicklung Berlin 2021, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/MSS/MSS_2021.html';

COMMENT ON COLUMN utt.block.social_index_dynamics IS 'Dynamik-Index (3 Gruppen: numerische Zuordnung); Datenquelle: FIS Broker, Monitoring Soziale Stadtentwicklung Berlin 2021, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/MSS/MSS_2021.html';

COMMENT ON COLUMN utt.block.social_index_description IS 'Verbale Zuordnung Status und Dynamik; Datenquelle: FIS Broker, Monitoring Soziale Stadtentwicklung Berlin 2021, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/MSS/MSS_2021.html';

CREATE INDEX block_geom_idx ON utt.block USING gist (geom);
CREATE INDEX block_centroid_idx ON utt.block USING gist (centroid);

-- building

CREATE TABLE utt.building (
    row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fid bigint NOT NULL,
    uuid character varying NOT NULL,
    geom public.geometry,
    displayed boolean,
    gfk integer,
    bezgfk character varying,
    ofl integer,
    bezofl character varying,
    aog integer,
    aug integer,
    hoh boolean,
    bat integer,
    bezbat character varying,
    nam character varying,
    baw integer,
    bezbaw character varying,
    zus integer,
    bezzus character varying,
    lag character varying,
    namlag character varying,
    hnr character varying,
    pnr character varying,
    lnr character varying,
    bezeich character varying,
    heritage_id character varying,
    heritage_type character varying,
    height numeric,
    roof_type character varying,
    roof_description character varying,
    heated boolean,
    usage_type text,
    building_type text,
    last_modified timestamp without time zone,
    gf double precision,
    building_type_publication text,
    block_edge_id character varying,
    heated_area_corrected numeric,
    heated_area_correction_factor numeric,
    data_source_height text,
    height_simstadt numeric,
    source_valid tstzrange,
    utt_txn tstzrange NOT NULL,
    CONSTRAINT building_source_valid_nonempty CHECK (source_valid IS NULL OR NOT isempty(source_valid)),
    CONSTRAINT building_utt_txn_nonempty CHECK (NOT isempty(utt_txn)),
    CONSTRAINT building_utt_txn_no_overlap EXCLUDE USING gist
        (uuid WITH =, utt_txn WITH &&),
    CONSTRAINT building_source_valid_no_overlap EXCLUDE USING gist
        (uuid WITH =, source_valid WITH &&, utt_txn WITH &&)
        WHERE (source_valid IS NOT NULL)
);

COMMENT ON COLUMN utt.building.row_id IS 'UTT-internal immutable identifier of this stored building version.';

COMMENT ON COLUMN utt.building.source_valid IS 'Optional source-valid time. Building curation derives it from source-backed revision metadata; NULL means the source supplies no usable validity information.';

COMMENT ON COLUMN utt.building.utt_txn IS 'System time when UTT considered this version current. Managed by curation as a half-open range with an unbounded end for the current version.';

COMMENT ON COLUMN utt.building.fid IS 'Technischer Schlüssel in Datenquelle; Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.uuid IS 'ALKIS-Objekt-ID, ungeeignet als Primary Key da alphanumerisch; Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.geom IS 'Polygon des Umrings; Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.displayed IS 'in EnergyMap betrachtes Gebäude, Wert definiert mittels Funktion emc.display_bldg_type()';

COMMENT ON COLUMN utt.building.gfk IS 'Gebäudefunktion (Schlüssel); Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.bezgfk IS 'Gebäudefunktion (Bezeichnung); Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.ofl IS 'Lage zur Erdoberfläche (Schlüssel); Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.bezofl IS 'Lage zur Erdoberfläche (Bezeichnung); Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.aog IS 'Anzahl der Obergeschosse	; Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.aug IS 'Anzahl der Untergeschosse; Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.hoh IS 'Hochhaus; Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.bat IS 'Bauart (Schlüssel); Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.bezbat IS 'Bauart (Bezeichnung); Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.nam IS 'Name; Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.baw IS 'Bauweise (Schlüssel); Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.bezbaw IS 'Bauweise (Bezeichnung); Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.zus IS 'Zustand (Schlüssel); Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.bezzus IS 'Zustand (Bezeichnung); Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.lag IS 'Straßenschlüssel; Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.namlag IS 'Straßenname; Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.hnr IS 'Hausnummer; Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.pnr IS 'Pseudonummer; Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.lnr IS 'Laufende Nummer; Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.bezeich IS 'AAA-Beschreibung; Datenquelle: FIS Broker, ALKIS Berlin Gebäude';

COMMENT ON COLUMN utt.building.heritage_id IS 'ID in Denkmalliste Berlin; Datenquelle: FIS Broker, Denkmalkarte Berlin, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/denkmal.html';

COMMENT ON COLUMN utt.building.heritage_type IS 'Art des Denkmals; Datenquelle: FIS Broker, Denkmalkarte Berlin, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/denkmal.html';

COMMENT ON COLUMN utt.building.height IS 'Gebäudehöhe; Datenquelle: FIS Broker, Gebäudehöhen 2022, https://www.berlin.de/umweltatlas/nutzung/gebaeudehoehen/fortlaufend-aktualisiert/zusammenfassung/';

COMMENT ON COLUMN utt.building.roof_type IS 'Dachart; Datenquelle: FIS Broker, Gebäudehöhen 2022, https://www.berlin.de/umweltatlas/nutzung/gebaeudehoehen/fortlaufend-aktualisiert/zusammenfassung/';

COMMENT ON COLUMN utt.building.roof_description IS 'Dachartbeschreibung; Datenquelle: FIS Broker, Gebäudehöhen 2022, https://www.berlin.de/umweltatlas/nutzung/gebaeudehoehen/fortlaufend-aktualisiert/zusammenfassung/';

COMMENT ON COLUMN utt.building.heated IS 'Annahme ob Gebäude beheizt oder nicht beheizt, Wert definiert mittels Funktion emc.display_bldg_type()';

COMMENT ON COLUMN utt.building.usage_type IS 'Unterscheidung zwischen Wohngebäude (WG) und Nicht-Wohngebäude (NWG), Wert definiert mittels Funktion emc.display_bldg_type()';

COMMENT ON COLUMN utt.building.building_type IS 'Detaillierter Gebäudetyp für SimStadt oder Differenzierung im neuronalen Netz, Wert definiert mittels Funktion emc.display_bldg_type()';

CREATE INDEX bldg_geom_idx ON utt.building USING gist (geom);

CREATE INDEX idx_building_uuid ON utt.building USING btree (uuid);

CREATE INDEX idx_building_uuid_type ON utt.building USING btree (uuid, building_type_publication);

-- city

CREATE TABLE utt.city (
    row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id bigint NOT NULL,
    name character varying NOT NULL,
    geom public.geometry,
    source_valid tstzrange,
    utt_txn tstzrange NOT NULL,
    CONSTRAINT city_source_valid_nonempty CHECK (source_valid IS NULL OR NOT isempty(source_valid)),
    CONSTRAINT city_utt_txn_nonempty CHECK (NOT isempty(utt_txn)),
    CONSTRAINT city_utt_txn_no_overlap EXCLUDE USING gist
        (id WITH =, utt_txn WITH &&),
    CONSTRAINT city_source_valid_no_overlap EXCLUDE USING gist
        (id WITH =, source_valid WITH &&, utt_txn WITH &&)
        WHERE (source_valid IS NOT NULL)
);

COMMENT ON COLUMN utt.city.row_id IS 'UTT-internal immutable identifier of this stored city version.';

COMMENT ON COLUMN utt.city.source_valid IS 'Optional source-valid time. City curation derives it from source-backed revision metadata; NULL means the source supplies no usable validity information.';

COMMENT ON COLUMN utt.city.utt_txn IS 'System time when UTT considered this version current. Managed by curation as a half-open range with an unbounded end for the current version.';

COMMENT ON COLUMN utt.city.id IS 'ID der Stadt in emc';

COMMENT ON COLUMN utt.city.name IS 'Name der Stadt';

COMMENT ON COLUMN utt.city.geom IS 'Polygon des Umrings; Datenquelle: FIS Broker, ALKIS Berlin Landesgrenze';

CREATE INDEX city_geom_idx ON utt.city USING gist (geom);

-- district

CREATE TABLE utt.district (
    row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dist_id bigint NOT NULL,
    name character varying NOT NULL,
    geom public.geometry,
    source_valid tstzrange,
    utt_txn tstzrange NOT NULL,
    CONSTRAINT district_source_valid_nonempty CHECK (source_valid IS NULL OR NOT isempty(source_valid)),
    CONSTRAINT district_utt_txn_nonempty CHECK (NOT isempty(utt_txn)),
    CONSTRAINT district_utt_txn_no_overlap EXCLUDE USING gist
        (dist_id WITH =, utt_txn WITH &&),
    CONSTRAINT district_source_valid_no_overlap EXCLUDE USING gist
        (dist_id WITH =, source_valid WITH &&, utt_txn WITH &&)
        WHERE (source_valid IS NOT NULL)
);

COMMENT ON COLUMN utt.district.row_id IS 'UTT-internal immutable identifier of this stored district version.';

COMMENT ON COLUMN utt.district.source_valid IS 'Optional source-valid time. District curation derives it from source-backed revision metadata; NULL means the source supplies no usable validity information.';

COMMENT ON COLUMN utt.district.utt_txn IS 'System time when UTT considered this version current. Managed by curation as a half-open range with an unbounded end for the current version.';

COMMENT ON COLUMN utt.district.dist_id IS 'ID des Bezirks; Datenquelle: FIS Broker, ALKIS Berlin Bezirke im Liegenschaftskataster';

COMMENT ON COLUMN utt.district.name IS 'Name des Bezirks; Datenquelle: FIS Broker, ALKIS Berlin Bezirke im Liegenschaftskataster';

COMMENT ON COLUMN utt.district.geom IS 'Polygon des Umrings; Datenquelle: FIS Broker, ALKIS Berlin Bezirke im Liegenschaftskataster';

CREATE INDEX district_geom_idx ON utt.district USING gist (geom);

-- plot

CREATE TABLE utt.plot (
    row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fsko bigint NOT NULL,
    geom public.geometry,
    zae bigint,
    gmk bigint,
    fln bigint,
    in_district bigint,
    owner_type text,
    owner_type_description text,
    plot_price_2022 numeric,
    plot_primary_usage_2022 character varying,
    plot_price_2023 numeric,
    plot_primary_usage_2023 character varying,
    avg_no_storeys_2022 numeric,
    avg_no_storeys_2023 numeric,
    owner_type_nas text,
    block_edge_id character varying,
    block_edge_match_type character varying,
    has_bldgs boolean,
    source_valid tstzrange,
    utt_txn tstzrange NOT NULL,
    CONSTRAINT plot_source_valid_nonempty CHECK (source_valid IS NULL OR NOT isempty(source_valid)),
    CONSTRAINT plot_utt_txn_nonempty CHECK (NOT isempty(utt_txn)),
    CONSTRAINT plot_utt_txn_no_overlap EXCLUDE USING gist
        (fsko WITH =, utt_txn WITH &&),
    CONSTRAINT plot_source_valid_no_overlap EXCLUDE USING gist
        (fsko WITH =, source_valid WITH &&, utt_txn WITH &&)
        WHERE (source_valid IS NOT NULL)
);

COMMENT ON COLUMN utt.plot.row_id IS 'UTT-internal immutable identifier of this stored plot version.';

COMMENT ON COLUMN utt.plot.source_valid IS 'Optional source-valid time. Plot curation derives its opening from the ALKIS feature beg date; NULL means the source supplies no usable validity information.';

COMMENT ON COLUMN utt.plot.utt_txn IS 'System time when UTT considered this version current. Managed by curation as a half-open range with an unbounded end for the current version.';

COMMENT ON COLUMN utt.plot.fsko IS 'Flurstückskennzeichen; Datenquelle: FIS Broker, Flurstücke im Liegenschaftskataster';

COMMENT ON COLUMN utt.plot.geom IS 'Polygon des Umrings; Datenquelle: FIS Broker, Flurstücke im Liegenschaftskataster';

COMMENT ON COLUMN utt.plot.zae IS 'Flurstückskennzeichen (Zähler) ; Datenquelle: FIS Broker, Flurstücke im Liegenschaftskataster';

COMMENT ON COLUMN utt.plot.gmk IS 'Gemarkungsschlüssel; Datenquelle: FIS Broker, Flurstücke im Liegenschaftskataster';

COMMENT ON COLUMN utt.plot.fln IS 'Flurnummer; Datenquelle: FIS Broker, Flurstücke im Liegenschaftskataster';

COMMENT ON COLUMN utt.plot.in_district IS 'befindet sich in diesem Bezirk; Datenquelle: POSTGIS Prozedur emc.update_plot';

COMMENT ON COLUMN utt.plot.owner_type IS 'Nummer der Eigentümerart; Datenquelle: für Charlottenburg-Wilmersdorf: BezCW über interne Kanäle; freigegeben für EnergyMap, interne Nutzung; Mögliche Werte: 1000, 2000, 3100, 4000, 5100, 5300, 5920, 6000; Quelle für Rest-Berlin: FIS Broker, Liegenschaftsplan, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/datenformatbeschreibung/Datenformatbeschreibung_Liegenschaftsplan.pdf; Mögliche Werte: 4000, 5100, 5920, 6000';

COMMENT ON COLUMN utt.plot.owner_type_description IS 'Eigentümerart Klartext; Datenquelle: für Charlottenburg-Wilmersdorf: BezCW über interne Kanäle; freigegeben für EnergyMap, interne Nutzung; Mögliche Werte: 1000, 2000, 3100, 4000, 5100, 5300, 5920, 6000; Quelle für Rest-Berlin: FIS Broker, Liegenschaftsplan, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/datenformatbeschreibung/Datenformatbeschreibung_Liegenschaftsplan.pdf; Mögliche Werte: 4000, 5100, 5920, 6000';

COMMENT ON COLUMN utt.plot.plot_price_2022 IS 'Bodenrichtwert 2022; Datenquelle: FIS Broker, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/brw/BRW_Vorblatt_2022.pdf';

COMMENT ON COLUMN utt.plot.plot_primary_usage_2022 IS 'Flächennutzung 2022; Datenquelle: FIS Broker, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/brw/BRW_Vorblatt_2022.pdf';

COMMENT ON COLUMN utt.plot.plot_price_2023 IS 'Bodenrichtwert 2023; Datenquelle: FIS Broker, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/brw/BRW_Vorblatt_2023.pdf';

COMMENT ON COLUMN utt.plot.plot_primary_usage_2023 IS 'Flächennutzung 2023; Datenquelle: FIS Broker, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/brw/BRW_Vorblatt_2023.pdf';

COMMENT ON COLUMN utt.plot.avg_no_storeys_2022 IS 'Mittlere Geschosszahl 2022; Datenquelle: FIS Broker, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/brw/BRW_Vorblatt_2022.pdf';

COMMENT ON COLUMN utt.plot.avg_no_storeys_2023 IS 'Mittlere Geschosszahl 2023; Datenquelle: FIS Broker, https://fbinter.stadt-berlin.de/fb_daten/beschreibung/brw/BRW_Vorblatt_2023.pdf';

COMMENT ON COLUMN utt.plot.owner_type_nas IS 'Nummer der Eigentümerart aus NAS-Format; Datenquelle: ALKIS Gesamtdatenbestand im NAS-Format, Filterung mit Jupyter-Notebook, dann DB Prozedur update_plot_owner_from_nas()';

CREATE INDEX plot_geom_idx ON utt.plot USING gist (geom);

-- Relationships are added after all referenced tables exist.
-- NULL means unassigned. Referenced rows cannot be deleted or re-keyed while in use.
-- Normally checked per statement; a bulk import may use SET CONSTRAINTS ALL DEFERRED
-- inside its transaction, provided all referenced rows exist before COMMIT.
-- Stable building, plot, block and district identifiers may repeat across temporal
-- versions, so unversioned relationship columns do not reference them directly.
-- building.fid is a technical source key and is not a relationship target.
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

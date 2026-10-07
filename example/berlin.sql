-- Run as DBA on a fresh UTTDB after init. Each registration commits separately.
-- After a failed registration, run ROLLBACK; before retrying that registration.
-- Only layers used by the curation routines are stored.
-- With psql: psql -v ON_ERROR_STOP=1 -f example/berlin.sql


-- Register various sources from Geoportal Berlin (gdi.berlin.de)
BEGIN;
  SELECT * FROM utt_pkg.mirror_register_wfs_source(
    'berlin_alkis', 'https://gdi.berlin.de/services/wfs/alkis'
  );
COMMIT;

BEGIN;
  SELECT * FROM utt_pkg.mirror_register_wfs_source(
    'berlin_alkis_gebaeude', 'https://gdi.berlin.de/services/wfs/alkis_gebaeude'
  );
COMMIT;

BEGIN;
  SELECT * FROM utt_pkg.mirror_register_wfs_source(
    'berlin_bloecke', 'https://gdi.berlin.de/services/wfs/bloecke'
  );
COMMIT;

BEGIN;
  SELECT * FROM utt_pkg.mirror_register_wfs_source(
    'berlin_adressen', 'https://gdi.berlin.de/services/wfs/adressen_rbs'
  );
COMMIT;

BEGIN;
  SELECT * FROM utt_pkg.mirror_register_wfs_source(
    'berlin_baumbestand', 'https://gdi.berlin.de/services/wfs/baumbestand'
  );
COMMIT;

-- Example of a file registration, file must be loaded into folder ./uttdb/source_files first
-- BEGIN;
--   -- Keep this file in source-files before running the setup.
--   SELECT * FROM utt_pkg.mirror_register_file_source(
--     'geo_waerme', '/source-files/q_total_RM_Paper.tif'
--   );
-- COMMIT;

-- Store selected foreign source tables in local mirror storage for fast access
BEGIN;
  SELECT utt_pkg.mirror_store_layer('berlin_alkis', 'alkis:land');
  SELECT utt_pkg.mirror_store_layer('berlin_alkis', 'alkis:bezirk');
  SELECT utt_pkg.mirror_store_layer('berlin_alkis', 'alkis:flurstuecke');
  SELECT utt_pkg.mirror_store_layer('berlin_alkis_gebaeude', 'alkis_gebaeude:gebaeude');
  SELECT utt_pkg.mirror_store_layer('berlin_bloecke', 'bloecke:rbs_bloecke');
  SELECT utt_pkg.mirror_store_layer('berlin_adressen', 'adressen_rbs:adressen_rbs');
COMMIT;

-- Curate data from locally stored source tables into utt structures
BEGIN;
  SELECT utt_pkg.curate_city();
  SELECT utt_pkg.curate_district();
  SELECT utt_pkg.curate_block();
  SELECT utt_pkg.curate_plot();
  SELECT utt_pkg.curate_building();
  SELECT utt_pkg.curate_address();
COMMIT;

-- Set relations between geometric objects
BEGIN;
  SELECT utt_pkg.curate_relation('building_block');
  SELECT utt_pkg.curate_relation('building_plot');
  SELECT utt_pkg.curate_relation('plot_block');
COMMIT;

-- Example data analysis on utt data
select 'number of residentials' as category, count(uuid), sum(st_area(geom)) as total_ground_area from utt.building where gfk < 2000
union
select 'number of non-residentials' as category, count(uuid), sum(st_area(geom)) as total_ground_area from utt.building where gfk >= 2000
union
select 'number of buildings in berlin' as category, count(uuid), sum(st_area(geom)) as total_ground_area from utt.building where bezeich = 'AX_Gebaeude';
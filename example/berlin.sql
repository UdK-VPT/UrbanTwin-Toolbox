-- Run as DBA on a fresh UTTDB after init. Each registration, layer import and
-- the complete curated dataset commit separately. Run without an outer transaction.
-- After a failed step, run ROLLBACK; and retry only that step; earlier commits remain.
-- Only layers used by the curation routines are stored.
-- With psql: psql -v ON_ERROR_STOP=1 -f example/berlin.sql


-- Register various sources from Geoportal Berlin (gdi.berlin.de)
BEGIN;
  SELECT * FROM mirror.register_wfs_source(
    'berlin_alkis', 'https://gdi.berlin.de/services/wfs/alkis'
  );
COMMIT;

BEGIN;
  SELECT * FROM mirror.register_wfs_source(
    'berlin_alkis_gebaeude', 'https://gdi.berlin.de/services/wfs/alkis_gebaeude'
  );
COMMIT;

BEGIN;
  SELECT * FROM mirror.register_wfs_source(
    'berlin_bloecke', 'https://gdi.berlin.de/services/wfs/bloecke'
  );
COMMIT;

BEGIN;
  SELECT * FROM mirror.register_wfs_source(
    'berlin_adressen', 'https://gdi.berlin.de/services/wfs/adressen_rbs'
  );
COMMIT;

BEGIN;
  SELECT * FROM mirror.register_wfs_source(
    'berlin_baumbestand', 'https://gdi.berlin.de/services/wfs/baumbestand'
  );
COMMIT;

-- Example of a file registration, file must be loaded into folder ./uttdb/source-files first
-- BEGIN;
--   -- Keep this file in source-files before running the setup.
--   SELECT * FROM mirror.register_file_source(
--     'geo_waerme', '/source-files/q_total_RM_Paper.tif'
--   );
-- COMMIT;

-- Declare stable source keys explicitly. Each accepted import is a full source
-- snapshot; missing keys close their current mirror versions after threshold review.
UPDATE mirror.registry SET stable_key = ARRAY[CASE layer_name
  WHEN 'alkis:land' THEN 'lan'
  WHEN 'alkis:bezirk' THEN 'name'
  WHEN 'alkis:flurstuecke' THEN 'fsko'
  WHEN 'alkis_gebaeude:gebaeude' THEN 'uuid'
  WHEN 'bloecke:rbs_bloecke' THEN 'blknr'
  WHEN 'adressen_rbs:adressen_rbs' THEN 'adr_ident' END]
WHERE (source_name,layer_name) IN (
  ('berlin_alkis','alkis:land'),('berlin_alkis','alkis:bezirk'),
  ('berlin_alkis','alkis:flurstuecke'),('berlin_alkis_gebaeude','alkis_gebaeude:gebaeude'),
  ('berlin_bloecke','bloecke:rbs_bloecke'),('berlin_adressen','adressen_rbs:adressen_rbs')
);

-- Store selected sources as accepted version history, with read-only current views.
BEGIN;
  SELECT mirror.store_layer('berlin_alkis', 'alkis:land');
COMMIT;

BEGIN;
  SELECT mirror.store_layer('berlin_alkis', 'alkis:bezirk');
COMMIT;

BEGIN;
  SELECT mirror.store_layer('berlin_alkis', 'alkis:flurstuecke');
COMMIT;

BEGIN;
  SELECT mirror.store_layer('berlin_alkis_gebaeude', 'alkis_gebaeude:gebaeude');
COMMIT;

BEGIN;
  SELECT mirror.store_layer('berlin_bloecke', 'bloecke:rbs_bloecke');
COMMIT;

BEGIN;
  SELECT mirror.store_layer('berlin_adressen', 'adressen_rbs:adressen_rbs');
COMMIT;

-- Pin one snapshot after all six required source acceptances; pass it through the
-- complete recipe. Failed builds preserve the previous complete curated dataset.
-- This explicit override is necessary for fresh imports newer than the recipe default.
BEGIN;
DO $$
DECLARE selected_snapshot timestamptz := clock_timestamp();
BEGIN
  CALL curation.curate_berlin_20261101(snapshot_at=>selected_snapshot);
END;
$$;
COMMIT;

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

-- Example of a file registration, file must be loaded into folder ./uttdb/source-files first
-- BEGIN;
--   -- Keep this file in source-files before running the setup.
--   SELECT * FROM utt_pkg.mirror_register_file_source(
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
  SELECT utt_pkg.mirror_store_layer('berlin_alkis', 'alkis:land');
  SELECT utt_pkg.mirror_store_layer('berlin_alkis', 'alkis:bezirk');
  SELECT utt_pkg.mirror_store_layer('berlin_alkis', 'alkis:flurstuecke');
  SELECT utt_pkg.mirror_store_layer('berlin_alkis_gebaeude', 'alkis_gebaeude:gebaeude');
  SELECT utt_pkg.mirror_store_layer('berlin_bloecke', 'bloecke:rbs_bloecke');
  SELECT utt_pkg.mirror_store_layer('berlin_adressen', 'adressen_rbs:adressen_rbs');
COMMIT;

-- Mapping revisions are explicit configuration, installed after accepted source history.
-- Keep published source keys separate from official domain identity transformations.
BEGIN;
  INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,
      source_columns,source_id_column,rule_name,priority)
  SELECT row_id,'city',ARRAY['geom','name'],
      ARRAY['lan','namlan','geom'],'lan','berlin_city_v1',100
  FROM mirror.registry WHERE source_name='berlin_alkis' AND layer_name='alkis:land';
  INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,
      source_columns,source_id_column,rule_name,priority)
  SELECT row_id,'district',ARRAY['geom','name'],
      ARRAY['name','namgem','geom'],'name','berlin_district_v1',100
  FROM mirror.registry WHERE source_name='berlin_alkis' AND layer_name='alkis:bezirk';
  INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,
      source_columns,source_id_column,rule_name,priority)
  SELECT row_id,'block',ARRAY['centroid','geom','mostly_district_id_official','planning_area_no','source_date'],
      ARRAY['blknr','geom','plr','bez','datum'],'blknr','berlin_block_v1',100
  FROM mirror.registry WHERE source_name='berlin_bloecke' AND layer_name='bloecke:rbs_bloecke';
  INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,
      source_columns,source_id_column,rule_name,priority)
  SELECT row_id,'plot',ARRAY['cadastral_district_code','cadastral_field_number','district_id_official','geom','parcel_number_numerator','source_date'],
      ARRAY['fsko','geom','zae','gmk','fln','gdz','beg'],'fsko','berlin_plot_v1',100
  FROM mirror.registry WHERE source_name='berlin_alkis' AND layer_name='alkis:flurstuecke';
  INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,
      source_columns,source_id_column,rule_name,priority)
  SELECT row_id,'building',ARRAY['aaa_description','building_association_number','building_component_type','building_component_type_description','building_condition','building_condition_description','building_configuration','building_configuration_description','building_function','building_function_description','geom','highrise','house_number','name','position_relative_to_ground','position_relative_to_ground_description','pseudo_house_number','source_fid','storeys_above_ground','storeys_below_ground','street_code','street_name'],
      ARRAY['uuid','fid','geom','gfk','bezgfk','ofl','bezofl','aog','aug','hoh','bat','bezbat','nam','baw','bezbaw','zus','bezzus','lag','namlag','hnr','pnr','lnr','bezeich'],'uuid','berlin_building_v1',100
  FROM mirror.registry WHERE source_name='berlin_alkis_gebaeude' AND layer_name='alkis_gebaeude:gebaeude';
  INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,
      source_columns,source_id_column,rule_name,priority)
  SELECT row_id,'address',ARRAY['address_date','block_id_official','district_id_official','district_name','geom','house_number','house_number_suffix','pca_id','place_id','place_name','planning_area_name','planning_area_no','street_id','street_name','type'],
      ARRAY['adr_ident','geom','strnam','strnr','hausnr','hausnrz','postleit','blk','bez','bez_name','ot','ot_name','plr','plr_name','aufn_dt','str_typ'],'adr_ident','berlin_address_v1',100
  FROM mirror.registry WHERE source_name='berlin_adressen' AND layer_name='adressen_rbs:adressen_rbs';
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

-- Backfill spatial relations for every pair of versions with overlapping system time
BEGIN;
  SELECT utt_pkg.curate_relation('building_block');
  SELECT utt_pkg.curate_relation('building_plot');
  SELECT utt_pkg.curate_relation('plot_block');
COMMIT;

-- Example data analysis on utt data
select 'number of residentials' as category, count(building_id_official), sum(st_area(geom)) as total_ground_area from utt.building where upper_inf(utt_txn) AND building_function < 2000
union
select 'number of non-residentials' as category, count(building_id_official), sum(st_area(geom)) as total_ground_area from utt.building where upper_inf(utt_txn) AND building_function >= 2000
union
select 'number of buildings in berlin' as category, count(building_id_official), sum(st_area(geom)) as total_ground_area from utt.building where upper_inf(utt_txn) AND aaa_description = 'AX_Gebaeude';

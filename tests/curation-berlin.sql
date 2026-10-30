-- Six concrete Berlin SQL rule contracts, source-date state and historical backfill.
-- Run on a disposable initialized UTTDB: psql -X -v ON_ERROR_STOP=1 -f tests/curation-berlin.sql
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE uttdb_dba;
CREATE TABLE mirror.test_city_source("lan" text,"namlan" text,"geom" geometry);
INSERT INTO mirror.test_city_source VALUES('11','Berlin',public.ST_GeomFromText('POLYGON((0 0,0 10,10 10,10 0,0 0))',25832));
INSERT INTO mirror.registry(source_name,layer_name,source_type,source_url,table_base,stable_key) VALUES('berlin_alkis','alkis:land','file','/source-files/test','test_city',ARRAY['lan']);
SELECT utt_pkg.mirror_store_layer('berlin_alkis','alkis:land');
INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,source_columns,source_id_column,rule_name) SELECT row_id,'city',ARRAY['geom','name'],ARRAY['lan','namlan','geom'],'lan','berlin_city_v1' FROM mirror.registry WHERE source_name='berlin_alkis' AND layer_name='alkis:land';
SELECT utt_pkg.curate_city();
SELECT utt_pkg.curate_city();
DO $$BEGIN ASSERT (SELECT count(*)=1 FROM utt.city); END$$;
CREATE TABLE mirror.test_district_source("name" text,"namgem" text,"geom" geometry);
INSERT INTO mirror.test_district_source VALUES('11000001','District',public.ST_GeomFromText('POLYGON((0 0,0 10,10 10,10 0,0 0))',25832));
INSERT INTO mirror.registry(source_name,layer_name,source_type,source_url,table_base,stable_key) VALUES('berlin_alkis','alkis:bezirk','file','/source-files/test','test_district',ARRAY['name']);
SELECT utt_pkg.mirror_store_layer('berlin_alkis','alkis:bezirk');
INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,source_columns,source_id_column,rule_name) SELECT row_id,'district',ARRAY['geom','name'],ARRAY['name','namgem','geom'],'name','berlin_district_v1' FROM mirror.registry WHERE source_name='berlin_alkis' AND layer_name='alkis:bezirk';
SELECT utt_pkg.curate_district();
SELECT utt_pkg.curate_district();
DO $$BEGIN ASSERT (SELECT count(*)=1 FROM utt.district); END$$;
CREATE TABLE mirror.test_block_source("blknr" text,"geom" geometry,"plr" text,"bez" text,"datum" text);
INSERT INTO mirror.test_block_source VALUES('1',public.ST_GeomFromText('POLYGON((0 0,0 10,10 10,10 0,0 0))',25832),'42','1','2020-01-01');
INSERT INTO mirror.registry(source_name,layer_name,source_type,source_url,table_base,stable_key) VALUES('berlin_bloecke','bloecke:rbs_bloecke','file','/source-files/test','test_block',ARRAY['blknr']);
SELECT utt_pkg.mirror_store_layer('berlin_bloecke','bloecke:rbs_bloecke');
INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,source_columns,source_id_column,rule_name) SELECT row_id,'block',ARRAY['centroid','geom','mostly_district_id_official','planning_area_no','source_date'],ARRAY['blknr','geom','plr','bez','datum'],'blknr','berlin_block_v1' FROM mirror.registry WHERE source_name='berlin_bloecke' AND layer_name='bloecke:rbs_bloecke';
SELECT utt_pkg.curate_block();
SELECT utt_pkg.curate_block();
DO $$BEGIN ASSERT (SELECT count(*)=1 FROM utt.block); END$$;
CREATE TABLE mirror.test_plot_source("fsko" text,"geom" geometry,"zae" text,"gmk" text,"fln" text,"gdz" text,"beg" text);
INSERT INTO mirror.test_plot_source VALUES('000123___',public.ST_GeomFromText('POLYGON((0 0,0 10,10 10,10 0,0 0))',25832),'1','2','3','11000001','2020-01-01');
INSERT INTO mirror.registry(source_name,layer_name,source_type,source_url,table_base,stable_key) VALUES('berlin_alkis','alkis:flurstuecke','file','/source-files/test','test_plot',ARRAY['fsko']);
SELECT utt_pkg.mirror_store_layer('berlin_alkis','alkis:flurstuecke');
INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,source_columns,source_id_column,rule_name) SELECT row_id,'plot',ARRAY['cadastral_district_code','cadastral_field_number','district_id_official','geom','parcel_number_numerator','source_date'],ARRAY['fsko','geom','zae','gmk','fln','gdz','beg'],'fsko','berlin_plot_v1' FROM mirror.registry WHERE source_name='berlin_alkis' AND layer_name='alkis:flurstuecke';
SELECT utt_pkg.curate_plot();
SELECT utt_pkg.curate_plot();
DO $$BEGIN ASSERT (SELECT count(*)=1 FROM utt.plot); END$$;
CREATE TABLE mirror.test_building_source("uuid" text,"fid" text,"geom" geometry,"gfk" text,"bezgfk" text,"ofl" text,"bezofl" text,"aog" text,"aug" text,"hoh" text,"bat" text,"bezbat" text,"nam" text,"baw" text,"bezbaw" text,"zus" text,"bezzus" text,"lag" text,"namlag" text,"hnr" text,"pnr" text,"lnr" text,"bezeich" text);
INSERT INTO mirror.test_building_source VALUES('b1','1',public.ST_GeomFromText('POLYGON((0 0,0 10,10 10,10 0,0 0))',25832),'1000','Residential','0','Ground','3','0','','1','Main','Test','1','Attached','1','Completed','01','Street','1',NULL,'1','AX_Gebaeude');
INSERT INTO mirror.registry(source_name,layer_name,source_type,source_url,table_base,stable_key) VALUES('berlin_alkis_gebaeude','alkis_gebaeude:gebaeude','file','/source-files/test','test_building',ARRAY['uuid']);
SELECT utt_pkg.mirror_store_layer('berlin_alkis_gebaeude','alkis_gebaeude:gebaeude');
INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,source_columns,source_id_column,rule_name) SELECT row_id,'building',ARRAY['aaa_description','building_association_number','building_component_type','building_component_type_description','building_condition','building_condition_description','building_configuration','building_configuration_description','building_function','building_function_description','geom','highrise','house_number','name','position_relative_to_ground','position_relative_to_ground_description','pseudo_house_number','source_fid','storeys_above_ground','storeys_below_ground','street_code','street_name'],ARRAY['uuid','fid','geom','gfk','bezgfk','ofl','bezofl','aog','aug','hoh','bat','bezbat','nam','baw','bezbaw','zus','bezzus','lag','namlag','hnr','pnr','lnr','bezeich'],'uuid','berlin_building_v1' FROM mirror.registry WHERE source_name='berlin_alkis_gebaeude' AND layer_name='alkis_gebaeude:gebaeude';
SELECT utt_pkg.curate_building();
SELECT utt_pkg.curate_building();
DO $$BEGIN ASSERT (SELECT count(*)=1 FROM utt.building); END$$;
CREATE TABLE mirror.test_address_source("adr_ident" text,"geom" geometry,"strnam" text,"strnr" text,"hausnr" text,"hausnrz" text,"postleit" text,"blk" text,"bez" text,"bez_name" text,"ot" text,"ot_name" text,"plr" text,"plr_name" text,"aufn_dt" text,"str_typ" text);
INSERT INTO mirror.test_address_source VALUES('100',public.ST_GeomFromText('POINT(5 5)',25832),'Street','01','1',NULL,'10115','1','1','District','01','Town','42','Area','2020-01-01','street');
INSERT INTO mirror.registry(source_name,layer_name,source_type,source_url,table_base,stable_key) VALUES('berlin_adressen','adressen_rbs:adressen_rbs','file','/source-files/test','test_address',ARRAY['adr_ident']);
SELECT utt_pkg.mirror_store_layer('berlin_adressen','adressen_rbs:adressen_rbs');
INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,source_columns,source_id_column,rule_name) SELECT row_id,'address',ARRAY['address_date','block_id_official','district_id_official','district_name','geom','house_number','house_number_suffix','pca_id','place_id','place_name','planning_area_name','planning_area_no','street_id','street_name','type'],ARRAY['adr_ident','geom','strnam','strnr','hausnr','hausnrz','postleit','blk','bez','bez_name','ot','ot_name','plr','plr_name','aufn_dt','str_typ'],'adr_ident','berlin_address_v1' FROM mirror.registry WHERE source_name='berlin_adressen' AND layer_name='adressen_rbs:adressen_rbs';
SELECT utt_pkg.curate_address();
SELECT utt_pkg.curate_address();
DO $$BEGIN ASSERT (SELECT count(*)=1 FROM utt.address); END$$;
DO $$BEGIN
 ASSERT (SELECT source_fid=1 AND highrise IS NULL FROM utt.building_current);
 ASSERT (SELECT plot_id_official=123 FROM utt.plot_current);
 ASSERT (SELECT source_date=TIMESTAMP '2020-01-01' FROM utt.block_current);
 ASSERT (SELECT address_date=TIMESTAMP '2020-01-01' FROM utt.address_current);
 ASSERT (SELECT count(*)=6 FROM utt.curation_provenance);
 ASSERT (SELECT count(DISTINCT target_table)=6 FROM utt.curation_provenance);
 -- Each table starts row_id at 1: readers must distinguish table and row together.
 ASSERT (SELECT count(*)=1 AND bool_and(target_table='utt.city'::regclass)
   FROM utt_pkg.provenance_at('city',clock_timestamp()));
 ASSERT (SELECT count(*)=1 AND bool_and(target_table='utt.building'::regclass)
   FROM utt_pkg.provenance_at('building',clock_timestamp()));
 ASSERT NOT EXISTS(SELECT FROM mirror.registry WHERE source_revision_at IS NOT NULL);
END$$;
UPDATE mirror.test_block_source SET datum='2000-01-01';
SELECT utt_pkg.mirror_store_layer('berlin_bloecke','bloecke:rbs_bloecke');
SELECT utt_pkg.curate_block();
DO $$BEGIN ASSERT (SELECT count(*)=2 FROM utt.block); END$$;
UPDATE mirror.test_plot_source SET beg='2000-01-01';
SELECT utt_pkg.mirror_store_layer('berlin_alkis','alkis:flurstuecke');
SELECT utt_pkg.curate_plot();
DO $$BEGIN ASSERT (SELECT count(*)=2 FROM utt.plot); END$$;
UPDATE mirror.test_address_source SET aufn_dt='2000-01-01';
SELECT utt_pkg.mirror_store_layer('berlin_adressen','adressen_rbs:adressen_rbs');
SELECT utt_pkg.curate_address();
DO $$BEGIN ASSERT (SELECT count(*)=2 FROM utt.address); END$$;
-- No relation run occurred while the first block/plot versions were current.
SELECT utt_pkg.curate_relation('building_block');
SELECT utt_pkg.curate_relation('building_plot');
SELECT utt_pkg.curate_relation('plot_block');
DO $$BEGIN
 ASSERT (SELECT count(*)=2 FROM utt.relation_bldg_block);
 ASSERT (SELECT count(*)=2 FROM utt.relation_bldg_plot);
 ASSERT (SELECT count(*)=3 FROM utt.relation_plot_block);
 ASSERT (SELECT count(*)=1 FROM utt_pkg.relation_at('building_block',clock_timestamp()));
 ASSERT (SELECT count(*)=1 FROM utt.relation_bldg_block_current);
 ASSERT (SELECT count(*)=1 FROM utt_pkg.block_at(clock_timestamp()));
 ASSERT (SELECT count(*)=1 FROM utt_pkg.provenance_at('block',clock_timestamp()));
 ASSERT NOT has_table_privilege('uttdb_pipeline','utt.building','INSERT');
 ASSERT NOT has_table_privilege('uttdb_pipeline','utt.curation_provenance','INSERT');
END$$;
SELECT utt_pkg.curate_relation('building_block');
DO $$BEGIN ASSERT (SELECT count(*)=2 FROM utt.relation_bldg_block); END$$;
-- Removing a descriptive source column cannot silently clear a nullable Berlin value.
ALTER TABLE mirror.test_building_source DROP COLUMN nam;
SELECT utt_pkg.mirror_store_layer('berlin_alkis_gebaeude','alkis_gebaeude:gebaeude');
SELECT utt_pkg.curate_building();
DO $$BEGIN ASSERT (SELECT count(*)=1 FROM utt.building); ASSERT (SELECT name='Test' FROM utt.building_current); END$$;
UPDATE utt.curation_mapping SET active=false WHERE target_entity='building';
ROLLBACK;

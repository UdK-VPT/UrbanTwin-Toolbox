-- Rollback-only group selection, provenance, integrity and privilege checks.
-- Run on a disposable initialized UTTDB: psql -X -v ON_ERROR_STOP=1 -f tests/curation.sql
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE uttdb_dba;
CREATE TABLE mirror.core_source(id text,label text,geom geometry,note text);
INSERT INTO mirror.core_source VALUES('b1','Building',ST_GeomFromText('POLYGON((0 0,0 10,10 10,10 0,0 0))',25832),'v1');
CREATE TABLE mirror.preferred_source(id text,height numeric);
INSERT INTO mirror.preferred_source VALUES('b1',5);
CREATE TABLE mirror.fallback_source(id text,height numeric);
INSERT INTO mirror.fallback_source VALUES('b1',7);
INSERT INTO mirror.registry(source_name,layer_name,source_type,source_url,table_base,stable_key) VALUES
('core','objects','file','/source-files/test','core',ARRAY['id']),
('preferred','objects','file','/source-files/test','preferred',ARRAY['id']),
('fallback','objects','file','/source-files/test','fallback',ARRAY['id']);
SELECT utt_pkg.mirror_store_layer('core','objects');
SELECT utt_pkg.mirror_store_layer('preferred','objects');
SELECT utt_pkg.mirror_store_layer('fallback','objects');
-- Reversed array order is normalized while preserving direct source/target pairing.
INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,source_columns,source_id_column,rule_name,priority)
SELECT row_id,'building',ARRAY['name','geom'],ARRAY['label','geom'],'id','direct_building_v1',1
FROM mirror.registry WHERE source_name='core';
INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,source_columns,source_id_column,rule_name,priority)
SELECT row_id,'building',ARRAY['building_height'],ARRAY['height'],'id','direct_building_v1',10
FROM mirror.registry WHERE source_name='preferred';
INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,source_columns,source_id_column,rule_name,priority)
SELECT row_id,'building',ARRAY['building_height'],ARRAY['height'],'id','direct_building_v1',20
FROM mirror.registry WHERE source_name='fallback';
SELECT utt_pkg.curate_building();
DO $$BEGIN
 ASSERT (SELECT count(*)=1 FROM utt.building);
 ASSERT (SELECT building_height=5 AND name='Building' FROM utt.building_current);
 ASSERT (SELECT count(*)=2 FROM utt.curation_provenance);
 ASSERT (SELECT target_columns=ARRAY['geom','name'] AND source_columns=ARRAY['geom','label']
   FROM utt.curation_mapping m JOIN mirror.registry r ON m.registry_row_id=r.row_id WHERE r.source_name='core');
END$$;
-- A new accepted import with unchanged source versions is not a new origin.
SELECT utt_pkg.mirror_store_layer('preferred','objects');
SELECT utt_pkg.curate_building();
DO $$BEGIN ASSERT (SELECT count(*)=1 FROM utt.building); ASSERT (SELECT count(*)=2 FROM utt.curation_provenance); END$$;
-- Losing candidates do not version targets or add observations.
UPDATE mirror.fallback_source SET height=8;
SELECT utt_pkg.mirror_store_layer('fallback','objects');
SELECT utt_pkg.curate_building();
DO $$BEGIN ASSERT (SELECT count(*)=1 FROM utt.building); ASSERT (SELECT count(*)=2 FROM utt.curation_provenance); END$$;
-- Missing preferred values make the entire height group ineligible.
UPDATE mirror.preferred_source SET height=NULL;
SELECT utt_pkg.mirror_store_layer('preferred','objects',true);
SELECT utt_pkg.mirror_accept_layer('preferred','objects');
SELECT utt_pkg.curate_building();
DO $$BEGIN
 ASSERT (SELECT count(*)=2 FROM utt.building);
 ASSERT (SELECT building_height=8 FROM utt.building_current);
 ASSERT EXISTS(SELECT FROM utt_pkg.provenance_at('building',clock_timestamp()) WHERE selection_reason='fallback');
END$$;
-- No core replacement: retain its state AND exact origin on the new version.
UPDATE utt.curation_mapping SET active=false WHERE registry_row_id=(SELECT row_id FROM mirror.registry WHERE source_name='core');
UPDATE mirror.fallback_source SET height=9;
SELECT utt_pkg.mirror_store_layer('fallback','objects');
SELECT utt_pkg.curate_building();
DO $$BEGIN
 ASSERT (SELECT count(*)=3 FROM utt.building);
 ASSERT (SELECT name='Building' AND building_height=9 FROM utt.building_current);
 ASSERT EXISTS(SELECT FROM utt_pkg.provenance_at('building',clock_timestamp()) WHERE selection_reason='carried');
END$$;
-- Rebalancing half an old atomic group must fail, preserving state and observations.
INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,source_columns,source_id_column,rule_name)
SELECT row_id,'building',ARRAY['geom'],ARRAY['geom'],'id','direct_building_v1' FROM mirror.registry WHERE source_name='core';
DO $$BEGIN
 BEGIN PERFORM utt_pkg.curate_building(); RAISE EXCEPTION 'partial rebalance allowed';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM='partial rebalance allowed' THEN RAISE; END IF; END;
END$$;
INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,source_columns,source_id_column,rule_name)
SELECT row_id,'building',ARRAY['name'],ARRAY['label'],'id','direct_building_v1' FROM mirror.registry WHERE source_name='core';
SELECT utt_pkg.curate_building();
DO $$BEGIN
 ASSERT (SELECT count(*)=3 FROM utt.building);
 ASSERT (SELECT count(*)=3 FROM utt_pkg.provenance_at('building',clock_timestamp()));
 ASSERT (SELECT count(*)=2 FROM utt_pkg.provenance_at('building',
   (SELECT lower(utt_txn) FROM utt.building_current)));
END$$;
-- A source-only revision adds origins without changing the domain version.
UPDATE mirror.core_source SET note='v2';
SELECT utt_pkg.mirror_store_layer('core','objects');
SELECT utt_pkg.curate_building();
DO $$BEGIN ASSERT (SELECT count(*)=3 FROM utt.building); END$$;
-- Aggregation retains both contributors, rather than inventing one source record.
CREATE TABLE mirror.parts_source(part text,id text,height numeric);
INSERT INTO mirror.parts_source VALUES('a','b1',2),('b','b1',3);
INSERT INTO mirror.registry(source_name,layer_name,source_type,source_url,table_base,stable_key)
VALUES('parts','objects','file','/source-files/test','parts',ARRAY['part']);
SELECT utt_pkg.mirror_store_layer('parts','objects');
INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,source_columns,source_id_column,rule_name,priority)
SELECT row_id,'building',ARRAY['building_height'],ARRAY['height'],'id','sum_building_v1',1
FROM mirror.registry WHERE source_name='parts';
SELECT utt_pkg.curate_building();
DO $$BEGIN
 ASSERT (SELECT count(*)=4 FROM utt.building);
 ASSERT (SELECT building_height=5 FROM utt.building_current);
 ASSERT (SELECT count(*)=2 FROM utt_pkg.provenance_at('building',clock_timestamp()) p
   JOIN utt.curation_mapping m USING(mapping_id) WHERE rule_name='sum_building_v1');
END$$;
-- All height candidates withdrawn/ineligible: preserve existing height and origins.
UPDATE utt.curation_mapping SET active=false WHERE target_columns=ARRAY['building_height'];
SELECT utt_pkg.curate_building();
DO $$BEGIN ASSERT (SELECT count(*)=4 FROM utt.building); ASSERT (SELECT building_height=5 FROM utt.building_current); END$$;
-- Referential and immutability checks are real database boundaries.
DO $$DECLARE p utt.curation_provenance%ROWTYPE; BEGIN
 SELECT * INTO p FROM utt.curation_provenance LIMIT 1;
 BEGIN UPDATE utt.curation_mapping SET priority=999 WHERE mapping_id=p.mapping_id; RAISE EXCEPTION 'mapping rewrite allowed';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM='mapping rewrite allowed' THEN RAISE; END IF; END;
 BEGIN DELETE FROM utt.curation_provenance; RAISE EXCEPTION 'provenance delete allowed';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM='provenance delete allowed' THEN RAISE; END IF; END;
 BEGIN UPDATE utt.building SET name='rewrite'; RAISE EXCEPTION 'history rewrite allowed';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM='history rewrite allowed' THEN RAISE; END IF; END;
 BEGIN
   INSERT INTO utt.curation_provenance(source_registry_row_id,mapping_id,target_table,target_row_id,source_row_id,source_key,import_id,observed_at,selection_reason)
   VALUES(p.source_registry_row_id,p.mapping_id,p.target_table,p.target_row_id,999999,p.source_key,p.import_id,p.observed_at,'preferred');
   RAISE EXCEPTION 'missing source accepted';
 EXCEPTION WHEN no_data_found OR foreign_key_violation THEN NULL; END;
 -- Generic target references must reject a wrong table and a missing target row.
 ASSERT p.target_table='utt.building'::regclass;
 BEGIN
   INSERT INTO utt.curation_provenance(source_registry_row_id,mapping_id,target_table,target_row_id,source_row_id,source_key,import_id,observed_at,selection_reason)
   VALUES(p.source_registry_row_id,p.mapping_id,'utt.city'::regclass,p.target_row_id,p.source_row_id,p.source_key,p.import_id,p.observed_at,'preferred');
   RAISE EXCEPTION 'wrong target table accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'Mapping and target table disagree.' THEN RAISE; END IF; END;
 BEGIN
   INSERT INTO utt.curation_provenance(source_registry_row_id,mapping_id,target_table,target_row_id,source_row_id,source_key,import_id,observed_at,selection_reason)
   VALUES(p.source_registry_row_id,p.mapping_id,p.target_table,999999,p.source_row_id,p.source_key,p.import_id,p.observed_at,'preferred');
   RAISE EXCEPTION 'missing target accepted';
 EXCEPTION WHEN no_data_found THEN NULL; END;
 ASSERT NOT has_table_privilege('uttdb_pipeline','utt.building','UPDATE');
 ASSERT NOT has_table_privilege('uttdb_pipeline','utt.curation_mapping','INSERT');
END$$;
-- Pipeline can execute curation but cannot edit its state directly.
RESET ROLE;
SET LOCAL ROLE uttdb_pipeline;
SELECT utt_pkg.curate_building();
RESET ROLE;
SET LOCAL ROLE uttdb_dba;
-- Source disappearance closes mirror history but retains curated state and origins.
DO $$DECLARE version_count bigint; origin_count bigint; BEGIN
 SELECT count(*) INTO version_count FROM utt.building;
 SELECT count(*) INTO origin_count FROM utt.curation_provenance;
 DELETE FROM mirror.core_source;
 PERFORM utt_pkg.mirror_store_layer('core','objects',review=>true);
 PERFORM utt_pkg.mirror_accept_layer('core','objects');
 ASSERT NOT EXISTS(SELECT FROM mirror.core);
 PERFORM utt_pkg.curate_building();
 ASSERT (SELECT count(*)=version_count FROM utt.building);
 ASSERT (SELECT count(*)=origin_count FROM utt.curation_provenance);
END$$;
ROLLBACK;

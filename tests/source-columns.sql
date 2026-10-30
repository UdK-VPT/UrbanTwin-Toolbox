-- Rollback-only structure reuse and mapping-schema checks on a disposable database.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE uttdb_dba;
CREATE TABLE mirror.structure_check_source(id text, label text);
INSERT INTO mirror.structure_check_source VALUES('11','Berlin');
COMMENT ON COLUMN mirror.structure_check_source.label IS 'Original label';
INSERT INTO mirror.registry(source_name,layer_name,source_type,source_url,table_base,stable_key)
VALUES('structure_check','cities','file','/source-files/check','structure_check',ARRAY['id']);
SELECT utt_pkg.mirror_store_layer('structure_check','cities');
SELECT utt_pkg.mirror_store_layer('structure_check','cities');
DO $$BEGIN
 ASSERT (SELECT count(*)=2 FROM mirror.source_columns);
 ASSERT (SELECT count(DISTINCT structure_version)=1 FROM mirror.import);
 ASSERT (SELECT count(*)=1 FROM mirror.structure_check_stored);
END$$;
-- A comment is part of the definition; restore it and reuse the original set.
COMMENT ON COLUMN mirror.structure_check_source.label IS 'Revised label';
SELECT utt_pkg.mirror_store_layer('structure_check','cities');
COMMENT ON COLUMN mirror.structure_check_source.label IS 'Original label';
SELECT utt_pkg.mirror_store_layer('structure_check','cities');
DO $$BEGIN
 ASSERT (SELECT count(*)=4 FROM mirror.source_columns);
 ASSERT (SELECT structure_version=1 FROM mirror.import ORDER BY import_id DESC LIMIT 1);
 ASSERT (SELECT count(*)=3 FROM mirror.structure_check_stored);
END$$;
INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,source_columns,source_id_column,rule_name)
SELECT row_id,'city',ARRAY['name'],ARRAY['label'],'id','direct_city_v1' FROM mirror.registry;
SELECT utt_pkg.curate_city();
-- Removing a column changes supplied structure; re-adding it can reuse an older set.
ALTER TABLE mirror.structure_check_source ADD COLUMN note text;
SELECT utt_pkg.mirror_store_layer('structure_check','cities');
ALTER TABLE mirror.structure_check_source DROP COLUMN note;
SELECT utt_pkg.mirror_store_layer('structure_check','cities');
DO $$BEGIN
 ASSERT (SELECT count(*)=7 FROM mirror.source_columns);
 ASSERT (SELECT structure_version=1 FROM mirror.import ORDER BY import_id DESC LIMIT 1);
END$$;
SELECT utt_pkg.curate_city();
DO $$BEGIN
 ASSERT (SELECT count(*)=1 FROM utt.city);
 ASSERT EXISTS(SELECT FROM utt.provenance_structure_check_cities);
 ASSERT has_function_privilege('uttdb_reader','utt_pkg.city_at(timestamptz)','EXECUTE');
 ASSERT has_function_privilege('uttdb_reader','utt_pkg.provenance_at(text,timestamptz)','EXECUTE');
 ASSERT NOT has_function_privilege('uttdb_reader','utt_pkg.curation_rule_query(bigint)','EXECUTE');
 ASSERT NOT has_function_privilege('uttdb_app_reader','utt_pkg.curation_validate_mapping()','EXECUTE');
END$$;
-- Readers must actually be callable under the reader role, not only by the DBA.
SET LOCAL ROLE uttdb_reader;
SELECT * FROM utt_pkg.city_at(clock_timestamp());
SELECT * FROM utt_pkg.provenance_at('city',clock_timestamp());
ROLLBACK;

-- Optional native-file metadata contributions; the payload is never parsed.
-- Create fixtures: python tests/create-mirror-fixtures.py
-- Then run against a disposable initialized UTTDB with ON_ERROR_STOP=1.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE uttdb_dba;
SELECT utt_pkg.mirror_register_external_file('native_city','11','/source-files/.utt-ver03-check/v1.nc','NetCDF');
-- Registration alone is not an accepted curation input.
DO $$BEGIN
 BEGIN
  INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,source_columns,source_id_column,rule_name)
  SELECT row_id,'city',ARRAY['name'],ARRAY['source_url'],'layer_name','direct_city_v1'
  FROM mirror.registry WHERE source_name='native_city';
  RAISE EXCEPTION 'unaccepted native source mapped';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM='unaccepted native source mapped' THEN RAISE; END IF;
 END;
 ASSERT NOT EXISTS(SELECT FROM utt.curation_mapping);
END$$;
SELECT utt_pkg.mirror_store_layer('native_city','11');
-- Deliberately map a reference attribute to exercise the file provenance contract.
-- This is a test, not a geographical interpretation of the native payload.
INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,source_columns,source_id_column,rule_name)
SELECT row_id,'city',ARRAY['name'],ARRAY['source_url'],'layer_name','direct_city_v1'
FROM mirror.registry WHERE source_name='native_city';
SELECT utt_pkg.curate_city();
DO $$BEGIN
 ASSERT (SELECT count(*)=1 FROM utt.city);
 ASSERT EXISTS(SELECT FROM utt.curation_provenance WHERE source_file_row_id IS NOT NULL AND source_row_id IS NULL);
END$$;
SELECT utt_pkg.mirror_store_layer('native_city','11',file_path=>'/source-files/.utt-ver03-check/v2.nc');
SELECT utt_pkg.curate_city();
DO $$BEGIN
 ASSERT (SELECT count(*)=2 FROM utt.city);
 ASSERT (SELECT count(*)=2 FROM mirror.registry WHERE source_name='native_city');
 ASSERT (SELECT count(*)=1 FROM utt_pkg.provenance_at('city',clock_timestamp()));
END$$;
-- Format metadata changes create a file version, but identical mapped output only changes provenance.
SELECT utt_pkg.mirror_store_layer('native_city','11',file_format=>'NetCDF revised');
SELECT utt_pkg.curate_city();
DO $$BEGIN
 ASSERT (SELECT count(*)=2 FROM utt.city);
 ASSERT (SELECT count(*)=3 FROM utt.curation_provenance);
END$$;
-- A mapping revision may anchor to a later accepted native reference without
-- creating a second, numerically named partition or losing existing provenance.
UPDATE utt.curation_mapping SET active=false;
INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,source_columns,source_id_column,rule_name)
SELECT row_id,'city',ARRAY['name'],ARRAY['source_url'],'layer_name','direct_city_v1'
FROM mirror.registry WHERE source_name='native_city' AND upper_inf(utt_txn);
SELECT utt_pkg.curate_city();
DO $$BEGIN
 ASSERT (SELECT count(*)=4 FROM utt.provenance_native_city_11);
 ASSERT (SELECT count(*)=1 FROM pg_inherits WHERE inhparent='utt.curation_provenance'::regclass);
 ASSERT (SELECT count(*)=2 FROM utt.city);
END$$;
ROLLBACK;

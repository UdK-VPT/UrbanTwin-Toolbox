-- Rollback-only native-file and OGR checks on a disposable initialized UTTDB.
-- Before running: python tests/create-mirror-fixtures.py
-- Then: psql -X -v ON_ERROR_STOP=1 -f tests/mirror-files.sql
-- Remove only the generated .utt-ver03-check fixtures afterwards.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE uttdb_dba;
SELECT utt_pkg.mirror_register_external_file('native_check','temperature','/source-files/.utt-ver03-check/v1.nc','NetCDF');
UPDATE mirror.registry SET source_owner='Published owner' WHERE source_name='native_check' AND utt_txn IS NULL;
SELECT utt_pkg.mirror_store_layer('native_check','temperature');
SELECT utt_pkg.mirror_store_layer('native_check','temperature');
DO $$BEGIN
 ASSERT (SELECT count(*)=1 FROM mirror.registry WHERE source_name='native_check');
 ASSERT (SELECT count(*)=2 FROM mirror.import i JOIN mirror.registry r ON r.row_id=i.registry_row_id WHERE r.source_name='native_check' AND i.status='accepted');
END$$;
SELECT utt_pkg.mirror_store_layer('native_check','temperature',true,'/source-files/.utt-ver03-check/v2.nc');
SELECT utt_pkg.mirror_accept_layer('native_check','temperature');
DO $$BEGIN
 ASSERT (SELECT count(*)=2 FROM mirror.registry WHERE source_name='native_check');
 ASSERT (SELECT count(*)=1 FROM mirror.registry WHERE source_name='native_check' AND upper_inf(utt_txn));
 ASSERT (SELECT count(*)=1 FROM mirror.registry WHERE source_name='native_check' AND NOT upper_inf(utt_txn));
 ASSERT (SELECT count(DISTINCT file_checksum)=2 FROM mirror.registry WHERE source_name='native_check');
 ASSERT NOT EXISTS(SELECT FROM mirror.registry WHERE source_name='native_check' AND source_owner IS DISTINCT FROM 'Published owner');
 ASSERT EXISTS(SELECT FROM mirror.import WHERE status='accepted' AND source_location='/source-files/.utt-ver03-check/v2.nc');
END$$;
SELECT utt_pkg.mirror_store_layer('native_check','temperature',file_path=>'/source-files/.utt-ver03-check/missing.nc');
DO $$BEGIN ASSERT EXISTS(SELECT FROM mirror.import WHERE status='failed'); END$$;
-- Corrupting a staged checksum cannot publish different evidence.
SELECT utt_pkg.mirror_store_layer('native_check','temperature',true);
DO $$DECLARE staging text; BEGIN
 SELECT staging_table INTO STRICT staging FROM mirror.import WHERE status='staged';
 EXECUTE format('UPDATE mirror.%I SET file_checksum=''incorrect''',staging);
 BEGIN PERFORM utt_pkg.mirror_accept_layer('native_check','temperature'); RAISE EXCEPTION 'mismatched file accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM='mismatched file accepted' THEN RAISE; END IF; END;
END$$;
SELECT utt_pkg.mirror_reject_layer('native_check','temperature');
SELECT * FROM utt_pkg.mirror_register_file_source('vector_check','/source-files/.utt-ver03-check/sample.geojson');
UPDATE mirror.registry SET stable_key=ARRAY['id'] WHERE source_name='vector_check';
SELECT utt_pkg.mirror_store_layer('vector_check','sample');
DO $$BEGIN
 ASSERT EXISTS(SELECT FROM mirror.import i JOIN mirror.registry r ON i.registry_row_id=r.row_id WHERE r.source_name='vector_check' AND i.status='accepted');
END$$;
-- Readable generated names and normalization collisions must be explicit.
DO $$BEGIN
 ASSERT (SELECT table_base='vector_check_sample' FROM mirror.registry WHERE source_name='vector_check');
 ASSERT to_regclass('mirror.native_check_temperature_staging') IS NULL;
 BEGIN
  PERFORM utt_pkg.mirror_register_file_source('vector-check','/source-files/.utt-ver03-check/sample.geojson');
  RAISE EXCEPTION 'normalization collision accepted';
 EXCEPTION WHEN duplicate_table OR unique_violation THEN NULL;
 END;
 ASSERT NOT EXISTS(SELECT FROM pg_foreign_server WHERE srvname='vector-check');
 BEGIN PERFORM utt_pkg.mirror_object_base(repeat('long',20));
  RAISE EXCEPTION 'long name accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM='long name accepted' THEN RAISE; END IF;
 END;
END$$;
ROLLBACK;

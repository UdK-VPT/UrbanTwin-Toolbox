-- Rollback-only checks on a freshly initialized disposable UTTDB.
-- Run from the repository root: psql -X -v ON_ERROR_STOP=1 -f tests/mirror.sql
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE uttdb_dba;
CREATE TABLE mirror.check_source(id integer, value text, geom geometry);
INSERT INTO mirror.check_source VALUES (1,'one',ST_SetSRID(ST_MakePoint(1,2),4326)),(2,'two',NULL);
INSERT INTO mirror.registry(source_name,layer_name,source_type,source_url,table_base,stable_key)
VALUES('check','features','file','/source-files/check','check',ARRAY['id']);
SELECT utt_pkg.mirror_store_layer('check','features');
DO $$BEGIN
 ASSERT (SELECT count(*)=2 FROM mirror.check_stored);
 ASSERT (SELECT count(*)=1 FROM mirror.import WHERE status='accepted');
 ASSERT (SELECT count(*)=2 FROM mirror.check);
END$$;
SELECT utt_pkg.mirror_store_layer('check','features');
DO $$BEGIN ASSERT (SELECT count(*)=2 FROM mirror.check_stored); END$$;
UPDATE mirror.check_source SET value='changed' WHERE id=1;
SELECT utt_pkg.mirror_store_layer('check','features');
DO $$BEGIN
 ASSERT (SELECT count(*)=3 FROM mirror.check_stored);
 ASSERT (SELECT count(*)=1 FROM mirror.check_stored WHERE NOT upper_inf(utt_txn));
END$$;
DELETE FROM mirror.check_source WHERE id=2;
SELECT utt_pkg.mirror_store_layer('check','features');
DO $$BEGIN ASSERT EXISTS(SELECT FROM mirror.import WHERE status='staged' AND cardinality(threshold_failures)>0); END$$;
-- Threshold failure alone does not change accepted membership.
DO $$BEGIN ASSERT (SELECT count(*)=2 FROM mirror.check); END$$;
SELECT utt_pkg.mirror_accept_layer('check','features');
DO $$BEGIN
 ASSERT (SELECT count(*)=1 FROM mirror.check);
 ASSERT EXISTS(SELECT FROM mirror.check_stored WHERE id=2 AND NOT upper_inf(utt_txn));
END$$;
ALTER TABLE mirror.check_source ADD COLUMN added text;
UPDATE mirror.check_source SET added='new';
SELECT utt_pkg.mirror_store_layer('check','features');
DO $$BEGIN ASSERT (SELECT added='new' FROM mirror.check); END$$;
ALTER TABLE mirror.check_source DROP COLUMN value;
SELECT utt_pkg.mirror_store_layer('check','features');
DO $$BEGIN ASSERT NOT EXISTS(SELECT FROM pg_attribute WHERE attrelid='mirror.check'::regclass AND attname='value' AND NOT attisdropped); END$$;
SELECT utt_pkg.mirror_store_layer('check','features',true);
SELECT utt_pkg.mirror_reject_layer('check','features');
DO $$BEGIN
 BEGIN DELETE FROM mirror.check_stored; RAISE EXCEPTION 'history deletion allowed'; EXCEPTION WHEN raise_exception THEN IF SQLERRM='history deletion allowed' THEN RAISE; END IF; END;
 BEGIN UPDATE mirror.import SET data_revision_at=now() WHERE status='accepted'; RAISE EXCEPTION 'accepted edit allowed'; EXCEPTION WHEN raise_exception THEN IF SQLERRM='accepted edit allowed' THEN RAISE; END IF; END;
 ASSERT NOT has_table_privilege('uttdb_pipeline','mirror.check_stored','UPDATE');
 ASSERT NOT has_table_privilege('uttdb_pipeline','mirror.check','INSERT');
END$$;
-- Invalid input stays staged and cannot bypass integrity checks manually.
INSERT INTO mirror.check_source(id,geom,added) VALUES(NULL,NULL,NULL);
SELECT utt_pkg.mirror_store_layer('check','features');
DO $$BEGIN
 ASSERT EXISTS(SELECT FROM mirror.import WHERE status='staged' AND cardinality(validation_errors)>0);
 BEGIN PERFORM utt_pkg.mirror_accept_layer('check','features'); RAISE EXCEPTION 'invalid keys accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM='invalid keys accepted' THEN RAISE; END IF; END;
END$$;
SELECT utt_pkg.mirror_reject_layer('check','features');
DELETE FROM mirror.check_source WHERE id IS NULL;
-- Incompatible schema changes are held and never rewrite history.
ALTER TABLE mirror.check_source ALTER COLUMN added TYPE integer USING 1;
SELECT utt_pkg.mirror_store_layer('check','features');
DO $$BEGIN ASSERT EXISTS(SELECT FROM mirror.import WHERE status='staged' AND cardinality(validation_errors)>0); END$$;
SELECT utt_pkg.mirror_reject_layer('check','features');
-- Registered scope and stable keys cannot be repurposed after acceptance.
DO $$BEGIN
 BEGIN UPDATE mirror.registry SET coverage='another whole scope' WHERE source_name='check';
   RAISE EXCEPTION 'registered scope changed';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM='registered scope changed' THEN RAISE; END IF; END;
END$$;
SELECT utt_pkg.mirror_unregister_source('check');
DO $$BEGIN ASSERT EXISTS(SELECT FROM mirror.registry WHERE source_name='check' AND retired); END$$;
-- Raster metadata changes require review; manual approval retains integrity checks.
CREATE TABLE mirror.raster_check_source(rid bigint, rast raster);
INSERT INTO mirror.raster_check_source SELECT 1, ST_AddBand(ST_MakeEmptyRaster(2,2,0,0,1,-1,0,0,4326),'8BUI'::text,1,0);
INSERT INTO mirror.registry(source_name,layer_name,source_type,source_url,table_base,stable_key)
VALUES('raster_check','tiles','file','/source-files/check.tif','raster_check',ARRAY['rid']);
SELECT utt_pkg.mirror_store_layer('raster_check','tiles');
SELECT utt_pkg.mirror_store_layer('raster_check','tiles');
DO $$BEGIN ASSERT (SELECT count(*)=1 FROM mirror.raster_check_stored); END$$;
UPDATE mirror.raster_check_source SET rast=ST_SetUpperLeft(rast,1,1);
SELECT utt_pkg.mirror_store_layer('raster_check','tiles');
DO $$BEGIN ASSERT EXISTS(SELECT FROM mirror.import WHERE status='staged' AND cardinality(threshold_failures)>0); END$$;
SELECT utt_pkg.mirror_accept_layer('raster_check','tiles');
DO $$BEGIN ASSERT (SELECT count(*)=2 FROM mirror.raster_check_stored); END$$;
-- Full snapshots replace membership even when counts are unchanged.
CREATE TABLE mirror.snapshot_check_source(id bigint,value text);
INSERT INTO mirror.snapshot_check_source VALUES(1,'one'),(2,'two');
INSERT INTO mirror.registry(source_name,layer_name,source_type,source_url,table_base,stable_key,coverage)
VALUES('snapshot_check','objects','file','/source-files/snapshot','snapshot_check',ARRAY['id'],'registered scope');
SELECT utt_pkg.mirror_store_layer('snapshot_check','objects');
DELETE FROM mirror.snapshot_check_source WHERE id=2;
INSERT INTO mirror.snapshot_check_source VALUES(3,'three');
SELECT utt_pkg.mirror_store_layer('snapshot_check','objects');
DO $$BEGIN
 ASSERT (SELECT count(*)=2 FROM mirror.snapshot_check);
 ASSERT NOT EXISTS(SELECT FROM mirror.snapshot_check WHERE id=2);
 ASSERT EXISTS(SELECT FROM mirror.snapshot_check_stored WHERE id=2 AND NOT upper_inf(utt_txn));
 ASSERT EXISTS(SELECT FROM mirror.import i JOIN mirror.registry r ON i.registry_row_id=r.row_id
   WHERE r.source_name='snapshot_check' AND i.coverage='registered scope' AND i.source_location='/source-files/snapshot');
END$$;
-- A count decrease inside the configured threshold is accepted automatically.
UPDATE mirror.registry SET change_threshold_percent=50 WHERE source_name='snapshot_check';
DELETE FROM mirror.snapshot_check_source WHERE id=3;
SELECT utt_pkg.mirror_store_layer('snapshot_check','objects');
DO $$BEGIN
 ASSERT (SELECT count(*)=1 FROM mirror.snapshot_check);
 ASSERT EXISTS(SELECT FROM mirror.snapshot_check_stored WHERE id=3 AND NOT upper_inf(utt_txn));
 ASSERT NOT EXISTS(SELECT FROM mirror.import WHERE status='staged');
END$$;
-- Empty updates are held by the count threshold; rejection preserves state.
DELETE FROM mirror.snapshot_check_source;
SELECT utt_pkg.mirror_store_layer('snapshot_check','objects');
DO $$BEGIN
 ASSERT (SELECT count(*)=1 FROM mirror.snapshot_check);
 ASSERT EXISTS(SELECT FROM mirror.import WHERE status='staged' AND cardinality(threshold_failures)>0);
END$$;
SELECT utt_pkg.mirror_reject_layer('snapshot_check','objects');
DO $$BEGIN ASSERT (SELECT count(*)=1 FROM mirror.snapshot_check); END$$;
-- Explicit acceptance of that empty snapshot closes every current source version.
SELECT utt_pkg.mirror_store_layer('snapshot_check','objects');
SELECT utt_pkg.mirror_accept_layer('snapshot_check','objects');
DO $$BEGIN
 ASSERT NOT EXISTS(SELECT FROM mirror.snapshot_check);
 ASSERT (SELECT count(*)=3 FROM mirror.snapshot_check_stored WHERE NOT upper_inf(utt_txn));
END$$;
-- A reappearing stable key creates a new version, not a rewrite of withdrawn history.
INSERT INTO mirror.snapshot_check_source VALUES(1,'returned');
SELECT utt_pkg.mirror_store_layer('snapshot_check','objects',review=>true);
SELECT utt_pkg.mirror_accept_layer('snapshot_check','objects');
DO $$BEGIN
 ASSERT (SELECT count(*)=2 FROM mirror.snapshot_check_stored WHERE id=1);
 ASSERT (SELECT value='returned' FROM mirror.snapshot_check);
END$$;
-- Failed row reads never publish absence.
DROP TABLE mirror.snapshot_check_source;
SELECT utt_pkg.mirror_store_layer('snapshot_check','objects');
DO $$BEGIN
 ASSERT (SELECT count(*)=1 FROM mirror.snapshot_check);
 ASSERT EXISTS(SELECT FROM mirror.import i JOIN mirror.registry r ON r.row_id=i.registry_row_id
   WHERE r.source_name='snapshot_check' AND i.status='failed');
END$$;
ROLLBACK;

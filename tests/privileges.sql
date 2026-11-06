-- Bootstrap login; disposable database only. All fixture roles/objects roll back.
\set ON_ERROR_STOP on
BEGIN;
CALL utt_pkg.create_admin('privilege_admin_alice');
CALL utt_pkg.create_admin('privilege_admin_bob');
SET SESSION AUTHORIZATION privilege_admin_alice;
CALL utt_pkg.create_developer('privilege_dev_alice');
CALL utt_pkg.create_developer('privilege_dev_bob');
DO $$DECLARE account_name text; sandbox_name text; BEGIN
 ASSERT NOT EXISTS(SELECT FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname IN ('sandbox_privilege_dev_alice','sandbox_privilege_dev_bob'));
 ASSERT NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('sandbox_privilege_dev_alice','sandbox_privilege_dev_bob'));
END$$;
CREATE TABLE mirror.privilege_example(id integer GENERATED ALWAYS AS IDENTITY, value text);
INSERT INTO mirror.privilege_example(value) VALUES('shared');
CREATE VIEW mirror.privilege_example_view AS SELECT * FROM mirror.privilege_example;
CREATE TABLE mirror.privilege_rows_source(id integer, value text);
INSERT INTO mirror.privilege_rows_source VALUES(1,'accepted');
INSERT INTO mirror.registry(source_name,layer_name,source_type,source_url,table_base,stable_key)
VALUES('privilege_rows','features','file','/source-files/test','privilege_rows',ARRAY['id']);
SELECT mirror.store_layer('privilege_rows','features',true);
SELECT mirror.reject_layer('privilege_rows','features');
SELECT mirror.store_layer('privilege_rows','features',true);
SELECT mirror.accept_layer('privilege_rows','features');
CREATE FUNCTION mirror.privilege_mutation() RETURNS void LANGUAGE sql SECURITY DEFINER
AS 'DELETE FROM mirror.privilege_example';
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION privilege_admin_bob;
ALTER TABLE mirror.privilege_example ADD COLUMN extra integer;
CALL utt_pkg.create_developer('privilege_dev_late');
CALL utt_pkg.create_admin('privilege_admin_late');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION privilege_admin_late;
ALTER TABLE mirror.privilege_example ADD COLUMN later integer;
DO $$DECLARE protected_schema text; BEGIN
 FOREACH protected_schema IN ARRAY ARRAY['mirror','curation','utt_pkg','citydb','citydb_pkg'] LOOP
   EXECUTE format('CREATE TABLE %I.privilege_future (id integer)',protected_schema);
   EXECUTE format('CREATE VIEW %I.privilege_future_view AS SELECT * FROM %I.privilege_future',protected_schema,protected_schema);
 END LOOP;
END$$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION privilege_dev_alice;
CREATE TABLE sandbox_privilege_dev_alice.example(id integer);
INSERT INTO sandbox_privilege_dev_alice.example VALUES(1);
ALTER TABLE sandbox_privilege_dev_alice.example ADD COLUMN label text;
CREATE VIEW sandbox_privilege_dev_alice.example_view AS SELECT * FROM sandbox_privilege_dev_alice.example;
CREATE TABLE sandbox_privilege_dev_alice.disposable(id integer);
DROP TABLE sandbox_privilege_dev_alice.disposable;
CREATE FUNCTION sandbox_privilege_dev_alice.mutate() RETURNS void LANGUAGE sql SECURITY DEFINER
AS 'DELETE FROM sandbox_privilege_dev_alice.example';
DO $$DECLARE account_name text; sandbox_name text; BEGIN
 BEGIN account_name:='privilege_escalation'; CALL utt_pkg.create_admin(account_name); RAISE EXCEPTION 'provisioning allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM mirror.privilege_mutation(); RAISE EXCEPTION 'mutation allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM nextval('mirror.privilege_example_id_seq'); RAISE EXCEPTION 'sequence advancement allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END$$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION privilege_dev_bob;
SELECT * FROM sandbox_privilege_dev_alice.example;
SELECT * FROM sandbox_privilege_dev_alice.example_view;
CREATE TABLE sandbox_privilege_dev_bob.example(id integer);
INSERT INTO sandbox_privilege_dev_bob.example VALUES(2);
ALTER TABLE sandbox_privilege_dev_bob.example ADD COLUMN label text;
CREATE TABLE sandbox_privilege_dev_bob.disposable(id integer);
DROP TABLE sandbox_privilege_dev_bob.disposable;
DO $$DECLARE account_name text; sandbox_name text; BEGIN
 BEGIN UPDATE sandbox_privilege_dev_alice.example SET id=2; RAISE EXCEPTION 'peer update allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN ALTER TABLE sandbox_privilege_dev_alice.example ADD COLUMN forbidden integer; RAISE EXCEPTION 'peer alter allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN DROP TABLE sandbox_privilege_dev_alice.example; RAISE EXCEPTION 'peer drop allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM sandbox_privilege_dev_alice.mutate(); RAISE EXCEPTION 'peer function allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END$$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION privilege_dev_late;
SELECT * FROM mirror.privilege_example_view;
SELECT * FROM mirror.registry;
SELECT * FROM mirror.privilege_rows;
SELECT * FROM mirror.privilege_rows_stored;
SELECT * FROM curation.dataset_build;
SELECT * FROM sandbox_privilege_dev_alice.example;
SELECT * FROM sandbox_privilege_dev_bob.example;
DO $$DECLARE protected_schema text; BEGIN
 FOREACH protected_schema IN ARRAY ARRAY['mirror','curation','utt_pkg','citydb','citydb_pkg'] LOOP
   ASSERT has_schema_privilege(current_user,protected_schema,'USAGE');
   ASSERT NOT has_schema_privilege(current_user,protected_schema,'CREATE');
   EXECUTE format('SELECT * FROM %I.privilege_future_view',protected_schema);
   BEGIN EXECUTE format('CREATE TABLE %I.forbidden(id integer)',protected_schema); RAISE EXCEPTION 'shared create allowed';
   EXCEPTION WHEN insufficient_privilege THEN NULL; END;
   BEGIN EXECUTE format('INSERT INTO %I.privilege_future VALUES(1)',protected_schema); RAISE EXCEPTION 'shared insert allowed';
   EXCEPTION WHEN insufficient_privilege THEN NULL; END;
   BEGIN EXECUTE format('UPDATE %I.privilege_future SET id=1',protected_schema); RAISE EXCEPTION 'shared update allowed';
   EXCEPTION WHEN insufficient_privilege THEN NULL; END;
   BEGIN EXECUTE format('DELETE FROM %I.privilege_future',protected_schema); RAISE EXCEPTION 'shared delete allowed';
   EXCEPTION WHEN insufficient_privilege THEN NULL; END;
   BEGIN EXECUTE format('TRUNCATE %I.privilege_future',protected_schema); RAISE EXCEPTION 'shared truncate allowed';
   EXCEPTION WHEN insufficient_privilege THEN NULL; END;
   BEGIN EXECUTE format('ALTER TABLE %I.privilege_future ADD COLUMN forbidden integer',protected_schema); RAISE EXCEPTION 'shared alter allowed';
   EXCEPTION WHEN insufficient_privilege THEN NULL; END;
   BEGIN EXECUTE format('DROP TABLE %I.privilege_future',protected_schema); RAISE EXCEPTION 'shared drop allowed';
   EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
END$$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION privilege_admin_bob;
SELECT mirror.unregister_source('privilege_rows','features');
SELECT utt_pkg.create_developer_sandbox('privilege_dev_alice');
ALTER TABLE sandbox_privilege_dev_alice.example ADD COLUMN administered integer;
DO $$DECLARE account_name text; sandbox_name text; BEGIN
 ASSERT (SELECT count(*)=1 FROM sandbox_privilege_dev_alice.example);
 BEGIN account_name:='privilege_dev_alice'; CALL utt_pkg.create_developer(account_name,sandbox_name); RAISE EXCEPTION 'duplicate account allowed';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'Account already exists.' THEN RAISE; END IF; END;
 BEGIN account_name:='Privilege_Dev_Alice'; CALL utt_pkg.create_developer(account_name,sandbox_name); RAISE EXCEPTION 'normalization alias allowed';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'Invalid or overlength developer login.' THEN RAISE; END IF; END;
 BEGIN account_name:=repeat('x',64); CALL utt_pkg.create_developer(account_name,sandbox_name); RAISE EXCEPTION 'truncation allowed';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'Invalid or overlength developer login.' THEN RAISE; END IF; END;
END$$;
CREATE SCHEMA sandbox_privilege_collision;
DO $$DECLARE account_name text; sandbox_name text; BEGIN
 BEGIN account_name:='privilege_collision'; CALL utt_pkg.create_developer(account_name,sandbox_name); RAISE EXCEPTION 'schema collision allowed';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE 'Sandbox % already belongs to another role.' THEN RAISE; END IF; END;
 ASSERT NOT EXISTS(SELECT FROM pg_roles WHERE rolname='privilege_collision');
END$$;
SELECT utt_pkg.create_developer_sandbox('privilege_admin_bob');
CREATE TABLE sandbox_privilege_admin_bob.example(id integer);
CALL utt_pkg.deactivate_account('privilege_dev_alice');
RESET SESSION AUTHORIZATION;
DO $$DECLARE account_name text; sandbox_name text; BEGIN
 ASSERT to_regclass('sandbox_privilege_dev_alice.example') IS NOT NULL;
 ASSERT (SELECT relowner='utt_admin'::regrole FROM pg_class WHERE oid='mirror.privilege_example'::regclass);
 ASSERT NOT (SELECT rolsuper OR rolcreaterole FROM pg_roles WHERE rolname='privilege_admin_alice');
END$$;
ROLLBACK;

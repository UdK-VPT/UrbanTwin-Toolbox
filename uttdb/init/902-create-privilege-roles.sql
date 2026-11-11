-- Fresh initialization, run by the bootstrap PostgreSQL superuser.
-- All UTT privilege policy lives here, including future-object policy.
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='utt_admin') THEN
    CREATE ROLE utt_admin NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='utt_developer') THEN
    CREATE ROLE utt_developer NOLOGIN;
  END IF;
  ALTER ROLE utt_admin NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
  ALTER ROLE utt_developer NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
  EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC',current_database());
  EXECUTE format('GRANT CONNECT, TEMPORARY ON DATABASE %I TO utt_admin, utt_developer',current_database());
  EXECUTE format('GRANT CREATE ON DATABASE %I TO utt_admin',current_database());
  EXECUTE format('GRANT utt_admin TO %I WITH ADMIN OPTION',current_user);
END $$;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON FOREIGN DATA WRAPPER ogr_fdw, postgres_fdw TO utt_admin;
-- Trusted administrators manage source files; no SUPERUSER is granted.
GRANT pg_read_server_files TO utt_admin;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_stat_file(text),
  pg_catalog.pg_read_binary_file(text),
  pg_catalog.pg_read_binary_file(text,bigint,bigint) TO utt_admin;
GRANT SET ON PARAMETER "postgis.gdal_enabled_drivers" TO utt_admin;
COMMENT ON ROLE utt_admin IS 'Trusted UTT administrators; shared object owner. Individual logins remain identifiable as session_user.';
COMMENT ON ROLE utt_developer IS 'Researchers and developers: shared reads and individually owned sandboxes.';

-- Scheduler configuration uses upstream functions, never table writes. Jobs run
-- as individual administrator logins; the bootstrap superuser cannot schedule.
-- Retain upstream extension ownership, RLS and per-owner mutation checks.
REVOKE ALL ON SCHEMA cron FROM PUBLIC, utt_developer;
REVOKE ALL ON ALL TABLES IN SCHEMA cron FROM PUBLIC, utt_developer;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA cron FROM PUBLIC, utt_developer;
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA cron FROM PUBLIC, utt_developer;
GRANT USAGE ON SCHEMA cron TO utt_admin;
GRANT SELECT ON cron.job, cron.job_run_details TO utt_admin;
GRANT EXECUTE ON FUNCTION cron.schedule(text,text), cron.schedule(text,text,text),
  cron.alter_job(bigint,text,text,text,text,boolean),
  cron.unschedule(bigint), cron.unschedule(text) TO utt_admin;
-- SELECT-only policy lets the utt_admin-owned mirror view see all jobs. This
-- grants no UPDATE/INSERT/DELETE rights and does not change API ownership checks.
CREATE POLICY utt_admin_job_visibility ON cron.job
  FOR SELECT TO utt_admin USING (true);

-- A single narrowly scoped DDL boundary makes ownership/defaults independent of
-- which administrator executes DDL. It also covers the optional curation schema.
CREATE OR REPLACE FUNCTION utt_pkg.apply_shared_privileges()
RETURNS event_trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog AS $$
DECLARE command record; object_owner oid; admin_oid oid := 'utt_admin'::regrole;
BEGIN
  FOR command IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
    IF command.in_extension THEN CONTINUE; END IF;
    IF command.classid='pg_foreign_server'::regclass THEN
      SELECT srvowner INTO object_owner FROM pg_foreign_server WHERE oid=command.objid;
      IF object_owner<>admin_oid AND pg_has_role(object_owner,admin_oid,'MEMBER') THEN
        EXECUTE format('ALTER SERVER %s OWNER TO utt_admin',command.object_identity);
      END IF;
    ELSIF command.classid='pg_namespace'::regclass THEN
      IF command.object_identity NOT IN ('mirror','curation','utt_pkg','citydb','citydb_pkg') THEN CONTINUE; END IF;
      SELECT nspowner INTO object_owner FROM pg_namespace WHERE oid=command.objid;
      IF object_owner<>admin_oid THEN
        EXECUTE format('ALTER SCHEMA %s OWNER TO utt_admin',command.object_identity);
      END IF;
      EXECUTE format('REVOKE ALL ON SCHEMA %s FROM PUBLIC',command.object_identity);
      EXECUTE format('GRANT USAGE ON SCHEMA %s TO utt_developer',command.object_identity);
    ELSIF command.schema_name IN ('mirror','curation','utt_pkg','citydb','citydb_pkg')
      OR EXISTS(SELECT FROM pg_namespace WHERE nspname=command.schema_name
        AND nspname LIKE 'sandbox\_%' ESCAPE '\' AND nspowner=admin_oid) THEN
      IF command.classid='pg_class'::regclass AND command.object_type IN
        ('table','partitioned table','view','materialized view','foreign table','sequence') THEN
        SELECT relowner INTO object_owner FROM pg_class WHERE oid=command.objid;
        IF object_owner<>admin_oid AND NOT (command.object_type='sequence' AND EXISTS(
          SELECT FROM pg_depend WHERE classid='pg_class'::regclass AND objid=command.objid
          AND refclassid='pg_class'::regclass AND deptype IN ('a','i'))) THEN
          EXECUTE format('ALTER %s %s OWNER TO utt_admin',command.object_type,command.object_identity);
        END IF;
        EXECUTE format('REVOKE ALL ON %s %s FROM PUBLIC',
          CASE WHEN command.object_type='sequence' THEN 'SEQUENCE' ELSE 'TABLE' END,command.object_identity);
        EXECUTE format('GRANT SELECT ON %s %s TO utt_developer',
          CASE WHEN command.object_type='sequence' THEN 'SEQUENCE' ELSE 'TABLE' END,command.object_identity);
      ELSIF command.classid='pg_proc'::regclass THEN
        -- Provisioning and this hook retain their bootstrap owner: they are the
        -- narrow boundaries for role creation and event-trigger administration.
        IF command.schema_name='utt_pkg' AND EXISTS(SELECT FROM pg_proc
          WHERE oid=command.objid AND proname IN
            ('apply_shared_privileges','create_admin','create_developer','create_developer_sandbox','deactivate_account')) THEN
          CONTINUE;
        END IF;
        SELECT proowner INTO object_owner FROM pg_proc WHERE oid=command.objid;
        IF object_owner<>admin_oid THEN
          EXECUTE format('ALTER ROUTINE %s OWNER TO utt_admin',command.object_identity);
        END IF;
        EXECUTE format('REVOKE ALL ON ROUTINE %s FROM PUBLIC, utt_developer',command.object_identity);
        EXECUTE format('GRANT EXECUTE ON ROUTINE %s TO utt_admin',command.object_identity);
        IF command.schema_name='mirror' AND command.objid=to_regprocedure('mirror.read_geotiff(text)') THEN
          EXECUTE format('GRANT EXECUTE ON ROUTINE %s TO utt_developer',command.object_identity);
        END IF;
      ELSIF command.classid='pg_type'::regclass AND command.object_type IN ('type','domain') THEN
        SELECT typowner INTO object_owner FROM pg_type WHERE oid=command.objid;
        IF object_owner<>admin_oid THEN
          EXECUTE format('ALTER %s %s OWNER TO utt_admin',command.object_type,command.object_identity);
        END IF;
      END IF;
    END IF;
  END LOOP;
END $$;
COMMENT ON FUNCTION utt_pkg.apply_shared_privileges() IS 'Internal bootstrap-owned ddl_command_end policy. Called only by the UTT event trigger; gives protected shared objects common administrative ownership, developer reads and restricted routine execution. Skips extension members and bootstrap privilege helpers. Returns event_trigger. Example firing it: CREATE TABLE mirror.example (id integer);';
REVOKE ALL ON FUNCTION utt_pkg.apply_shared_privileges() FROM PUBLIC;
DROP EVENT TRIGGER IF EXISTS utt_shared_privileges;
CREATE EVENT TRIGGER utt_shared_privileges ON ddl_command_end
WHEN TAG IN ('CREATE SCHEMA','CREATE TABLE','CREATE TABLE AS','SELECT INTO',
 'CREATE VIEW','CREATE MATERIALIZED VIEW','CREATE FOREIGN TABLE','CREATE SEQUENCE',
 'CREATE FUNCTION','CREATE PROCEDURE','CREATE TYPE','CREATE DOMAIN','CREATE SERVER',
 'ALTER TABLE','ALTER FOREIGN TABLE','ALTER VIEW','ALTER MATERIALIZED VIEW',
 'ALTER SEQUENCE','ALTER TYPE','ALTER DOMAIN')
EXECUTE FUNCTION utt_pkg.apply_shared_privileges();

-- Upstream objects already exist before 902. Preserve their definitions and
-- extension ownership, while transferring ordinary 3DCityDB objects explicitly.
DO $$ DECLARE item record; schema_name text; BEGIN
  FOREACH schema_name IN ARRAY ARRAY['mirror','utt_pkg','citydb','citydb_pkg','curation'] LOOP
    IF to_regnamespace(schema_name) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('ALTER SCHEMA %I OWNER TO utt_admin',schema_name);
    EXECUTE format('REVOKE ALL ON SCHEMA %I FROM PUBLIC',schema_name);
    EXECUTE format('GRANT USAGE ON SCHEMA %I TO utt_developer',schema_name);
    FOR item IN SELECT c.oid,c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname=schema_name AND c.relkind IN ('r','p','v','m','f','S')
      AND NOT EXISTS(SELECT FROM pg_depend WHERE classid='pg_class'::regclass AND objid=c.oid AND deptype='e')
      ORDER BY CASE WHEN c.relkind='S' THEN 1 ELSE 0 END LOOP
      EXECUTE format('ALTER %s %s OWNER TO utt_admin',
        CASE item.relkind WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW'
        WHEN 'f' THEN 'FOREIGN TABLE' WHEN 'S' THEN 'SEQUENCE' ELSE 'TABLE' END,item.oid::regclass);
    END LOOP;
    FOR item IN SELECT p.oid,p.oid::regprocedure AS signature FROM pg_proc p
      JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname=schema_name
      AND NOT (n.nspname='utt_pkg' AND p.proname IN ('apply_shared_privileges','create_admin','create_developer','create_developer_sandbox','deactivate_account'))
      AND NOT EXISTS(SELECT FROM pg_depend WHERE classid='pg_proc'::regclass AND objid=p.oid AND deptype='e') LOOP
      EXECUTE format('ALTER ROUTINE %s OWNER TO utt_admin',item.signature);
    END LOOP;
    EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA %I FROM PUBLIC',schema_name);
    EXECUTE format('REVOKE ALL ON ALL SEQUENCES IN SCHEMA %I FROM PUBLIC',schema_name);
    EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA %I TO utt_developer',schema_name);
    EXECUTE format('REVOKE ALL ON ALL ROUTINES IN SCHEMA %I FROM PUBLIC, utt_developer',schema_name);
    EXECUTE format('GRANT EXECUTE ON ALL ROUTINES IN SCHEMA %I TO utt_admin',schema_name);
  END LOOP;
  IF to_regprocedure('mirror.read_geotiff(text)') IS NOT NULL THEN
    GRANT EXECUTE ON FUNCTION mirror.read_geotiff(text) TO utt_developer;
  END IF;
END $$;
-- Global revoke is required: a schema-local revoke cannot undo PUBLIC's global default.
ALTER DEFAULT PRIVILEGES FOR ROLE utt_admin REVOKE EXECUTE ON ROUTINES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE utt_admin GRANT SELECT ON TABLES TO utt_developer;

CREATE OR REPLACE FUNCTION utt_pkg.create_developer_sandbox(developer_role text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE sandbox_schema text; sandbox_owner text;
BEGIN
  IF NOT pg_has_role(session_user,'utt_admin','MEMBER') THEN
    RAISE EXCEPTION 'Only utt_admin members may provision sandboxes.';
  END IF;
  IF developer_role IS NULL OR developer_role !~ '^[a-z][a-z0-9_]*$'
    OR octet_length('sandbox_'||developer_role)>63 THEN
    RAISE EXCEPTION 'Use a lowercase ASCII login beginning with a letter; sandbox name must fit 63 bytes.';
  END IF;
  IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname=developer_role AND rolcanlogin AND NOT rolsuper) THEN
    RAISE EXCEPTION 'Expected an existing individual, non-superuser login.';
  END IF;
  -- Admin researchers inherit sandbox ownership through utt_admin, avoiding
  -- the circular membership that individual ownership membership would require.
  sandbox_owner:=CASE WHEN pg_has_role(developer_role,'utt_admin','MEMBER')
    THEN 'utt_admin' ELSE developer_role END;
  sandbox_schema:='sandbox_'||developer_role;
  IF EXISTS(SELECT FROM pg_namespace WHERE nspname=sandbox_schema AND nspowner<>(SELECT oid FROM pg_roles WHERE rolname=sandbox_owner)) THEN
    RAISE EXCEPTION 'Sandbox % already belongs to another role.',sandbox_schema;
  END IF;
  EXECUTE format('GRANT utt_developer TO %I',developer_role);
  IF sandbox_owner<>'utt_admin' THEN
    EXECUTE format('GRANT %I TO utt_admin',developer_role);
  END IF;
  IF to_regnamespace(sandbox_schema) IS NULL THEN
    EXECUTE format('CREATE SCHEMA %I AUTHORIZATION %I',sandbox_schema,sandbox_owner);
  END IF;
  EXECUTE format('REVOKE ALL ON SCHEMA %I FROM PUBLIC',sandbox_schema);
  EXECUTE format('GRANT USAGE ON SCHEMA %I TO utt_developer',sandbox_schema);
  EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA %I TO utt_developer',sandbox_schema);
  EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I GRANT SELECT ON TABLES TO utt_developer',developer_role,sandbox_schema);
  -- Sandbox security-definer routines must never become a peer mutation path.
  EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I REVOKE EXECUTE ON ROUTINES FROM PUBLIC',developer_role);
  RETURN sandbox_schema;
END $$;
COMMENT ON FUNCTION utt_pkg.create_developer_sandbox(text) IS 'Administrator entry for an existing individual developer login. Creates an empty owned sandbox, or safely reuses its matching schema; configures peer SELECT defaults and administrative ownership membership. Returns schema name. Administrator sandboxes use inherited utt_admin ownership to avoid membership cycles. Rejects invalid names and collisions; does not reset objects. Example: SELECT utt_pkg.create_developer_sandbox(''alice'');';

CREATE OR REPLACE PROCEDURE utt_pkg.create_developer(INOUT login_name text, INOUT sandbox_schema text DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
  IF NOT pg_has_role(session_user,'utt_admin','MEMBER') THEN RAISE EXCEPTION 'Only utt_admin members may create accounts.'; END IF;
  IF login_name IS NULL OR login_name !~ '^[a-z][a-z0-9_]*$' OR octet_length('sandbox_'||login_name)>63 THEN
    RAISE EXCEPTION 'Invalid or overlength developer login.';
  END IF;
  IF EXISTS(SELECT FROM pg_roles WHERE rolname=login_name) THEN RAISE EXCEPTION 'Account already exists.'; END IF;
  EXECUTE format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION',login_name);
  sandbox_schema:=utt_pkg.create_developer_sandbox(login_name);
END $$;
COMMENT ON PROCEDURE utt_pkg.create_developer(text,text) IS 'Administrator-only atomic account provisioning: creates a passwordless individual LOGIN, developer membership and empty owned sandbox with peer read defaults. Returns login_name and sandbox_schema. Set credentials separately with psql password command or deployment authentication. Duplicate accounts fail. Example: CALL utt_pkg.create_developer(''alice'');';

CREATE OR REPLACE PROCEDURE utt_pkg.create_admin(INOUT login_name text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
  IF NOT pg_has_role(session_user,'utt_admin','MEMBER') THEN RAISE EXCEPTION 'Only utt_admin members may create accounts.'; END IF;
  IF login_name IS NULL OR login_name !~ '^[a-z][a-z0-9_]*$' OR octet_length(login_name)>63 THEN RAISE EXCEPTION 'Invalid administrator login.'; END IF;
  IF EXISTS(SELECT FROM pg_roles WHERE rolname=login_name) THEN RAISE EXCEPTION 'Account already exists.'; END IF;
  EXECUTE format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION',login_name);
  EXECUTE format('GRANT utt_admin TO %I',login_name);
END $$;
COMMENT ON PROCEDURE utt_pkg.create_admin(text) IS 'Administrator-only atomic provisioning of an individual passwordless LOGIN with utt_admin membership and no sandbox. Returns login_name; credentials are configured separately. Bootstrap installation login receives utt_admin membership in 902 and provisions the first human admin. Example: CALL utt_pkg.create_admin(''bob'');';
REVOKE ALL ON FUNCTION utt_pkg.create_developer_sandbox(text) FROM PUBLIC;
REVOKE ALL ON PROCEDURE utt_pkg.create_developer(text,text), utt_pkg.create_admin(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION utt_pkg.create_developer_sandbox(text) TO utt_admin;
GRANT EXECUTE ON PROCEDURE utt_pkg.create_developer(text,text), utt_pkg.create_admin(text) TO utt_admin;

CREATE OR REPLACE PROCEDURE utt_pkg.deactivate_account(login_name text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
  IF NOT pg_has_role(session_user,'utt_admin','MEMBER') THEN RAISE EXCEPTION 'Only utt_admin members may deactivate accounts.'; END IF;
  IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname=login_name AND rolcanlogin AND NOT rolsuper
    AND (pg_has_role(oid,'utt_admin','MEMBER') OR pg_has_role(oid,'utt_developer','MEMBER'))) THEN
    RAISE EXCEPTION 'Expected an active, non-superuser UTT login.';
  END IF;
  EXECUTE format('ALTER ROLE %I NOLOGIN',login_name);
END $$;
COMMENT ON PROCEDURE utt_pkg.deactivate_account(text) IS 'Administrator-only account deactivation: sets a non-superuser UTT login NOLOGIN, without deleting roles, sandbox objects or memberships. Existing sessions are unaffected. Returns no result. Example: CALL utt_pkg.deactivate_account(''alice'');';
REVOKE ALL ON PROCEDURE utt_pkg.deactivate_account(text) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE utt_pkg.deactivate_account(text) TO utt_admin;

DO $$
DECLARE
  db_name name := current_database();
  role_name name;
BEGIN
  FOREACH role_name IN ARRAY ARRAY[
    'uttdb_dba',
    'uttdb_reader',
    'uttdb_developer',
    'uttdb_pipeline',
    'uttdb_app_reader',
    'uttdb_app_writer'
  ]::name[]
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN', role_name);
    END IF;
  END LOOP;

  EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC', db_name);
  EXECUTE format(
    'GRANT CONNECT, TEMPORARY ON DATABASE %I TO uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer',
    db_name
  );
  EXECUTE format('GRANT CONNECT, TEMPORARY, CREATE ON DATABASE %I TO uttdb_dba', db_name);
  EXECUTE format('GRANT uttdb_dba TO %I', current_user);
  EXECUTE format('GRANT uttdb_pipeline TO %I', current_user);
END
$$;

REVOKE CREATE ON SCHEMA public FROM PUBLIC;

GRANT USAGE ON SCHEMA citydb TO uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT USAGE ON SCHEMA mirror TO uttdb_reader, uttdb_developer, uttdb_pipeline;
GRANT USAGE ON SCHEMA utt_pkg TO uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;

GRANT SELECT ON ALL TABLES IN SCHEMA citydb TO uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT SELECT ON ALL TABLES IN SCHEMA mirror TO uttdb_reader, uttdb_developer, uttdb_pipeline;
GRANT SELECT ON ALL TABLES IN SCHEMA utt_pkg TO uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA citydb TO uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA mirror TO uttdb_reader, uttdb_developer, uttdb_pipeline;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA utt_pkg TO uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;

GRANT ALL PRIVILEGES ON SCHEMA citydb, mirror, utt_pkg TO uttdb_dba;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA citydb, mirror, utt_pkg TO uttdb_dba;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA citydb, mirror, utt_pkg TO uttdb_dba;
GRANT ALL PRIVILEGES ON ALL ROUTINES IN SCHEMA utt_pkg TO uttdb_dba;

ALTER DEFAULT PRIVILEGES IN SCHEMA citydb GRANT SELECT ON TABLES TO uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA mirror GRANT SELECT ON TABLES TO uttdb_reader, uttdb_developer, uttdb_pipeline;
ALTER DEFAULT PRIVILEGES IN SCHEMA utt_pkg GRANT SELECT ON TABLES TO uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA citydb, mirror, utt_pkg GRANT USAGE, SELECT ON SEQUENCES TO uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;

ALTER DEFAULT PRIVILEGES FOR ROLE uttdb_pipeline IN SCHEMA mirror GRANT SELECT ON TABLES TO uttdb_reader, uttdb_developer, uttdb_pipeline;
ALTER DEFAULT PRIVILEGES FOR ROLE uttdb_pipeline IN SCHEMA utt_pkg GRANT SELECT ON TABLES TO uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
ALTER DEFAULT PRIVILEGES FOR ROLE uttdb_pipeline IN SCHEMA mirror, utt_pkg GRANT USAGE, SELECT ON SEQUENCES TO uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;

CREATE OR REPLACE FUNCTION utt_pkg.create_developer_sandbox(developer_role name)
RETURNS name
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  sandbox_schema name;
BEGIN
  IF NOT pg_has_role(session_user, 'uttdb_dba', 'member') THEN
    RAISE EXCEPTION 'Only members of uttdb_dba can create developer sandboxes.';
  END IF;

  IF developer_role IS NULL OR developer_role::text = '' THEN
    RAISE EXCEPTION 'Developer role name must not be empty.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = developer_role::text) THEN
    RAISE EXCEPTION 'Role % does not exist.', developer_role;
  END IF;

  sandbox_schema := (
    'sandbox_' || lower(regexp_replace(developer_role::text, '[^a-zA-Z0-9_]+', '_', 'g'))
  )::name;

  EXECUTE format('GRANT uttdb_developer TO %I', developer_role);
  EXECUTE format('CREATE SCHEMA IF NOT EXISTS %I AUTHORIZATION %I', sandbox_schema, developer_role);
  EXECUTE format('GRANT USAGE, CREATE ON SCHEMA %I TO %I', sandbox_schema, developer_role);
  EXECUTE format('GRANT ALL PRIVILEGES ON SCHEMA %I TO uttdb_dba', sandbox_schema);
  EXECUTE format('COMMENT ON SCHEMA %I IS %L', sandbox_schema, 'Per-developer UTTDB sandbox schema.');

  RETURN sandbox_schema;
END;
$$;

REVOKE ALL ON FUNCTION utt_pkg.create_developer_sandbox(name) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION utt_pkg.create_developer_sandbox(name) TO uttdb_dba;

COMMENT ON FUNCTION utt_pkg.create_developer_sandbox(name) IS
  'Creates or reuses a sandbox_<role> schema owned by an existing developer login role, grants that login membership in uttdb_developer, and returns the sandbox schema name. Only a session user who is a member of uttdb_dba may call this security-definer function. Example, after creating login role alice: SELECT utt_pkg.create_developer_sandbox(''alice'');';

COMMENT ON ROLE uttdb_dba IS 'UTTDB administrators. Can provision logins, sandbox schemas, and database-owned objects.';
COMMENT ON ROLE uttdb_reader IS 'UTTDB read-only access for trusted humans and diagnostics.';
COMMENT ON ROLE uttdb_developer IS 'UTTDB developer access. Reads curated schemas and works inside assigned sandbox schemas.';
COMMENT ON ROLE uttdb_pipeline IS 'UTTDB data pipeline role for controlled snapshot builds; mirror administration remains DBA-only.';
COMMENT ON ROLE uttdb_app_reader IS 'UTTDB application read role for APIs and services.';
COMMENT ON ROLE uttdb_app_writer IS 'UTTDB application mutation role. Prefer package/API functions over direct table writes.';

ALTER DEFAULT PRIVILEGES IN SCHEMA utt_pkg REVOKE EXECUTE ON ROUTINES FROM PUBLIC;

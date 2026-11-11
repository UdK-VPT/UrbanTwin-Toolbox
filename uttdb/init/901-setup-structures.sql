-- Remove unused PostGIS structures
DROP EXTENSION IF EXISTS postgis_tiger_geocoder CASCADE;
DROP EXTENSION IF EXISTS postgis_topology CASCADE;
DROP SCHEMA IF EXISTS tiger CASCADE;
DROP SCHEMA IF EXISTS tiger_data CASCADE;
DROP SCHEMA IF EXISTS topology CASCADE;

-- Keep extension objects in public; extension files are supplied by the database image.
CREATE EXTENSION IF NOT EXISTS postgres_fdw WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS ogr_fdw WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS http WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS postgis_raster WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;

-- pg_cron owns its cron schema; initialized in POSTGRES_DB after the preload
-- restart in 900-utt-init.sh. No jobs are installed by initialization.
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Create project schemas
CREATE SCHEMA IF NOT EXISTS mirror;
CREATE SCHEMA IF NOT EXISTS utt_pkg;

COMMENT ON SCHEMA mirror IS 'Source registry, ingestion routines, acceptance and accepted history.';
COMMENT ON SCHEMA utt_pkg IS 'Shared UrbanTwin-Toolbox administration helpers; independent of mirror and project curation.';

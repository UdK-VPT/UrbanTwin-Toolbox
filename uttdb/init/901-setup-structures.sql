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

-- Create project schemas
CREATE SCHEMA IF NOT EXISTS mirror;
CREATE SCHEMA IF NOT EXISTS utt;
CREATE SCHEMA IF NOT EXISTS utt_pkg;

COMMENT ON SCHEMA mirror IS 'Self-owned mirror of upstream GIS source data.';
COMMENT ON SCHEMA utt IS 'Curated UrbanTwin-Toolbox project truth derived from mirrored and integrated sources.';
COMMENT ON SCHEMA utt_pkg IS 'UrbanTwin-Toolbox database functions and procedures that coordinate citydb, mirror, and utt schemas.';

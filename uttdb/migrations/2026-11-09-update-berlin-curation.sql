-- Development migration for an existing database initialized with the previous 913.
-- Run as the bootstrap DBA or utt_admin member, from the repository root:
-- psql -X -v ON_ERROR_STOP=1 -f uttdb/migrations/2026-11-09-update-berlin-curation.sql
-- Updates only the Berlin entry point and its comment. Existing output tables,
-- build metadata, procedure identity, ownership and privileges are preserved.
-- Does not run curation. Init files 901-903 need no changes.
BEGIN;

CREATE OR REPLACE PROCEDURE curation.curate_berlin_20261101(
    snapshot_at timestamptz DEFAULT NULL,
    region public.geometry DEFAULT NULL,git_revision text DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog SET TimeZone='UTC' AS $$
DECLARE entity text; output_name text; columns_sql text; unresolved_layers text;
BEGIN
    IF snapshot_at IS NOT NULL AND (NOT isfinite(snapshot_at) OR snapshot_at>clock_timestamp()) THEN
      RAISE EXCEPTION 'Choose a finite mirror snapshot at or before build time.';
    END IF;
    IF region IS NOT NULL AND (public.ST_IsEmpty(region) OR NOT public.ST_IsValid(region)
      OR public.ST_SRID(region)<=0) THEN RAISE EXCEPTION 'Region requires valid nonempty geometry with an explicit source-compatible CRS.'; END IF;
    PERFORM pg_advisory_xact_lock(70303,1);
    -- Prevent source publication/schema changes during the cooperating input selection.
    LOCK TABLE mirror.registry IN EXCLUSIVE MODE;
    SELECT string_agg(required.source_name || '/' || required.layer_name, ', '
                      ORDER BY required.source_name,required.layer_name)
      INTO unresolved_layers
    FROM (VALUES
      ('berlin_alkis','alkis:land'),
      ('berlin_alkis','alkis:bezirk'),
      ('berlin_alkis','alkis:flurstuecke'),
      ('berlin_alkis_gebaeude','alkis_gebaeude:gebaeude'),
      ('berlin_bloecke','bloecke:rbs_bloecke'),
      ('berlin_adressen','adressen_rbs:adressen_rbs')
    ) AS required(source_name,layer_name)
    LEFT JOIN mirror.registry r ON r.source_name=required.source_name
      AND r.layer_name=required.layer_name AND r.storage_mode='rows'
      AND (snapshot_at IS NOT NULL OR NOT r.retired)
    LEFT JOIN LATERAL (
      SELECT i.status FROM mirror.import i WHERE i.registry_row_id=r.row_id
        AND (snapshot_at IS NULL OR (i.status='accepted' AND i.accepted_at<=snapshot_at))
      ORDER BY CASE WHEN snapshot_at IS NULL THEN i.import_id END DESC,
               i.accepted_at DESC,i.import_id DESC LIMIT 1
    ) latest ON true
    WHERE latest.status IS DISTINCT FROM 'accepted';
    IF unresolved_layers IS NOT NULL THEN
      RAISE EXCEPTION 'Required Berlin sources are not ready: %',unresolved_layers
        USING HINT='For a current build, register active row sources and resolve their latest imports in mirror.import using mirror.store_layer, mirror.accept_layer or mirror.reject_layer as appropriate. Historical builds require an accepted import at or before snapshot_at.';
    END IF;
    -- Resolve once after waiting for publication/build locks; explicit times stay unchanged.
    snapshot_at:=coalesce(snapshot_at,clock_timestamp());
    CALL curation.curate_berlin_city_20261101(snapshot_at,region);
    CALL curation.curate_berlin_district_20261101(snapshot_at,region);
    CALL curation.curate_berlin_block_20261101(snapshot_at,region);
    CALL curation.curate_berlin_plot_20261101(snapshot_at,region);
    CALL curation.curate_berlin_building_20261101(snapshot_at,region);
    CALL curation.curate_berlin_address_20261101(snapshot_at,region);
    CALL curation.curate_berlin_relations_20261101();
    -- Keep output object identities stable for dependent queries and constraints.
    -- DELETE/INSERT is MVCC-safe for readers; all replacements commit together.
    LOCK TABLE curation.berlin_city,curation.berlin_district,curation.berlin_block,
      curation.berlin_plot,curation.berlin_building,curation.berlin_address,
      curation.berlin_relation_building_block,curation.berlin_relation_building_plot,curation.berlin_relation_plot_block,
      curation.dataset_build IN EXCLUSIVE MODE;
    DELETE FROM curation.berlin_relation_building_block;
    DELETE FROM curation.berlin_relation_building_plot;
    DELETE FROM curation.berlin_relation_plot_block;
    FOREACH entity IN ARRAY ARRAY['city','district','block','plot','building','address',
      'relation_building_block','relation_building_plot','relation_plot_block'] LOOP
      output_name:='berlin_'||entity;
      SELECT string_agg(quote_ident(attname),',' ORDER BY attnum) INTO columns_sql
        FROM pg_attribute WHERE attrelid=to_regclass('curation.'||output_name)
          AND attnum>0 AND NOT attisdropped;
      EXECUTE format('DELETE FROM curation.%I',output_name);
      EXECUTE format('INSERT INTO curation.%I (%s) OVERRIDING SYSTEM VALUE SELECT %s FROM pg_temp.%I',
        output_name,columns_sql,columns_sql,output_name||'_working');
      EXECUTE format('ANALYZE curation.%I',output_name);
    END LOOP;
    INSERT INTO curation.dataset_build(dataset_name,recipe_name,git_revision,mirror_snapshot,region,completed_at)
      VALUES('berlin','curation.curate_berlin_20261101',git_revision,snapshot_at,region,clock_timestamp())
      ON CONFLICT(dataset_name) DO UPDATE SET recipe_name=excluded.recipe_name,
        git_revision=excluded.git_revision,mirror_snapshot=excluded.mirror_snapshot,
        region=excluded.region,completed_at=excluded.completed_at;
END;
$$;
COMMENT ON PROCEDURE curation.curate_berlin_20261101(timestamptz,public.geometry,text) IS 'Pipeline/DBA entry point: reconstructs six Berlin entity tables and three n:m relationship tables from one accepted mirror snapshot, then installs all results and the current dataset_build row in one caller transaction. Uses indexed temporary tables; failure preserves the previous complete dataset. No internal commits, publication interface or curated history. NULL region selects full scope; explicit regions must use source-compatible CRS. Git revision is caller-supplied and nullable. Omitted or NULL snapshot_at selects one current mirror time after locking and requires active sources with accepted latest imports; explicit timestamps reconstruct accepted history independently of later import failures or retirement. Missing inputs raise exceptions with recovery hints. Standalone CALL is atomic; an explicit outer transaction controls commit when supplied. Example: CALL curation.curate_berlin_20261101(); Historical example: CALL curation.curate_berlin_20261101(snapshot_at=>''2026-11-01 00:00:00+00'');';

COMMIT;

-- Ver03: approved SQL rules, mapping integrity and shared atomic-group curation.
-- Native files may contribute their registered metadata through direct rules;
-- decoding native payloads requires a separately approved format-specific SQL rule.
CREATE FUNCTION utt_pkg.curation_rule_query(mapping_id bigint)
RETURNS text LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog SET TimeZone='UTC' AS $$
DECLARE
    m utt.curation_mapping%ROWTYPE;
    r mirror.registry%ROWTYPE;
    relation_sql text;
    source_filter text;
    key_sql text;
    identity_sql text;
    state_sql text;
    required_columns text[];
    produced_columns text[];
    expected_id_column text;
    pair record;
    target_type text;
    target_oid oid;
    expressions text[] := '{}';
    eligibility text := 'true';
BEGIN
    SELECT * INTO STRICT m FROM utt.curation_mapping WHERE curation_mapping.mapping_id=curation_rule_query.mapping_id;
    SELECT * INTO STRICT r FROM mirror.registry WHERE row_id=m.registry_row_id;
    IF r.storage_mode='rows' THEN
        relation_sql:=format('mirror.%I',r.stored_table);
        source_filter:='upper_inf(s.utt_txn)';
        SELECT 'jsonb_build_object(' || string_agg(format('%L,s.%I',k,k),',' ORDER BY n) || ')'
        INTO key_sql FROM unnest(r.stable_key) WITH ORDINALITY u(k,n);
    ELSE
        relation_sql:='mirror.registry';
        source_filter:=format('s.source_name=%L AND s.layer_name=%L AND upper_inf(s.utt_txn)',r.source_name,r.layer_name);
        key_sql:='jsonb_build_object(''source_name'',s.source_name,''layer_name'',s.layer_name)';
    END IF;
    IF m.rule_name IN ('direct_'||m.target_entity||'_v1','sum_'||m.target_entity||'_v1') THEN
        IF cardinality(m.source_columns)<>cardinality(m.target_columns) THEN
            RAISE EXCEPTION 'Direct/sum rules pair source_columns and target_columns one-to-one.';
        END IF;
        FOR pair IN SELECT sc,tc FROM unnest(m.source_columns,m.target_columns) p(sc,tc) LOOP
            SELECT format_type(atttypid,atttypmod),atttypid INTO target_type,target_oid
            FROM pg_attribute WHERE attrelid=to_regclass('utt.'||m.target_entity) AND attname=pair.tc AND NOT attisdropped;
            IF m.rule_name LIKE 'sum_%' THEN
                IF NOT EXISTS(SELECT FROM pg_type WHERE oid=target_oid AND typcategory='N') THEN
                    RAISE EXCEPTION 'Sum rules support numeric target columns only.';
                END IF;
                expressions:=array_append(expressions,format('(sum(s.%I) OVER (PARTITION BY s.%I))::%s AS %I',pair.sc,m.source_id_column,target_type,pair.tc));
            ELSE
                expressions:=array_append(expressions,format('s.%I::%s AS %I',pair.sc,target_type,pair.tc));
            END IF;
            eligibility:=eligibility||format(' AND s.%I IS NOT NULL',pair.sc);
            IF target_oid='public.geometry'::regtype THEN
                eligibility:=eligibility||format(' AND NOT public.ST_IsEmpty(s.%I) AND public.ST_SRID(s.%I)>0',pair.sc,pair.sc);
            END IF;
        END LOOP;
        identity_sql:=format('s.%I::%s',m.source_id_column,CASE WHEN m.target_entity='building' THEN 'text' ELSE 'bigint' END);
        state_sql:=array_to_string(expressions,',');
    ELSE
        IF r.storage_mode<>'rows' THEN RAISE EXCEPTION 'Berlin rules require accepted row sources.'; END IF;
        CASE m.rule_name
        WHEN 'berlin_city_v1' THEN
            expected_id_column:='lan';
            IF m.target_entity<>'city' THEN RAISE EXCEPTION 'Rule/target mismatch.'; END IF;
            required_columns:=ARRAY['lan','namlan','geom'];
            produced_columns:=ARRAY['name','geom'];
            identity_sql:=$rule$(lan)::bigint$rule$;
            state_sql:=$rule$namlan AS name,geom AS geom$rule$;
            eligibility:='geom IS NOT NULL AND NOT public.ST_IsEmpty(geom) AND public.ST_SRID(geom)>0';
        WHEN 'berlin_district_v1' THEN
            expected_id_column:='name';
            IF m.target_entity<>'district' THEN RAISE EXCEPTION 'Rule/target mismatch.'; END IF;
            required_columns:=ARRAY['name','namgem','geom'];
            produced_columns:=ARRAY['name','geom'];
            identity_sql:=$rule$(name)::bigint$rule$;
            state_sql:=$rule$namgem AS name,geom AS geom$rule$;
            eligibility:='geom IS NOT NULL AND NOT public.ST_IsEmpty(geom) AND public.ST_SRID(geom)>0';
        WHEN 'berlin_block_v1' THEN
            expected_id_column:='blknr';
            IF m.target_entity<>'block' THEN RAISE EXCEPTION 'Rule/target mismatch.'; END IF;
            required_columns:=ARRAY['blknr','geom','plr','bez','datum'];
            produced_columns:=ARRAY['geom','planning_area_no','mostly_district_id_official','centroid','source_date'];
            identity_sql:=$rule$(blknr)::bigint$rule$;
            state_sql:=$rule$geom AS geom,plr AS planning_area_no,11000000 + bez::bigint AS mostly_district_id_official,CASE WHEN public.ST_Covers(geom,public.ST_Centroid(geom)) THEN public.ST_Centroid(geom) ELSE public.ST_PointOnSurface(geom) END AS centroid,datum::timestamp AS source_date$rule$;
            eligibility:='geom IS NOT NULL AND NOT public.ST_IsEmpty(geom) AND public.ST_SRID(geom)>0';
        WHEN 'berlin_plot_v1' THEN
            expected_id_column:='fsko';
            IF m.target_entity<>'plot' THEN RAISE EXCEPTION 'Rule/target mismatch.'; END IF;
            required_columns:=ARRAY['fsko','geom','zae','gmk','fln','gdz','beg'];
            produced_columns:=ARRAY['geom','parcel_number_numerator','cadastral_district_code','cadastral_field_number','district_id_official','source_date'];
            identity_sql:=$rule$(rtrim(fsko, '_'))::bigint$rule$;
            state_sql:=$rule$geom AS geom,zae AS parcel_number_numerator,gmk AS cadastral_district_code,fln AS cadastral_field_number,gdz AS district_id_official,beg::timestamp AS source_date$rule$;
            eligibility:='geom IS NOT NULL AND NOT public.ST_IsEmpty(geom) AND public.ST_SRID(geom)>0';
        WHEN 'berlin_building_v1' THEN
            expected_id_column:='uuid';
            IF m.target_entity<>'building' THEN RAISE EXCEPTION 'Rule/target mismatch.'; END IF;
            required_columns:=ARRAY['uuid','fid','geom','gfk','bezgfk','ofl','bezofl','aog','aug','hoh','bat','bezbat','nam','baw','bezbaw','zus','bezzus','lag','namlag','hnr','pnr','lnr','bezeich'];
            produced_columns:=ARRAY['source_fid','geom','building_function','building_function_description','position_relative_to_ground','position_relative_to_ground_description','storeys_above_ground','storeys_below_ground','highrise','building_component_type','building_component_type_description','name','building_configuration','building_configuration_description','building_condition','building_condition_description','street_code','street_name','house_number','pseudo_house_number','building_association_number','aaa_description'];
            identity_sql:=$rule$(uuid)::text$rule$;
            state_sql:=$rule$fid AS source_fid,geom AS geom,gfk AS building_function,bezgfk AS building_function_description,ofl AS position_relative_to_ground,bezofl AS position_relative_to_ground_description,aog AS storeys_above_ground,aug AS storeys_below_ground,nullif(btrim(hoh), '')::boolean AS highrise,bat AS building_component_type,bezbat AS building_component_type_description,nam AS name,baw AS building_configuration,bezbaw AS building_configuration_description,zus AS building_condition,bezzus AS building_condition_description,lag AS street_code,namlag AS street_name,hnr AS house_number,pnr AS pseudo_house_number,lnr AS building_association_number,bezeich AS aaa_description$rule$;
            eligibility:='geom IS NOT NULL AND NOT public.ST_IsEmpty(geom) AND public.ST_SRID(geom)>0';
        WHEN 'berlin_address_v1' THEN
            expected_id_column:='adr_ident';
            IF m.target_entity<>'address' THEN RAISE EXCEPTION 'Rule/target mismatch.'; END IF;
            required_columns:=ARRAY['adr_ident','geom','strnam','strnr','hausnr','hausnrz','postleit','blk','bez','bez_name','ot','ot_name','plr','plr_name','aufn_dt','str_typ'];
            produced_columns:=ARRAY['geom','street_name','street_id','house_number','house_number_suffix','pca_id','block_id_official','district_id_official','district_name','place_id','place_name','planning_area_no','planning_area_name','address_date','type'];
            identity_sql:=$rule$(adr_ident)::bigint$rule$;
            state_sql:=$rule$geom AS geom,strnam AS street_name,strnr AS street_id,hausnr AS house_number,hausnrz AS house_number_suffix,postleit AS pca_id,blk AS block_id_official,11000000 + bez::bigint AS district_id_official,bez_name AS district_name,ot AS place_id,ot_name AS place_name,plr AS planning_area_no,plr_name AS planning_area_name,aufn_dt::timestamp AS address_date,str_typ AS type$rule$;
            eligibility:='geom IS NOT NULL AND NOT public.ST_IsEmpty(geom) AND public.ST_SRID(geom)>0';
        ELSE RAISE EXCEPTION 'Unknown approved rule: %',m.rule_name;
        END CASE;
        IF NOT m.target_columns <@ produced_columns OR NOT required_columns <@ m.source_columns
           OR m.source_id_column<>expected_id_column THEN
            RAISE EXCEPTION 'Mapping columns do not satisfy the approved rule contract.';
        END IF;
    END IF;
    -- Current accepted inputs only; the latest import identifies the accepted state
    -- used now, while each source version retains its own creating import.
    RETURN format('SELECT (%s)::text AS entity_key,%s,s.row_id AS source_version_id,
        %s AS source_key FROM %s s WHERE %s AND (%s)
        AND EXISTS(SELECT FROM mirror.registry current_registration
          WHERE current_registration.source_name=%L AND current_registration.layer_name=%L
            AND NOT current_registration.retired
            AND (current_registration.utt_txn IS NULL OR upper_inf(current_registration.utt_txn)))',
        identity_sql,state_sql,key_sql,relation_sql,source_filter,eligibility,r.source_name,r.layer_name);
END;
$$;
COMMENT ON FUNCTION utt_pkg.curation_rule_query(bigint) IS 'Internal approved-rule dispatcher for mapping validation and curation. Returns a SELECT over exact current accepted source versions, without executing metadata as SQL. Berlin v1 rules retain named transformations and nullable descriptive values; direct v1 rules require every group member non-NULL; sum v1 rules aggregate numeric members by explicit source_id_column and retain all contributors. No file payload is decoded. Example: SELECT utt_pkg.curation_rule_query(1); Rules with changed behavior need a new durable name.';

-- One lock order for mapping edits, curation and relation generation. The statement
-- trigger obtains it before tuple locks, avoiding mapping-edit/curation deadlocks.
CREATE FUNCTION utt_pkg.curation_lock_mappings() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(70303,1);
    RETURN NULL;
END;
$$;
CREATE TRIGGER lock_mapping_changes BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE
ON utt.curation_mapping FOR EACH STATEMENT EXECUTE FUNCTION utt_pkg.curation_lock_mappings();
COMMENT ON FUNCTION utt_pkg.curation_lock_mappings() IS 'Statement trigger serializing mapping edits with curation/relation transactions before any mapping tuple changes. Returns NULL. Example firing it: UPDATE utt.curation_mapping SET active=false WHERE mapping_id=1;';

CREATE FUNCTION utt_pkg.curation_validate_mapping() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE
    r mirror.registry%ROWTYPE;
    source_relation regclass;
    contract_relation regclass;
    target_relation regclass;
    canonical_targets text[];
    partition_name text;
    partition_values text;
    partition_oid regclass;
    key_name text;
    query_sql text;
    projection text;
BEGIN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Mapping revisions are retained; deactivate instead.'; END IF;
    IF TG_OP='UPDATE' AND (to_jsonb(NEW)-'active') IS DISTINCT FROM (to_jsonb(OLD)-'active') THEN
        RAISE EXCEPTION 'Mapping definitions are immutable; insert another revision.';
    END IF;
    -- Retirement must remain possible after a source schema changes.
    IF TG_OP='UPDATE' AND NOT NEW.active THEN RETURN NEW; END IF;
    IF array_ndims(NEW.target_columns)<>1 OR array_ndims(NEW.source_columns)<>1
       OR cardinality(NEW.target_columns)=0 OR cardinality(NEW.source_columns)=0
       OR array_position(NEW.target_columns,NULL) IS NOT NULL OR array_position(NEW.source_columns,NULL) IS NOT NULL
       OR cardinality(NEW.target_columns)<>(SELECT count(DISTINCT x) FROM unnest(NEW.target_columns) x)
       OR cardinality(NEW.source_columns)<>(SELECT count(DISTINCT x) FROM unnest(NEW.source_columns) x) THEN
        RAISE EXCEPTION 'Mapping column arrays must be nonempty, one-dimensional and distinct, without NULLs.';
    END IF;
    IF TG_WHEN='BEFORE' THEN
        IF NEW.rule_name IN ('direct_'||NEW.target_entity||'_v1','sum_'||NEW.target_entity||'_v1') THEN
            SELECT array_agg(tc ORDER BY tc),array_agg(sc ORDER BY tc)
            INTO NEW.target_columns,NEW.source_columns FROM unnest(NEW.target_columns,NEW.source_columns) p(tc,sc);
        ELSE
            SELECT array_agg(x ORDER BY x) INTO NEW.target_columns FROM unnest(NEW.target_columns) x;
        END IF;
        RETURN NEW;
    END IF;
    SELECT array_agg(x ORDER BY x) INTO canonical_targets FROM unnest(NEW.target_columns) x;
    IF NEW.target_columns IS DISTINCT FROM canonical_targets THEN
        RAISE EXCEPTION 'Store target_columns in alphabetical order; pair direct source_columns in that same order.';
    END IF;
    IF NEW.active AND EXISTS(SELECT FROM utt.curation_mapping m
        WHERE m.active AND m.mapping_id<>NEW.mapping_id AND m.target_entity=NEW.target_entity
          AND m.target_columns && NEW.target_columns AND m.target_columns<>NEW.target_columns) THEN
        RAISE EXCEPTION 'Active groups must be identical or disjoint, never partially overlapping.';
    END IF;
    SELECT * INTO STRICT r FROM mirror.registry WHERE row_id=NEW.registry_row_id;
    source_relation:=CASE WHEN r.storage_mode='rows' THEN to_regclass(format('mirror.%I',r.stored_table)) ELSE 'mirror.registry'::regclass END;
    contract_relation:=CASE WHEN r.storage_mode='rows' THEN to_regclass(format('mirror.%I',r.table_base)) ELSE 'mirror.registry'::regclass END;
    target_relation:=to_regclass('utt.'||NEW.target_entity);
    IF source_relation IS NULL OR contract_relation IS NULL OR (r.storage_mode='external_file' AND r.utt_txn IS NULL) THEN RAISE EXCEPTION 'Accept source history before defining a mapping.'; END IF;
    key_name:=NEW.target_entity||'_id_official';
    IF NEW.source_columns && ARRAY['row_id','utt_txn','import_id','utt_key']
       OR NEW.source_id_column IN ('row_id','utt_txn','import_id','utt_key') THEN
        RAISE EXCEPTION 'UTT-generated source identity/time cannot be mapped as domain state or logical identity.';
    END IF;
    IF EXISTS(SELECT FROM unnest(NEW.source_columns || ARRAY[NEW.source_id_column]) c
        WHERE NOT EXISTS(SELECT FROM pg_attribute WHERE attrelid=contract_relation AND attname=c AND attnum>0 AND NOT attisdropped))
       OR EXISTS(SELECT FROM unnest(NEW.target_columns) c WHERE c IN ('row_id','utt_txn',key_name)
        OR NOT EXISTS(SELECT FROM pg_attribute WHERE attrelid=target_relation AND attname=c AND attnum>0 AND NOT attisdropped)) THEN
        RAISE EXCEPTION 'Unknown source/target columns, or generated identity/time selected as state.';
    END IF;
    query_sql:=utt_pkg.curation_rule_query(NEW.mapping_id);
    SELECT string_agg(format('q.%I::%s',c,format_type(a.atttypid,a.atttypmod)),',')
    INTO projection FROM unnest(NEW.target_columns) c JOIN pg_attribute a ON a.attrelid=target_relation AND a.attname=c;
    EXECUTE format('SELECT %s FROM (%s) q LIMIT 0',projection,query_sql);
    partition_name:='provenance_'||utt_pkg.mirror_object_base(r.source_name,r.layer_name);
    partition_oid:=to_regclass(format('utt.%I',partition_name));
    -- Native registry rows are versions of one source, so share its readable partition.
    SELECT string_agg(quote_literal(row_id),', ' ORDER BY row_id) INTO partition_values
    FROM mirror.registry WHERE source_name=r.source_name AND layer_name=r.layer_name
      AND (r.storage_mode='external_file' OR row_id=r.row_id);
    IF partition_oid IS NOT NULL THEN
        IF NOT EXISTS(SELECT FROM pg_inherits WHERE inhrelid=partition_oid
            AND inhparent='utt.curation_provenance'::regclass)
          OR EXISTS(SELECT FROM utt.curation_mapping m JOIN mirror.registry other ON other.row_id=m.registry_row_id
            WHERE utt_pkg.mirror_object_base(other.source_name,other.layer_name)=
                  utt_pkg.mirror_object_base(r.source_name,r.layer_name)
              AND (other.source_name,other.layer_name) IS DISTINCT FROM (r.source_name,r.layer_name)) THEN
            RAISE EXCEPTION 'Readable partition name % is already used; choose distinct source/layer names.',partition_name;
        END IF;
        IF (SELECT pg_get_expr(relpartbound,oid) FROM pg_class WHERE oid=partition_oid)
          IS DISTINCT FROM format('FOR VALUES IN (%s)',partition_values) THEN
            IF r.storage_mode<>'external_file' THEN
                RAISE EXCEPTION 'Partition % has an unexpected source registration bound.',partition_name;
            END IF;
            -- Mapping edits hold the shared advisory lock; no curation can write here.
            EXECUTE format('ALTER TABLE utt.curation_provenance DETACH PARTITION %s',partition_oid);
            EXECUTE format('ALTER TABLE utt.curation_provenance ATTACH PARTITION %s FOR VALUES IN (%s)',partition_oid,partition_values);
        END IF;
    ELSE
        EXECUTE format('CREATE TABLE utt.%I PARTITION OF utt.curation_provenance FOR VALUES IN (%s)',partition_name,partition_values);
        IF r.storage_mode='rows' THEN
            EXECUTE format('ALTER TABLE utt.%I ADD FOREIGN KEY(source_row_id) REFERENCES %s(row_id), ADD CHECK(source_file_row_id IS NULL)',partition_name,source_relation);
        ELSE
            EXECUTE format('ALTER TABLE utt.%I ADD CHECK(source_row_id IS NULL)',partition_name);
        END IF;
        EXECUTE format('CREATE TRIGGER protect_truncate BEFORE TRUNCATE ON utt.%I EXECUTE FUNCTION utt_pkg.curation_validate_provenance()',partition_name);
        EXECUTE format('REVOKE ALL ON utt.%I FROM PUBLIC,uttdb_pipeline,uttdb_app_writer',partition_name);
        EXECUTE format('GRANT SELECT ON utt.%I TO uttdb_reader,uttdb_developer,uttdb_pipeline,uttdb_app_reader,uttdb_app_writer',partition_name);
        EXECUTE format('GRANT ALL ON utt.%I TO uttdb_dba',partition_name);
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER normalize_mapping BEFORE INSERT OR UPDATE ON utt.curation_mapping
FOR EACH ROW EXECUTE FUNCTION utt_pkg.curation_validate_mapping();
CREATE TRIGGER validate_mapping AFTER INSERT OR UPDATE OR DELETE ON utt.curation_mapping
FOR EACH ROW EXECUTE FUNCTION utt_pkg.curation_validate_mapping();
COMMENT ON FUNCTION utt_pkg.curation_validate_mapping() IS 'DBA mapping-integrity trigger: retains immutable revisions, checks canonical atomic groups, catalog columns/types and approved SQL contracts; creates a provenance partition with a real source-history FK. Returns NEW. Example firing it: INSERT INTO utt.curation_mapping(registry_row_id,target_entity,target_columns,source_columns,source_id_column,rule_name) VALUES(1,''city'',ARRAY[''geom'',''name''],ARRAY[''geom'',''name''],''city_id'',''direct_city_v1'');';

CREATE FUNCTION utt_pkg.provenance_at(entity text,system_time timestamptz)
RETURNS SETOF utt.curation_provenance LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE projection text;
BEGIN
    IF entity IS NULL OR entity NOT IN ('city','district','block','plot','building','address') OR system_time IS NULL OR NOT isfinite(system_time) THEN
        RAISE EXCEPTION 'Supply a supported entity and finite system time.';
    END IF;
    SELECT string_agg(format('o.%I',attname),',' ORDER BY attnum) INTO projection
    FROM pg_attribute WHERE attrelid='utt.curation_provenance'::regclass AND attnum>0 AND NOT attisdropped;
    RETURN QUERY EXECUTE format('WITH observations AS MATERIALIZED (
        SELECT p.*,m.target_columns AS group_columns FROM utt.curation_provenance p
        JOIN utt.curation_mapping m USING(mapping_id)
        JOIN utt.%I t ON t.row_id=p.target_row_id
        WHERE p.target_table=$2 AND t.utt_txn @> $1 AND p.observed_at<=$1)
        SELECT %s FROM observations o WHERE NOT EXISTS(
            SELECT FROM observations newer WHERE newer.target_row_id=o.target_row_id
              AND newer.observed_at>o.observed_at AND newer.group_columns && o.group_columns)',
        entity,projection) USING system_time,to_regclass(format('utt.%I',entity));
END;
$$;
COMMENT ON FUNCTION utt_pkg.provenance_at(text,timestamptz) IS 'Reader as-of query returning the complete latest contributor set for each group of each target version current at the supplied system time. Newer overlapping replacement groups supersede earlier group boundaries without reinterpreting old observations. Uses immutable mapping definitions, ignoring present activation. Writes nothing. Example: SELECT * FROM utt_pkg.provenance_at(''building'',''2026-10-28 12:00+00'');';

CREATE FUNCTION utt_pkg.curation_protect_history() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
    IF TG_OP='TRUNCATE' THEN RAISE EXCEPTION 'Curated history cannot be truncated.'; END IF;
    IF TG_OP='DELETE' OR (to_jsonb(NEW)-'utt_txn') IS DISTINCT FROM (to_jsonb(OLD)-'utt_txn')
       OR NOT upper_inf(OLD.utt_txn) OR upper_inf(NEW.utt_txn)
       OR lower(OLD.utt_txn) IS DISTINCT FROM lower(NEW.utt_txn) THEN
        RAISE EXCEPTION 'Curated versions are immutable except for closing current system time.';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION utt_pkg.curation_protect_history() IS 'Integrity trigger on domain versions: permits only closure of a current system-time range, rejecting data rewrites, deletion and truncation. Returns NEW. Example firing it: UPDATE utt.city SET name=''replacement''; -- rejected; curate a replacement version instead.';

CREATE FUNCTION utt_pkg.curation_validate_provenance() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE
    m utt.curation_mapping%ROWTYPE;
    r mirror.registry%ROWTYPE;
    source_range tstzrange;
    source_key_value jsonb;
    accepted_at timestamptz;
    source_relation regclass;
    key_sql text;
    target_relation regclass;
    target_range tstzrange;
BEGIN
    IF TG_OP<>'INSERT' THEN RAISE EXCEPTION 'Provenance is append-only.'; END IF;
    SELECT * INTO STRICT m FROM utt.curation_mapping WHERE mapping_id=NEW.mapping_id;
    SELECT * INTO STRICT r FROM mirror.registry WHERE row_id=NEW.source_registry_row_id;
    target_relation:=to_regclass(format('utt.%I',m.target_entity));
    IF NEW.target_table IS DISTINCT FROM target_relation THEN
        RAISE EXCEPTION 'Mapping and target table disagree.';
    END IF;
    EXECUTE format('SELECT utt_txn FROM %s WHERE row_id=$1 FOR KEY SHARE',target_relation)
        INTO STRICT target_range USING NEW.target_row_id;
    IF NOT target_range @> NEW.observed_at THEN RAISE EXCEPTION 'Observation must lie inside its target version system time.'; END IF;
    SELECT i.accepted_at INTO STRICT accepted_at FROM mirror.import i JOIN mirror.registry ir ON ir.row_id=i.registry_row_id
    WHERE i.import_id=NEW.import_id AND i.status='accepted' AND ir.source_name=r.source_name AND ir.layer_name=r.layer_name;
    IF accepted_at>NEW.observed_at THEN RAISE EXCEPTION 'An observation cannot use a future import.'; END IF;
    IF r.storage_mode='rows' THEN
        source_relation:=to_regclass(format('mirror.%I',r.stored_table));
        SELECT 'jsonb_build_object('||string_agg(format('%L,s.%I',k,k),',' ORDER BY n)||')'
        INTO key_sql FROM unnest(r.stable_key) WITH ORDINALITY u(k,n);
        EXECUTE format('SELECT utt_txn,%s FROM %s s WHERE row_id=$1',key_sql,source_relation)
            INTO STRICT source_range,source_key_value USING NEW.source_row_id;
    ELSE
        SELECT utt_txn,jsonb_build_object('source_name',source_name,'layer_name',layer_name)
        INTO STRICT source_range,source_key_value FROM mirror.registry WHERE row_id=NEW.source_file_row_id
            AND source_name=r.source_name AND layer_name=r.layer_name AND storage_mode='external_file';
    END IF;
    IF NOT source_range @> accepted_at OR source_key_value IS DISTINCT FROM NEW.source_key THEN
        RAISE EXCEPTION 'Source version/key was not part of the recorded accepted input.';
    END IF;
    IF EXISTS(SELECT FROM utt.curation_provenance p JOIN utt.curation_mapping pm USING(mapping_id)
        WHERE p.target_table=NEW.target_table AND p.target_row_id=NEW.target_row_id AND p.observed_at=NEW.observed_at
          AND pm.target_columns && m.target_columns AND pm.target_columns<>m.target_columns) THEN
        RAISE EXCEPTION 'One observation cannot contain conflicting group boundaries.';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER validate_provenance BEFORE INSERT OR UPDATE OR DELETE ON utt.curation_provenance
FOR EACH ROW EXECUTE FUNCTION utt_pkg.curation_validate_provenance();
CREATE TRIGGER protect_provenance_truncate BEFORE TRUNCATE ON utt.curation_provenance
EXECUTE FUNCTION utt_pkg.curation_validate_provenance();
COMMENT ON FUNCTION utt_pkg.curation_validate_provenance() IS 'Curation integrity trigger: append-only provenance with matching target/mapping, exact accepted source version and named key, nonfuture import, valid observation time and consistent group boundaries. Target existence is checked with a row lock; immutable target history prevents deletion/truncation. Real source FKs also apply. Returns NEW. Example firing it: DELETE FROM utt.curation_provenance; -- rejected.';

DO $$DECLARE entity text; BEGIN
    FOREACH entity IN ARRAY ARRAY['city','district','block','plot','building','address'] LOOP
        EXECUTE format('CREATE TRIGGER protect_history BEFORE UPDATE OR DELETE ON utt.%I FOR EACH ROW EXECUTE FUNCTION utt_pkg.curation_protect_history()',entity);
        EXECUTE format('CREATE TRIGGER protect_truncate BEFORE TRUNCATE ON utt.%I EXECUTE FUNCTION utt_pkg.curation_protect_history()',entity);
    END LOOP;
END $$;

CREATE FUNCTION utt_pkg.curate_entity(entity text)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog SET TimeZone='UTC' AS $$
DECLARE
    mapping_entry utt.curation_mapping%ROWTYPE;
    r mirror.registry%ROWTYPE;
    attr record;
    grp record;
    state_columns text;
    state_from_target text;
    state_from_effective text;
    candidate_columns text;
    candidate_values text;
    projection text;
    assignment_sql text;
    key_name text;
    key_type text;
    query_sql text;
    input_import bigint;
    input_schema bigint;
    at_time timestamptz;
    inserted_count integer;
    temp_name text;
    invalid boolean;
BEGIN
    IF entity IS NULL OR entity NOT IN ('city','district','block','plot','building','address') THEN RAISE EXCEPTION 'Unsupported entity: %',entity; END IF;
    PERFORM pg_advisory_xact_lock(70303,1);
    -- Coarse, explicit publication boundary: wait for in-flight mirror writers,
    -- then stop registry FOR UPDATE/publication while all source inputs are read.
    -- Plain metadata readers remain allowed. No filesystem payload is read here.
    LOCK TABLE mirror.registry IN EXCLUSIVE MODE;
    key_name:=entity||'_id_official';
    key_type:=CASE WHEN entity='building' THEN 'text' ELSE 'bigint' END;
    SELECT string_agg(format('%I',attname),',' ORDER BY attnum),
           string_agg(format('t.%I',attname),',' ORDER BY attnum),
           string_agg(format('e.%I',attname),',' ORDER BY attnum)
    INTO state_columns,state_from_target,state_from_effective
    FROM pg_attribute WHERE attrelid=to_regclass('utt.'||entity) AND attnum>0 AND NOT attisdropped AND attname NOT IN ('row_id','utt_txn');
    FOREACH temp_name IN ARRAY ARRAY['utt_candidates','utt_chosen','utt_groups','utt_effective',
        'utt_previous','utt_origins','utt_observations'] LOOP
        IF to_regclass(format('pg_temp.%I',temp_name)) IS NOT NULL THEN
            EXECUTE format('DROP TABLE pg_temp.%I',temp_name);
        END IF;
    END LOOP;
    EXECUTE format('CREATE TEMP TABLE utt_candidates ON COMMIT DROP AS SELECT %s,
        NULL::text AS _entity_key,NULL::bigint AS _mapping_id,NULL::bigint AS _registry_id,
        NULL::text[] AS _group_columns,NULL::bigint AS _source_version_id,NULL::jsonb AS _source_key,
        NULL::bigint AS _input_import,NULL::integer AS _priority,NULL::text AS _bundle_key
        FROM utt.%I t WITH NO DATA',state_from_target,entity);
    FOR mapping_entry IN SELECT * FROM utt.curation_mapping WHERE target_entity=entity AND active ORDER BY registry_row_id,mapping_id LOOP
        SELECT * INTO STRICT r FROM mirror.registry WHERE row_id=mapping_entry.registry_row_id;
        SELECT i.import_id,i.structure_version INTO input_import,input_schema FROM mirror.import i JOIN mirror.registry ir ON ir.row_id=i.registry_row_id
        WHERE ir.source_name=r.source_name AND ir.layer_name=r.layer_name AND i.status='accepted'
        ORDER BY i.accepted_at DESC,i.import_id DESC LIMIT 1;
        IF input_import IS NULL THEN CONTINUE; END IF;
        IF r.storage_mode='rows' AND EXISTS(SELECT FROM unnest(mapping_entry.source_columns || ARRAY[mapping_entry.source_id_column]) c
            WHERE NOT EXISTS(SELECT FROM mirror.source_columns sr WHERE sr.registry_row_id=r.row_id
                AND sr.structure_version=input_schema AND sr.column_name=c)) THEN
            RAISE NOTICE 'Mapping % lacks columns in the accepted schema; using eligible alternatives or former state.',mapping_entry.mapping_id;
            CONTINUE;
        END IF;
        query_sql:=utt_pkg.curation_rule_query(mapping_entry.mapping_id);
        SELECT string_agg(format('%I',c),',' ORDER BY n),
               string_agg(format('q.%I::%s',c,format_type(a.atttypid,a.atttypmod)),',' ORDER BY n)
        INTO candidate_columns,candidate_values FROM unnest(mapping_entry.target_columns) WITH ORDINALITY u(c,n)
        JOIN pg_attribute a ON a.attrelid=to_regclass('utt.'||entity) AND a.attname=c;
        EXECUTE format('INSERT INTO pg_temp.utt_candidates(%I,%s,_entity_key,_mapping_id,_registry_id,
            _group_columns,_source_version_id,_source_key,_input_import,_priority,_bundle_key)
            SELECT q.entity_key::%s,%s,q.entity_key,$1,$2,$3,q.source_version_id,q.source_key,$4,$5,
                CASE WHEN $6 THEN ''aggregate'' ELSE q.source_key::text END FROM (%s) q
            WHERE q.entity_key IS NOT NULL AND btrim(q.entity_key)<>''''',key_name,candidate_columns,key_type,candidate_values,query_sql)
            USING mapping_entry.mapping_id,r.row_id,mapping_entry.target_columns,input_import,mapping_entry.priority,mapping_entry.rule_name LIKE 'sum_%';
    END LOOP;
    IF NOT EXISTS(SELECT FROM pg_temp.utt_candidates) THEN RETURN 0; END IF;
    CREATE TEMP TABLE utt_chosen ON COMMIT DROP AS
        SELECT ranked.* FROM (SELECT c.*,dense_rank() OVER(
            PARTITION BY _entity_key,_group_columns ORDER BY _priority,_mapping_id,_bundle_key) AS _rank
            FROM pg_temp.utt_candidates c) ranked WHERE _rank=1;
    CREATE INDEX ON utt_chosen(_entity_key);
    CREATE TEMP TABLE utt_groups ON COMMIT DROP AS
        SELECT DISTINCT ON (_entity_key,_group_columns) * FROM pg_temp.utt_chosen
        ORDER BY _entity_key,_group_columns,_source_key::text;
    CREATE INDEX ON utt_groups(_entity_key);
    EXECUTE format('CREATE TEMP TABLE utt_effective ON COMMIT DROP AS SELECT %s,k._entity_key,
        t.row_id AS _old_row_id,NULL::bigint AS _new_row_id,false AS _changed
        FROM (SELECT DISTINCT _entity_key FROM pg_temp.utt_chosen) k
        LEFT JOIN utt.%I t ON t.%I::text=k._entity_key AND upper_inf(t.utt_txn)',state_from_target,entity,key_name);
    EXECUTE format('UPDATE pg_temp.utt_effective SET %I=_entity_key::%s',key_name,key_type);
    FOR grp IN SELECT DISTINCT _group_columns FROM pg_temp.utt_groups LOOP
        SELECT string_agg(format('%I=g.%I',c,c),',') INTO assignment_sql FROM unnest(grp._group_columns) c;
        EXECUTE format('UPDATE pg_temp.utt_effective e SET %s FROM pg_temp.utt_groups g
            WHERE e._entity_key=g._entity_key AND g._group_columns=$1',assignment_sql) USING grp._group_columns;
    END LOOP;
    -- All managed state is compared; fields without selected replacements are retained.
    EXECUTE format('UPDATE pg_temp.utt_effective e SET _changed=true WHERE _old_row_id IS NULL
        OR EXISTS(SELECT FROM utt.%I t WHERE t.row_id=e._old_row_id
          AND to_jsonb(ROW(%s)) IS DISTINCT FROM to_jsonb(ROW(%s)))',entity,state_from_target,state_from_effective);
    -- Reject mixed coordinate references rather than silently reprojecting source meaning.
    FOR attr IN SELECT attname FROM pg_attribute WHERE attrelid=to_regclass('utt.'||entity)
        AND atttypid='public.geometry'::regtype AND attnum>0 AND NOT attisdropped LOOP
        EXECUTE format('SELECT count(DISTINCT public.ST_SRID(g))>1 FROM (
            SELECT %I AS g FROM utt.%I WHERE upper_inf(utt_txn)
            UNION ALL SELECT %I FROM pg_temp.utt_effective) x WHERE g IS NOT NULL',attr.attname,entity,attr.attname) INTO invalid;
        IF invalid THEN RAISE EXCEPTION 'Mixed CRS in %.%; use an explicitly approved transformation rule.',entity,attr.attname; END IF;
    END LOOP;
    SELECT greatest(clock_timestamp(),coalesce(max(observed_at)+interval '1 microsecond','-infinity'::timestamptz))
        INTO at_time FROM utt.curation_provenance;
    EXECUTE format('CREATE TEMP TABLE utt_previous ON COMMIT DROP AS
        SELECT p.*,m.target_columns AS _group_columns,t.%I::text AS _entity_key
        FROM utt_pkg.provenance_at($1,$2) p JOIN utt.curation_mapping m USING(mapping_id)
        JOIN utt.%I t ON t.row_id=p.target_row_id
        WHERE EXISTS(SELECT FROM pg_temp.utt_effective e WHERE e._old_row_id=t.row_id)',key_name,entity)
        USING entity,at_time;
    CREATE INDEX ON utt_previous(_entity_key,_group_columns);
    -- A boundary change must replace every affected old group completely. Otherwise
    -- preserving half an old atomic group would invent an origin for split content.
    IF EXISTS(SELECT FROM pg_temp.utt_previous p
        WHERE EXISTS(SELECT FROM pg_temp.utt_groups g WHERE g._entity_key=p._entity_key AND g._group_columns && p._group_columns)
          AND NOT p._group_columns <@ ARRAY(SELECT DISTINCT c FROM pg_temp.utt_groups g
              CROSS JOIN LATERAL unnest(g._group_columns) c WHERE g._entity_key=p._entity_key)) THEN
        RAISE EXCEPTION 'Group-boundary changes require complete replacement of every affected former group.';
    END IF;
    CREATE TEMP TABLE utt_origins ON COMMIT DROP AS
        SELECT c._entity_key,c._mapping_id,c._registry_id,c._group_columns,c._source_version_id,
            c._source_key,c._input_import,
            CASE WHEN EXISTS(SELECT FROM utt.curation_mapping m WHERE m.active AND m.target_entity=entity
                AND m.target_columns=c._group_columns AND (m.priority,m.mapping_id)<(c._priority,c._mapping_id))
                THEN 'fallback' ELSE 'preferred' END AS _reason
        FROM pg_temp.utt_chosen c
        UNION ALL
        SELECT p._entity_key,p.mapping_id,p.source_registry_row_id,p._group_columns,
            coalesce(p.source_row_id,p.source_file_row_id),p.source_key,p.import_id,'carried'
        FROM pg_temp.utt_previous p WHERE NOT EXISTS(SELECT FROM pg_temp.utt_groups g
            WHERE g._entity_key=p._entity_key AND g._group_columns && p._group_columns);
    CREATE INDEX ON utt_origins(_entity_key,_group_columns);
    CREATE TEMP TABLE utt_observations ON COMMIT DROP AS
        SELECT DISTINCT f._entity_key,f._group_columns FROM pg_temp.utt_origins f
        JOIN pg_temp.utt_effective e USING(_entity_key)
        WHERE e._changed OR EXISTS(
            (SELECT n._mapping_id,n._source_version_id,n._source_key FROM pg_temp.utt_origins n
                WHERE n._entity_key=f._entity_key AND n._group_columns=f._group_columns
             EXCEPT SELECT p.mapping_id,coalesce(p.source_row_id,p.source_file_row_id),p.source_key FROM pg_temp.utt_previous p
                WHERE p._entity_key=f._entity_key AND p._group_columns=f._group_columns)
            UNION ALL
            (SELECT p.mapping_id,coalesce(p.source_row_id,p.source_file_row_id),p.source_key FROM pg_temp.utt_previous p
                WHERE p._entity_key=f._entity_key AND p._group_columns=f._group_columns
             EXCEPT SELECT n._mapping_id,n._source_version_id,n._source_key FROM pg_temp.utt_origins n
                WHERE n._entity_key=f._entity_key AND n._group_columns=f._group_columns));
    EXECUTE format('UPDATE utt.%I t SET utt_txn=tstzrange(lower(t.utt_txn),$1,''[)'')
        FROM pg_temp.utt_effective e WHERE e._changed AND t.row_id=e._old_row_id',entity) USING at_time;
    EXECUTE format('WITH inserted AS (INSERT INTO utt.%I(%s,utt_txn)
        SELECT %s,tstzrange($1,NULL,''[)'') FROM pg_temp.utt_effective e WHERE e._changed
        RETURNING row_id,%I)
        UPDATE pg_temp.utt_effective e SET _new_row_id=i.row_id FROM inserted i WHERE i.%I::text=e._entity_key',
        entity,state_columns,state_from_effective,key_name,key_name) USING at_time;
    GET DIAGNOSTICS inserted_count=ROW_COUNT;
    UPDATE pg_temp.utt_effective SET _new_row_id=_old_row_id WHERE NOT _changed;
    EXECUTE format('INSERT INTO utt.curation_provenance(target_table,target_row_id,source_registry_row_id,mapping_id,
        source_row_id,source_file_row_id,source_key,import_id,observed_at,selection_reason)
        SELECT $2,e._new_row_id,f._registry_id,f._mapping_id,
            CASE WHEN r.storage_mode=''rows'' THEN f._source_version_id END,
            CASE WHEN r.storage_mode=''external_file'' THEN f._source_version_id END,
            f._source_key,f._input_import,$1,f._reason
        FROM pg_temp.utt_origins f JOIN pg_temp.utt_effective e USING(_entity_key)
        JOIN pg_temp.utt_observations o USING(_entity_key,_group_columns)
        JOIN mirror.registry r ON r.row_id=f._registry_id') USING at_time,to_regclass(format('utt.%I',entity));
    RETURN inserted_count;
END;
$$;
COMMENT ON FUNCTION utt_pkg.curate_entity(text) IS 'DBA/pipeline security-definer transaction boundary shared by six wrappers. Locks mapping/curation configuration and mirror publication, selects atomic groups by priority/mapping/key, retains groups with no eligible replacement, versions only changed complete typed state, and atomically appends complete provenance observations (including carried groups and selection-only changes). Approved sum rules retain all contributors. Returns inserted entity-version count. Source dates are ordinary state. No implicit retirement/clearing. Example: SELECT utt_pkg.curate_entity(''city''); Coarse publication locking favors explicit consistency over concurrent imports.';

CREATE FUNCTION utt_pkg.curate_city() RETURNS integer
LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS
' SELECT utt_pkg.curate_entity(''city''); ';
COMMENT ON FUNCTION utt_pkg.curate_city() IS 'DBA/pipeline curation of city using active immutable mappings, accepted source versions and the shared group/provenance boundary. Writes system-time versions only for changed managed state and retains existing content without replacements. Returns inserted version count. Example: SELECT utt_pkg.curate_city();';

CREATE FUNCTION utt_pkg.curate_district() RETURNS integer
LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS
' SELECT utt_pkg.curate_entity(''district''); ';
COMMENT ON FUNCTION utt_pkg.curate_district() IS 'DBA/pipeline curation of district using active immutable mappings, accepted source versions and the shared group/provenance boundary. Writes system-time versions only for changed managed state and retains existing content without replacements. Returns inserted version count. Example: SELECT utt_pkg.curate_district();';

CREATE FUNCTION utt_pkg.curate_block() RETURNS integer
LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS
' SELECT utt_pkg.curate_entity(''block''); ';
COMMENT ON FUNCTION utt_pkg.curate_block() IS 'DBA/pipeline curation of block using active immutable mappings, accepted source versions and the shared group/provenance boundary. Writes system-time versions only for changed managed state and retains existing content without replacements. Returns inserted version count. Example: SELECT utt_pkg.curate_block();';

CREATE FUNCTION utt_pkg.curate_plot() RETURNS integer
LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS
' SELECT utt_pkg.curate_entity(''plot''); ';
COMMENT ON FUNCTION utt_pkg.curate_plot() IS 'DBA/pipeline curation of plot using active immutable mappings, accepted source versions and the shared group/provenance boundary. Writes system-time versions only for changed managed state and retains existing content without replacements. Returns inserted version count. Example: SELECT utt_pkg.curate_plot();';

CREATE FUNCTION utt_pkg.curate_building() RETURNS integer
LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS
' SELECT utt_pkg.curate_entity(''building''); ';
COMMENT ON FUNCTION utt_pkg.curate_building() IS 'DBA/pipeline curation of building using active immutable mappings, accepted source versions and the shared group/provenance boundary. Writes system-time versions only for changed managed state and retains existing content without replacements. Returns inserted version count. Example: SELECT utt_pkg.curate_building();';

CREATE FUNCTION utt_pkg.curate_address() RETURNS integer
LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS
' SELECT utt_pkg.curate_entity(''address''); ';
COMMENT ON FUNCTION utt_pkg.curate_address() IS 'DBA/pipeline curation of address using active immutable mappings, accepted source versions and the shared group/provenance boundary. Writes system-time versions only for changed managed state and retains existing content without replacements. Returns inserted version count. Example: SELECT utt_pkg.curate_address();';
CREATE FUNCTION utt_pkg.curate_relation(relation_name text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  inserted_count integer;
BEGIN
  PERFORM pg_advisory_xact_lock(70303,1);
  CASE relation_name
    WHEN 'building_block' THEN
      LOCK TABLE utt.relation_bldg_block IN SHARE ROW EXCLUSIVE MODE;
      WITH candidates AS (
        SELECT b.row_id AS building_row_id, k.row_id AS block_row_id,
               round((public.ST_Area(public.ST_Intersection(b.geom, k.geom))
                 / public.ST_Area(b.geom))::numeric, 3) AS relative_intersection
        FROM utt.building b
        JOIN utt.block k ON public.ST_Intersects(b.geom, k.geom)
        WHERE b.utt_txn && k.utt_txn
          AND b.geom IS NOT NULL AND k.geom IS NOT NULL
          AND NOT public.ST_IsEmpty(b.geom) AND NOT public.ST_IsEmpty(k.geom)
          AND public.ST_Area(b.geom) > 0
      )
      INSERT INTO utt.relation_bldg_block (
        building_row_id, block_row_id, relative_intersection
      )
      SELECT building_row_id, block_row_id, relative_intersection
      FROM candidates
      WHERE relative_intersection > 0.02 AND relative_intersection <= 1
      ON CONFLICT DO NOTHING;

    WHEN 'building_plot' THEN
      LOCK TABLE utt.relation_bldg_plot IN SHARE ROW EXCLUSIVE MODE;
      WITH candidates AS (
        SELECT b.row_id AS building_row_id, p.row_id AS plot_row_id,
               round((public.ST_Area(public.ST_Intersection(b.geom, p.geom))
                 / public.ST_Area(b.geom))::numeric, 3) AS relative_intersection
        FROM utt.building b
        JOIN utt.plot p ON public.ST_Intersects(b.geom, p.geom)
        WHERE b.utt_txn && p.utt_txn
          AND b.geom IS NOT NULL AND p.geom IS NOT NULL
          AND NOT public.ST_IsEmpty(b.geom) AND NOT public.ST_IsEmpty(p.geom)
          AND public.ST_Area(b.geom) > 0
      )
      INSERT INTO utt.relation_bldg_plot (
        building_row_id, plot_row_id, relative_intersection
      )
      SELECT building_row_id, plot_row_id, relative_intersection
      FROM candidates
      WHERE relative_intersection > 0.02 AND relative_intersection <= 1
      ON CONFLICT DO NOTHING;

    WHEN 'plot_block' THEN
      LOCK TABLE utt.relation_plot_block IN SHARE ROW EXCLUSIVE MODE;
      WITH candidates AS (
        SELECT p.row_id AS plot_row_id, k.row_id AS block_row_id,
               round((public.ST_Area(public.ST_Intersection(p.geom, k.geom))
                 / public.ST_Area(p.geom))::numeric, 3) AS relative_intersection
        FROM utt.plot p
        JOIN utt.block k ON public.ST_Intersects(p.geom, k.geom)
        WHERE p.utt_txn && k.utt_txn
          AND p.geom IS NOT NULL AND k.geom IS NOT NULL
          AND NOT public.ST_IsEmpty(p.geom) AND NOT public.ST_IsEmpty(k.geom)
          AND public.ST_Area(p.geom) > 0
      )
      INSERT INTO utt.relation_plot_block (
        plot_row_id, block_row_id, relative_intersection
      )
      SELECT plot_row_id, block_row_id, relative_intersection
      FROM candidates
      WHERE relative_intersection > 0.02 AND relative_intersection <= 1
      ON CONFLICT DO NOTHING;

    ELSE
      RAISE EXCEPTION 'Unsupported relation %. Use building_block, building_plot or plot_block.',
        relation_name;
  END CASE;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$$;

REVOKE ALL ON FUNCTION utt_pkg.curate_relation(text)
  FROM PUBLIC, uttdb_reader, uttdb_developer, uttdb_pipeline, uttdb_app_reader, uttdb_app_writer;
GRANT EXECUTE ON FUNCTION utt_pkg.curate_relation(text) TO uttdb_dba, uttdb_pipeline;
COMMENT ON FUNCTION utt_pkg.curate_relation(text) IS
  'DBA/pipeline security-definer calculation of one supported spatial relation between all immutable UTT entity versions whose system-time ranges overlap. relation_name must be building_block, building_plot or plot_block. The stored fraction is intersection area divided by the first entity area (building or plot), rounded to three decimals; values at or below 0.02 are omitted. Existing pairs are left unchanged, so reruns insert only relations for newly curated or previously unprocessed historical versions. Relation rows reference endpoint row_id values and have no separate temporal ranges; their temporal context comes from those immutable versions. Returns the number of inserted pairs. Examples: SELECT utt_pkg.curate_relation(''building_block''); SELECT utt_pkg.curate_relation(''building_plot''); SELECT utt_pkg.curate_relation(''plot_block'');';

-- Readers use current views or parameterized as-of functions without duplicate storage.
CREATE FUNCTION utt_pkg.city_at(system_time timestamptz) RETURNS SETOF utt.city
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS
' SELECT * FROM utt.city WHERE utt_txn @> system_time; ';
COMMENT ON FUNCTION utt_pkg.city_at(timestamptz) IS 'Reader query of city versions known at the supplied system time; returns typed entity rows and writes nothing. Example: SELECT * FROM utt_pkg.city_at(''2026-10-28 12:00+00'');';
CREATE FUNCTION utt_pkg.district_at(system_time timestamptz) RETURNS SETOF utt.district
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS
' SELECT * FROM utt.district WHERE utt_txn @> system_time; ';
COMMENT ON FUNCTION utt_pkg.district_at(timestamptz) IS 'Reader query of district versions known at the supplied system time; returns typed entity rows and writes nothing. Example: SELECT * FROM utt_pkg.district_at(''2026-10-28 12:00+00'');';
CREATE FUNCTION utt_pkg.block_at(system_time timestamptz) RETURNS SETOF utt.block
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS
' SELECT * FROM utt.block WHERE utt_txn @> system_time; ';
COMMENT ON FUNCTION utt_pkg.block_at(timestamptz) IS 'Reader query of block versions known at the supplied system time; returns typed entity rows and writes nothing. Example: SELECT * FROM utt_pkg.block_at(''2026-10-28 12:00+00'');';
CREATE FUNCTION utt_pkg.plot_at(system_time timestamptz) RETURNS SETOF utt.plot
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS
' SELECT * FROM utt.plot WHERE utt_txn @> system_time; ';
COMMENT ON FUNCTION utt_pkg.plot_at(timestamptz) IS 'Reader query of plot versions known at the supplied system time; returns typed entity rows and writes nothing. Example: SELECT * FROM utt_pkg.plot_at(''2026-10-28 12:00+00'');';
CREATE FUNCTION utt_pkg.building_at(system_time timestamptz) RETURNS SETOF utt.building
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS
' SELECT * FROM utt.building WHERE utt_txn @> system_time; ';
COMMENT ON FUNCTION utt_pkg.building_at(timestamptz) IS 'Reader query of building versions known at the supplied system time; returns typed entity rows and writes nothing. Example: SELECT * FROM utt_pkg.building_at(''2026-10-28 12:00+00'');';
CREATE FUNCTION utt_pkg.address_at(system_time timestamptz) RETURNS SETOF utt.address
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS
' SELECT * FROM utt.address WHERE utt_txn @> system_time; ';
COMMENT ON FUNCTION utt_pkg.address_at(timestamptz) IS 'Reader query of address versions known at the supplied system time; returns typed entity rows and writes nothing. Example: SELECT * FROM utt_pkg.address_at(''2026-10-28 12:00+00'');';

DO $$DECLARE routine record; BEGIN
    FOR routine IN SELECT p.oid::regprocedure AS signature,p.proname FROM pg_proc p
        JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='utt_pkg' AND (p.proname LIKE 'curate\_%' ESCAPE '\'
          OR p.proname LIKE 'curation\_%' ESCAPE '\'
          OR p.proname IN ('city_at','district_at','block_at','plot_at','building_at','address_at','provenance_at'))
    LOOP
        EXECUTE format('REVOKE ALL ON ROUTINE %s FROM PUBLIC,uttdb_reader,uttdb_developer,uttdb_pipeline,uttdb_app_reader,uttdb_app_writer',routine.signature);
        EXECUTE format('GRANT EXECUTE ON ROUTINE %s TO uttdb_dba',routine.signature);
        IF routine.proname IN ('curate_entity','curate_city','curate_district','curate_block','curate_plot','curate_building','curate_address','curate_relation') THEN
            EXECUTE format('GRANT EXECUTE ON ROUTINE %s TO uttdb_pipeline',routine.signature);
        ELSIF routine.proname LIKE '%_at' THEN
            EXECUTE format('GRANT EXECUTE ON ROUTINE %s TO uttdb_reader,uttdb_developer,uttdb_pipeline,uttdb_app_reader,uttdb_app_writer',routine.signature);
        END IF;
    END LOOP;
END $$;

CREATE FUNCTION utt_pkg.relation_at(relation_name text,system_time timestamptz)
RETURNS TABLE(first_row_id bigint,second_row_id bigint,relative_intersection numeric)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
    CASE relation_name
    WHEN 'building_block' THEN RETURN QUERY SELECT r.building_row_id,r.block_row_id,r.relative_intersection
        FROM utt.relation_bldg_block r JOIN utt.building a ON a.row_id=r.building_row_id JOIN utt.block b ON b.row_id=r.block_row_id
        WHERE a.utt_txn @> system_time AND b.utt_txn @> system_time;
    WHEN 'building_plot' THEN RETURN QUERY SELECT r.building_row_id,r.plot_row_id,r.relative_intersection
        FROM utt.relation_bldg_plot r JOIN utt.building a ON a.row_id=r.building_row_id JOIN utt.plot b ON b.row_id=r.plot_row_id
        WHERE a.utt_txn @> system_time AND b.utt_txn @> system_time;
    WHEN 'plot_block' THEN RETURN QUERY SELECT r.plot_row_id,r.block_row_id,r.relative_intersection
        FROM utt.relation_plot_block r JOIN utt.plot a ON a.row_id=r.plot_row_id JOIN utt.block b ON b.row_id=r.block_row_id
        WHERE a.utt_txn @> system_time AND b.utt_txn @> system_time;
    ELSE RAISE EXCEPTION 'Unsupported relation: %',relation_name;
    END CASE;
END;
$$;
COMMENT ON FUNCTION utt_pkg.relation_at(text,timestamptz) IS 'Reader as-of query of stored spatial pairs whose two endpoint versions were current at system_time. Returns endpoint row IDs and fraction without storing another time axis. Populate/backfill pairs with curate_relation first. Example: SELECT * FROM utt_pkg.relation_at(''building_plot'',''2026-10-28 12:00+00'');';
REVOKE ALL ON FUNCTION utt_pkg.relation_at(text,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION utt_pkg.relation_at(text,timestamptz)
TO uttdb_dba,uttdb_reader,uttdb_developer,uttdb_pipeline,uttdb_app_reader,uttdb_app_writer;

CREATE FUNCTION utt_pkg.curation_validate_relation() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE first_range tstzrange; second_range tstzrange;
BEGIN
    IF TG_OP<>'INSERT' THEN RAISE EXCEPTION 'Derived version relations are append-only.'; END IF;
    EXECUTE format('SELECT utt_txn FROM utt.%I WHERE row_id=$1',TG_ARGV[0]) INTO STRICT first_range
        USING (to_jsonb(NEW)->>TG_ARGV[1])::bigint;
    EXECUTE format('SELECT utt_txn FROM utt.%I WHERE row_id=$1',TG_ARGV[2]) INTO STRICT second_range
        USING (to_jsonb(NEW)->>TG_ARGV[3])::bigint;
    IF NOT first_range && second_range THEN RAISE EXCEPTION 'Relation endpoints must coexist in system time.'; END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER validate_relation BEFORE INSERT OR UPDATE OR DELETE ON utt.relation_bldg_block FOR EACH ROW
EXECUTE FUNCTION utt_pkg.curation_validate_relation('building','building_row_id','block','block_row_id');
CREATE TRIGGER validate_relation BEFORE INSERT OR UPDATE OR DELETE ON utt.relation_bldg_plot FOR EACH ROW
EXECUTE FUNCTION utt_pkg.curation_validate_relation('building','building_row_id','plot','plot_row_id');
CREATE TRIGGER validate_relation BEFORE INSERT OR UPDATE OR DELETE ON utt.relation_plot_block FOR EACH ROW
EXECUTE FUNCTION utt_pkg.curation_validate_relation('plot','plot_row_id','block','block_row_id');
COMMENT ON FUNCTION utt_pkg.curation_validate_relation() IS 'Integrity trigger ensuring derived version pairs coexist in system time and cannot be rewritten/deleted. Returns NEW; endpoint FKs and fraction checks also apply. Example firing it: UPDATE utt.relation_bldg_block SET relative_intersection=1; -- rejected; use curate_relation to append new endpoint pairs.';
REVOKE ALL ON FUNCTION utt_pkg.curation_validate_relation() FROM PUBLIC,uttdb_pipeline,uttdb_app_writer;
GRANT EXECUTE ON FUNCTION utt_pkg.curation_validate_relation() TO uttdb_dba;

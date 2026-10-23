-- P139 V0.8 incremental migration. Do NOT reset existing tables.
-- Requires existing V0.7 01/02/90 SQL to have been installed.
BEGIN;

CREATE OR REPLACE FUNCTION public.p139_admin_list_profiles()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
 IF NOT public.p139_is_system_admin() THEN RAISE EXCEPTION 'system administrator required'; END IF;
 RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',p.id,'display_name',p.display_name,'photo_path',p.photo_path,
   'aliases',COALESCE((SELECT jsonb_agg(a.alias ORDER BY a.alias)
       FROM public."TblP139Alias" a WHERE a.person_id=p.id),'[]'::jsonb),
   'group_count',(SELECT count(*) FROM public."TblP139GroupPerson" gp
      WHERE gp.person_id=p.id AND gp.is_active)
 ) ORDER BY p.display_name) FROM public."TblP139Person" p WHERE p.is_active),'[]'::jsonb);
END;$$;

CREATE OR REPLACE FUNCTION public.p139_admin_list_groups()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
 IF NOT public.p139_is_system_admin() THEN RAISE EXCEPTION 'system administrator required'; END IF;
 RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id',o.id,'name',o.name) ORDER BY o.name)
 FROM public."TblP139Organization" o WHERE o.is_active),'[]'::jsonb);
END;$$;

CREATE OR REPLACE FUNCTION public.p139_admin_rename_group(p_org_id uuid,p_name text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
 IF NOT public.p139_is_system_admin() THEN RAISE EXCEPTION 'system administrator required'; END IF;
 IF length(btrim(coalesce(p_name,''))) NOT BETWEEN 1 AND 120 THEN RAISE EXCEPTION 'invalid group name'; END IF;
 UPDATE public."TblP139Organization" SET name=btrim(p_name) WHERE id=p_org_id AND is_active;
 IF NOT FOUND THEN RAISE EXCEPTION 'group not found'; END IF;
 RETURN jsonb_build_object('id',p_org_id,'name',btrim(p_name));
END;$$;

-- Shared person profile edit; does not alter group membership or priority.
CREATE OR REPLACE FUNCTION public.p139_admin_upsert_profile(
 p_person_id uuid,p_display_name text,p_aliases text[],p_photo_path text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_alias text;
BEGIN
 IF NOT public.p139_is_system_admin() THEN RAISE EXCEPTION 'system administrator required'; END IF;
 IF length(btrim(coalesce(p_display_name,''))) NOT BETWEEN 1 AND 120 THEN RAISE EXCEPTION 'invalid name'; END IF;
 IF p_photo_path IS NULL OR length(btrim(p_photo_path))=0 THEN RAISE EXCEPTION 'photo required'; END IF;
 IF p_photo_path !~ '^[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}\.jpg$' THEN RAISE EXCEPTION 'invalid photo path'; END IF;
 INSERT INTO public."TblP139Person"(id,display_name,photo_path,organization_id)
 VALUES(p_person_id,btrim(p_display_name),p_photo_path,NULL)
 ON CONFLICT(id) DO UPDATE SET display_name=excluded.display_name,photo_path=excluded.photo_path,updated_at=now();
 DELETE FROM public."TblP139Alias" WHERE person_id=p_person_id;
 FOREACH v_alias IN ARRAY coalesce(p_aliases,ARRAY[]::text[]) LOOP
   IF length(btrim(v_alias)) BETWEEN 1 AND 120 THEN
     INSERT INTO public."TblP139Alias"(person_id,alias) VALUES(p_person_id,btrim(v_alias)) ON CONFLICT DO NOTHING;
   END IF;
 END LOOP;
 RETURN jsonb_build_object('id',p_person_id);
END;$$;

REVOKE ALL ON FUNCTION public.p139_admin_list_profiles() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.p139_admin_list_groups() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.p139_admin_rename_group(uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.p139_admin_upsert_profile(uuid,text,text[],text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.p139_admin_list_profiles() TO authenticated;
GRANT EXECUTE ON FUNCTION public.p139_admin_list_groups() TO authenticated;
GRANT EXECUTE ON FUNCTION public.p139_admin_rename_group(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.p139_admin_upsert_profile(uuid,text,text[],text) TO authenticated;
COMMIT;

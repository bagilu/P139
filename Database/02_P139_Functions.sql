-- P139 RPCs. All functions are namespaced and use fixed search_path values.
-- SECURITY DEFINER is limited to these functions because browser roles receive no table privileges.

CREATE OR REPLACE FUNCTION public.p139_is_system_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1 FROM public."TblP139SystemAdmin" WHERE user_id=auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.p139_create_group(p_group_name text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_group_id uuid;
BEGIN
  IF NOT public.p139_is_system_admin() THEN RAISE EXCEPTION 'system administrator required'; END IF;
  IF length(btrim(COALESCE(p_group_name,''))) NOT BETWEEN 1 AND 120 THEN RAISE EXCEPTION 'invalid group name'; END IF;
  INSERT INTO public."TblP139Organization"(name) VALUES(btrim(p_group_name)) RETURNING id INTO v_group_id;
  INSERT INTO public."TblP139Membership"(organization_id,user_id,role,is_active)
  VALUES(v_group_id,auth.uid(),'admin',true);
  RETURN jsonb_build_object('group_id',v_group_id,'name',btrim(p_group_name));
END;
$$;

CREATE OR REPLACE FUNCTION public.p139_is_member(p_org_id uuid, p_admin_only boolean DEFAULT false)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT public.p139_is_system_admin() OR EXISTS (
    SELECT 1 FROM public."TblP139Membership" m
    JOIN public."TblP139Organization" o ON o.id=m.organization_id AND o.is_active
    WHERE m.organization_id=p_org_id AND m.user_id=auth.uid() AND m.is_active
      AND (NOT p_admin_only OR m.role='admin')
  );
$$;

CREATE OR REPLACE FUNCTION public.p139_can_access_storage(p_org_folder text, p_admin_only boolean DEFAULT false)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_org_id uuid;
BEGIN
  IF auth.uid() IS NULL OR p_org_folder !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' THEN
    RETURN false;
  END IF;
  v_org_id := p_org_folder::uuid;
  RETURN public.p139_is_member(v_org_id,p_admin_only);
END;
$$;

CREATE OR REPLACE FUNCTION public.p139_list_my_organizations()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',o.id,'name',o.name,'role',CASE WHEN public.p139_is_system_admin() THEN 'admin' ELSE m.role END) ORDER BY o.name),'[]'::jsonb)
  FROM public."TblP139Organization" o
  LEFT JOIN public."TblP139Membership" m ON m.organization_id=o.id AND m.user_id=auth.uid() AND m.is_active
  WHERE o.is_active AND (public.p139_is_system_admin() OR m.role='admin');
$$;

CREATE OR REPLACE FUNCTION public.p139_public_list_groups()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',o.id,'name',o.name) ORDER BY o.name),'[]'::jsonb)
  FROM public."TblP139Organization" o
  WHERE o.is_active AND EXISTS (SELECT 1 FROM public."TblP139Person" p WHERE p.organization_id=o.id AND p.is_active);
$$;

CREATE OR REPLACE FUNCTION public.p139_public_list_people(p_org_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('id',p.id,'display_name',p.display_name,'photo_path',p.photo_path,
      'recognition_priority',p.recognition_priority,'aliases',COALESCE(a.aliases,'[]'::jsonb)) ORDER BY p.display_name)
    FROM public."TblP139Person" p
    JOIN public."TblP139Organization" o ON o.id=p.organization_id AND o.is_active
    LEFT JOIN LATERAL (SELECT jsonb_agg(x.alias ORDER BY x.alias) AS aliases FROM public."TblP139Alias" x WHERE x.person_id=p.id) a ON true
    WHERE p.organization_id=p_org_id AND p.is_active
  ),'[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.p139_public_check_answer(p_person_id uuid,p_answer text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_org_id uuid; v_name text; v_correct boolean; v_confused text; v_answer text; v_normalized text;
BEGIN
  v_answer:=btrim(COALESCE(p_answer,''));
  IF length(v_answer)<1 OR length(v_answer)>160 THEN RAISE EXCEPTION 'invalid answer'; END IF;
  SELECT p.organization_id,p.display_name INTO v_org_id,v_name
  FROM public."TblP139Person" p JOIN public."TblP139Organization" o ON o.id=p.organization_id AND o.is_active
  WHERE p.id=p_person_id AND p.is_active;
  IF v_org_id IS NULL THEN RAISE EXCEPTION 'person not found'; END IF;
  v_normalized:=lower(regexp_replace(v_answer,'\s+','','g'));
  SELECT (lower(regexp_replace(v_name,'\s+','','g'))=v_normalized OR EXISTS(
    SELECT 1 FROM public."TblP139Alias" a WHERE a.person_id=p_person_id AND lower(regexp_replace(a.alias,'\s+','','g'))=v_normalized
  )) INTO v_correct;
  IF NOT v_correct THEN
    SELECT p.display_name INTO v_confused FROM public."TblP139Person" p
    WHERE p.organization_id=v_org_id AND p.is_active AND p.id<>p_person_id
      AND (lower(regexp_replace(p.display_name,'\s+','','g'))=v_normalized OR EXISTS(
        SELECT 1 FROM public."TblP139Alias" a WHERE a.person_id=p.id AND lower(regexp_replace(a.alias,'\s+','','g'))=v_normalized
      )) LIMIT 1;
  END IF;
  RETURN jsonb_build_object('is_correct',v_correct,'correct_name',v_name,'confused_with',v_confused);
END;
$$;

CREATE OR REPLACE FUNCTION public.p139_list_people_for_priority(p_org_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT public.p139_is_member(p_org_id,false) THEN RAISE EXCEPTION 'not authorized'; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('id',p.id,'display_name',p.display_name,'photo_path',p.photo_path,'priority',u.priority) ORDER BY p.display_name)
    FROM public."TblP139Person" p
    LEFT JOIN public."TblP139UserPriority" u ON u.person_id=p.id AND u.user_id=auth.uid()
    WHERE p.organization_id=p_org_id AND p.is_active
  ),'[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.p139_set_my_priority(p_person_id uuid, p_priority smallint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_org_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'authentication required'; END IF;
  SELECT organization_id INTO v_org_id FROM public."TblP139Person" WHERE id=p_person_id AND is_active;
  IF v_org_id IS NULL OR NOT public.p139_is_member(v_org_id,false) THEN RAISE EXCEPTION 'not authorized'; END IF;
  IF p_priority IS NULL THEN
    DELETE FROM public."TblP139UserPriority" WHERE user_id=auth.uid() AND person_id=p_person_id;
  ELSE
    IF p_priority NOT BETWEEN 1 AND 3 THEN RAISE EXCEPTION 'invalid priority'; END IF;
    INSERT INTO public."TblP139UserPriority"(user_id,person_id,priority,updated_at)
    VALUES(auth.uid(),p_person_id,p_priority,now())
    ON CONFLICT(user_id,person_id) DO UPDATE SET priority=EXCLUDED.priority,updated_at=now();
  END IF;
  RETURN jsonb_build_object('ok',true);
END;
$$;

CREATE OR REPLACE FUNCTION public.p139_get_quiz_cycle(p_org_id uuid,p_priority smallint,p_exclude_person_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_result jsonb;
BEGIN
  IF NOT public.p139_is_member(p_org_id,false) THEN RAISE EXCEPTION 'not authorized'; END IF;
  IF p_priority NOT BETWEEN 1 AND 3 THEN RAISE EXCEPTION 'invalid priority'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('person_id',q.id,'photo_path',q.photo_path) ORDER BY (q.id=p_exclude_person_id),random()),'[]'::jsonb)
  INTO v_result
  FROM (
    SELECT p.id,p.photo_path FROM public."TblP139Person" p
    JOIN public."TblP139UserPriority" u ON u.person_id=p.id AND u.user_id=auth.uid() AND u.priority=p_priority
    WHERE p.organization_id=p_org_id AND p.is_active
  ) q;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.p139_submit_answer(p_person_id uuid,p_answer text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_org_id uuid; v_name text; v_correct boolean; v_confused text; v_confused_id uuid;
  v_normalized text; v_previous jsonb; v_answer text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'authentication required'; END IF;
  v_answer := btrim(COALESCE(p_answer,''));
  IF length(v_answer)<1 OR length(v_answer)>160 THEN RAISE EXCEPTION 'invalid answer'; END IF;
  SELECT organization_id,display_name INTO v_org_id,v_name FROM public."TblP139Person" WHERE id=p_person_id AND is_active;
  IF v_org_id IS NULL OR NOT public.p139_is_member(v_org_id,false) THEN RAISE EXCEPTION 'not authorized'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public."TblP139UserPriority" WHERE user_id=auth.uid() AND person_id=p_person_id) THEN RAISE EXCEPTION 'person is not in your learning plan'; END IF;
  v_normalized := lower(regexp_replace(v_answer,'\s+','','g'));
  SELECT (lower(regexp_replace(v_name,'\s+','','g'))=v_normalized OR EXISTS(
    SELECT 1 FROM public."TblP139Alias" a WHERE a.person_id=p_person_id AND lower(regexp_replace(a.alias,'\s+','','g'))=v_normalized
  )) INTO v_correct;
  IF NOT v_correct THEN
    SELECT p.id,p.display_name INTO v_confused_id,v_confused
    FROM public."TblP139Person" p
    WHERE p.organization_id=v_org_id AND p.is_active AND p.id<>p_person_id
      AND (lower(regexp_replace(p.display_name,'\s+','','g'))=v_normalized OR EXISTS(
        SELECT 1 FROM public."TblP139Alias" a WHERE a.person_id=p.id AND lower(regexp_replace(a.alias,'\s+','','g'))=v_normalized
      )) LIMIT 1;
  END IF;
  SELECT COALESCE(jsonb_agg(x.submitted_answer ORDER BY x.created_at DESC),'[]'::jsonb) INTO v_previous
  FROM (
    SELECT submitted_answer,created_at FROM public."TblP139AnswerEvent"
    WHERE user_id=auth.uid() AND person_id=p_person_id AND NOT is_correct
    ORDER BY created_at DESC LIMIT 3
  ) x;
  INSERT INTO public."TblP139AnswerEvent"(user_id,person_id,submitted_answer,is_correct,confused_with_person_id)
  VALUES(auth.uid(),p_person_id,v_answer,v_correct,v_confused_id);
  RETURN jsonb_build_object('is_correct',v_correct,'correct_name',v_name,'confused_with',v_confused,'previous_wrong_answers',v_previous);
END;
$$;

CREATE OR REPLACE FUNCTION public.p139_list_people_for_admin(p_org_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT public.p139_is_member(p_org_id,true) THEN RAISE EXCEPTION 'not authorized'; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('id',p.id,'display_name',p.display_name,'photo_path',p.photo_path,'recognition_priority',p.recognition_priority,'is_active',p.is_active,'aliases',COALESCE(a.aliases,'[]'::jsonb)) ORDER BY p.display_name)
    FROM public."TblP139Person" p
    LEFT JOIN LATERAL (SELECT jsonb_agg(x.alias ORDER BY x.alias) AS aliases FROM public."TblP139Alias" x WHERE x.person_id=p.id) a ON true
    WHERE p.organization_id=p_org_id
  ),'[]'::jsonb);
END;
$$;

DROP FUNCTION IF EXISTS public.p139_save_person(uuid,uuid,text,jsonb,text);
CREATE OR REPLACE FUNCTION public.p139_save_person(p_org_id uuid,p_person_id uuid,p_display_name text,p_aliases jsonb,p_photo_path text,p_recognition_priority smallint DEFAULT 2)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_alias text; v_norm text; v_id uuid;
BEGIN
  IF NOT public.p139_is_member(p_org_id,true) THEN RAISE EXCEPTION 'not authorized'; END IF;
  IF p_person_id IS NULL OR length(btrim(COALESCE(p_display_name,''))) NOT BETWEEN 1 AND 120 OR p_recognition_priority NOT BETWEEN 1 AND 3 THEN RAISE EXCEPTION 'invalid person data'; END IF;
  IF p_photo_path <> p_org_id::text||'/'||p_person_id::text||'.jpg' THEN RAISE EXCEPTION 'invalid photo path'; END IF;
  IF jsonb_typeof(COALESCE(p_aliases,'[]'::jsonb))<>'array' THEN RAISE EXCEPTION 'aliases must be a list'; END IF;
  v_norm := lower(regexp_replace(btrim(p_display_name),'\s+','','g'));
  IF EXISTS(
    SELECT 1 FROM public."TblP139Person" p WHERE p.organization_id=p_org_id AND p.id<>p_person_id
    AND lower(regexp_replace(p.display_name,'\s+','','g'))=v_norm
  ) OR EXISTS(
    SELECT 1 FROM public."TblP139Alias" a JOIN public."TblP139Person" p ON p.id=a.person_id
    WHERE p.organization_id=p_org_id AND p.id<>p_person_id AND lower(regexp_replace(a.alias,'\s+','','g'))=v_norm
  ) THEN RAISE EXCEPTION 'duplicate name or alias'; END IF;
  INSERT INTO public."TblP139Person"(id,organization_id,display_name,photo_path,recognition_priority,is_active,updated_at)
  VALUES(p_person_id,p_org_id,btrim(p_display_name),p_photo_path,p_recognition_priority,true,now())
  ON CONFLICT(id) DO UPDATE SET display_name=EXCLUDED.display_name,photo_path=EXCLUDED.photo_path,recognition_priority=EXCLUDED.recognition_priority,is_active=true,updated_at=now()
  WHERE public."TblP139Person".organization_id=p_org_id
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN RAISE EXCEPTION 'person belongs to another organization'; END IF;
  DELETE FROM public."TblP139Alias" WHERE person_id=p_person_id;
  FOR v_alias IN SELECT btrim(t.alias_value) FROM jsonb_array_elements_text(COALESCE(p_aliases,'[]'::jsonb)) AS t(alias_value) LOOP
    IF v_alias<>'' THEN
      v_norm := lower(regexp_replace(v_alias,'\s+','','g'));
      IF lower(regexp_replace(btrim(p_display_name),'\s+','','g'))=v_norm THEN CONTINUE; END IF;
      IF EXISTS(SELECT 1 FROM public."TblP139Person" p WHERE p.organization_id=p_org_id AND p.id<>p_person_id AND lower(regexp_replace(p.display_name,'\s+','','g'))=v_norm)
       OR EXISTS(SELECT 1 FROM public."TblP139Alias" a JOIN public."TblP139Person" p ON p.id=a.person_id WHERE p.organization_id=p_org_id AND p.id<>p_person_id AND lower(regexp_replace(a.alias,'\s+','','g'))=v_norm)
      THEN RAISE EXCEPTION 'alias conflicts with another person'; END IF;
      INSERT INTO public."TblP139Alias"(person_id,alias) VALUES(p_person_id,v_alias) ON CONFLICT(person_id,alias) DO NOTHING;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('ok',true,'person_id',p_person_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.p139_set_person_active(p_person_id uuid,p_is_active boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_org_id uuid;
BEGIN
  SELECT organization_id INTO v_org_id FROM public."TblP139Person" WHERE id=p_person_id;
  IF v_org_id IS NULL OR NOT public.p139_is_member(v_org_id,true) THEN RAISE EXCEPTION 'not authorized'; END IF;
  UPDATE public."TblP139Person" SET is_active=p_is_active,updated_at=now() WHERE id=p_person_id;
  RETURN jsonb_build_object('ok',true);
END;
$$;

CREATE OR REPLACE FUNCTION public.p139_add_member(p_org_id uuid,p_email text,p_role text DEFAULT 'participant')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_user_id uuid;
BEGIN
  IF NOT public.p139_is_member(p_org_id,true) THEN RAISE EXCEPTION 'not authorized'; END IF;
  IF p_role NOT IN ('admin','participant') THEN RAISE EXCEPTION 'invalid role'; END IF;
  SELECT id INTO v_user_id FROM auth.users WHERE lower(email)=lower(btrim(p_email)) LIMIT 1;
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'account not found'; END IF;
  INSERT INTO public."TblP139Membership"(organization_id,user_id,role,is_active)
  VALUES(p_org_id,v_user_id,p_role,true)
  ON CONFLICT(organization_id,user_id) DO UPDATE SET role=EXCLUDED.role,is_active=true;
  RETURN jsonb_build_object('ok',true);
END;
$$;

-- One-time initial setup, callable by a database owner from Supabase SQL Editor only.
CREATE OR REPLACE FUNCTION public.p139_bootstrap_organization(p_org_name text,p_admin_email text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_user_id uuid; v_org_id uuid; v_existing_org uuid;
BEGIN
  IF auth.uid() IS NOT NULL THEN RAISE EXCEPTION 'bootstrap is for SQL Editor setup only'; END IF;
  IF length(btrim(COALESCE(p_org_name,''))) NOT BETWEEN 1 AND 120 OR position('@' in COALESCE(p_admin_email,''))<2 THEN RAISE EXCEPTION 'invalid setup values'; END IF;
  SELECT id INTO v_user_id FROM auth.users WHERE lower(email)=lower(btrim(p_admin_email)) LIMIT 1;
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'admin account not found; register through P130 first'; END IF;
  IF EXISTS (SELECT 1 FROM public."TblP139SystemAdmin") THEN RAISE EXCEPTION 'bootstrap already completed'; END IF;
  SELECT organization_id INTO v_existing_org FROM public."TblP139Membership"
  WHERE user_id=v_user_id AND role='admin' AND is_active LIMIT 1;
  IF v_existing_org IS NOT NULL THEN
    INSERT INTO public."TblP139SystemAdmin"(user_id) VALUES(v_user_id);
    RETURN jsonb_build_object('organization_id',v_existing_org,'admin_email',lower(btrim(p_admin_email)),'upgraded_existing_admin',true);
  END IF;
  IF EXISTS (SELECT 1 FROM public."TblP139Organization") THEN RAISE EXCEPTION 'P139 groups already exist; an existing group administrator must run bootstrap'; END IF;
  INSERT INTO public."TblP139Organization"(name) VALUES(btrim(p_org_name)) RETURNING id INTO v_org_id;
  INSERT INTO public."TblP139Membership"(organization_id,user_id,role,is_active) VALUES(v_org_id,v_user_id,'admin',true);
  INSERT INTO public."TblP139SystemAdmin"(user_id) VALUES(v_user_id);
  RETURN jsonb_build_object('organization_id',v_org_id,'admin_email',lower(btrim(p_admin_email)));
END;
$$;

-- V0.5 multi-group profile model: one person/photo can be linked to several groups.
CREATE OR REPLACE FUNCTION public.p139_public_list_groups()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',o.id,'name',o.name) ORDER BY o.name),'[]'::jsonb)
  FROM public."TblP139Organization" o
  WHERE o.is_active AND EXISTS (
    SELECT 1 FROM public."TblP139GroupPerson" gp JOIN public."TblP139Person" p ON p.id=gp.person_id
    WHERE gp.organization_id=o.id AND gp.is_active
  );
$$;

CREATE OR REPLACE FUNCTION public.p139_public_list_people(p_org_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
BEGIN
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('id',p.id,'display_name',p.display_name,'photo_path',p.photo_path,
      'recognition_priority',gp.recognition_priority,'aliases',COALESCE(a.aliases,'[]'::jsonb)) ORDER BY p.display_name)
    FROM public."TblP139GroupPerson" gp
    JOIN public."TblP139Person" p ON p.id=gp.person_id
    JOIN public."TblP139Organization" o ON o.id=gp.organization_id AND o.is_active
    LEFT JOIN LATERAL (SELECT jsonb_agg(x.alias ORDER BY x.alias) AS aliases FROM public."TblP139Alias" x WHERE x.person_id=p.id) a ON true
    WHERE gp.organization_id=p_org_id AND gp.is_active
  ),'[]'::jsonb);
END;
$$;

DROP FUNCTION IF EXISTS public.p139_public_check_answer(uuid,text);
CREATE OR REPLACE FUNCTION public.p139_public_check_answer(p_org_id uuid,p_person_id uuid,p_answer text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE v_name text; v_correct boolean; v_confused text; v_answer text; v_normalized text;
BEGIN
  v_answer:=btrim(COALESCE(p_answer,''));
  IF length(v_answer)<1 OR length(v_answer)>160 THEN RAISE EXCEPTION 'invalid answer'; END IF;
  SELECT p.display_name INTO v_name
  FROM public."TblP139GroupPerson" gp JOIN public."TblP139Person" p ON p.id=gp.person_id
  JOIN public."TblP139Organization" o ON o.id=gp.organization_id AND o.is_active
  WHERE gp.organization_id=p_org_id AND gp.person_id=p_person_id AND gp.is_active;
  IF v_name IS NULL THEN RAISE EXCEPTION 'person not found in group'; END IF;
  v_normalized:=lower(regexp_replace(v_answer,'\s+','','g'));
  SELECT (lower(regexp_replace(v_name,'\s+','','g'))=v_normalized OR EXISTS(
    SELECT 1 FROM public."TblP139Alias" a WHERE a.person_id=p_person_id AND lower(regexp_replace(a.alias,'\s+','','g'))=v_normalized
  )) INTO v_correct;
  IF NOT v_correct THEN
    SELECT p.display_name INTO v_confused FROM public."TblP139GroupPerson" gp
    JOIN public."TblP139Person" p ON p.id=gp.person_id
    WHERE gp.organization_id=p_org_id AND gp.is_active AND p.id<>p_person_id
      AND (lower(regexp_replace(p.display_name,'\s+','','g'))=v_normalized OR EXISTS(
        SELECT 1 FROM public."TblP139Alias" a WHERE a.person_id=p.id AND lower(regexp_replace(a.alias,'\s+','','g'))=v_normalized
      )) LIMIT 1;
  END IF;
  RETURN jsonb_build_object('is_correct',v_correct,'correct_name',v_name,'confused_with',v_confused);
END;
$$;

CREATE OR REPLACE FUNCTION public.p139_list_people_for_admin(p_org_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT public.p139_is_member(p_org_id,true) THEN RAISE EXCEPTION 'not authorized'; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('id',p.id,'display_name',p.display_name,'photo_path',p.photo_path,
      'recognition_priority',gp.recognition_priority,'is_active',gp.is_active,'aliases',COALESCE(a.aliases,'[]'::jsonb)) ORDER BY p.display_name)
    FROM public."TblP139GroupPerson" gp JOIN public."TblP139Person" p ON p.id=gp.person_id
    LEFT JOIN LATERAL (SELECT jsonb_agg(x.alias ORDER BY x.alias) AS aliases FROM public."TblP139Alias" x WHERE x.person_id=p.id) a ON true
    WHERE gp.organization_id=p_org_id
  ),'[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.p139_list_available_people(p_org_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT public.p139_is_system_admin() OR NOT EXISTS(SELECT 1 FROM public."TblP139Organization" WHERE id=p_org_id AND is_active) THEN RAISE EXCEPTION 'system administrator required'; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('id',p.id,'display_name',p.display_name,'photo_path',p.photo_path,'source_group',COALESCE(o.name,'尚未加入群組')) ORDER BY p.display_name)
    FROM public."TblP139Person" p LEFT JOIN public."TblP139Organization" o ON o.id=p.organization_id
    WHERE NOT EXISTS(SELECT 1 FROM public."TblP139GroupPerson" gp WHERE gp.organization_id=p_org_id AND gp.person_id=p.id AND gp.is_active)
  ),'[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.p139_create_person_profile(p_person_id uuid,p_display_name text,p_aliases jsonb,p_photo_path text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE v_alias text;
BEGIN
  IF NOT public.p139_is_system_admin() THEN RAISE EXCEPTION 'system administrator required'; END IF;
  IF p_person_id IS NULL OR length(btrim(COALESCE(p_display_name,''))) NOT BETWEEN 1 AND 120 THEN RAISE EXCEPTION 'invalid person data'; END IF;
  IF p_photo_path<>p_person_id::text||'/'||p_person_id::text||'.jpg' THEN RAISE EXCEPTION 'invalid photo path'; END IF;
  IF jsonb_typeof(COALESCE(p_aliases,'[]'::jsonb))<>'array' THEN RAISE EXCEPTION 'aliases must be a list'; END IF;
  INSERT INTO public."TblP139Person"(id,organization_id,display_name,photo_path,recognition_priority,is_active,updated_at)
  VALUES(p_person_id,NULL,btrim(p_display_name),p_photo_path,2,true,now());
  FOR v_alias IN SELECT btrim(value) FROM jsonb_array_elements_text(COALESCE(p_aliases,'[]'::jsonb)) AS t(value) LOOP
    IF v_alias<>'' AND lower(regexp_replace(v_alias,'\s+','','g'))<>lower(regexp_replace(btrim(p_display_name),'\s+','','g')) THEN
      INSERT INTO public."TblP139Alias"(person_id,alias) VALUES(p_person_id,v_alias) ON CONFLICT(person_id,alias) DO NOTHING;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('ok',true,'person_id',p_person_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.p139_add_person_to_group(p_org_id uuid,p_person_id uuid,p_recognition_priority smallint DEFAULT 2)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT public.p139_is_system_admin() THEN RAISE EXCEPTION 'system administrator required'; END IF;
  IF p_recognition_priority NOT BETWEEN 1 AND 3 OR NOT EXISTS(SELECT 1 FROM public."TblP139Person" WHERE id=p_person_id)
    OR NOT EXISTS(SELECT 1 FROM public."TblP139Organization" WHERE id=p_org_id AND is_active) THEN RAISE EXCEPTION 'invalid group or person'; END IF;
  IF EXISTS(SELECT 1 FROM public."TblP139GroupPerson" gp JOIN public."TblP139Person" p ON p.id=gp.person_id
    WHERE gp.organization_id=p_org_id AND gp.is_active AND lower(regexp_replace(p.display_name,'\s+','','g'))=
      (SELECT lower(regexp_replace(display_name,'\s+','','g')) FROM public."TblP139Person" WHERE id=p_person_id) AND gp.person_id<>p_person_id) THEN
    RAISE EXCEPTION 'duplicate name in group';
  END IF;
  INSERT INTO public."TblP139GroupPerson"(organization_id,person_id,recognition_priority,is_active)
  VALUES(p_org_id,p_person_id,p_recognition_priority,true)
  ON CONFLICT(organization_id,person_id) DO UPDATE SET recognition_priority=EXCLUDED.recognition_priority,is_active=true;
  RETURN jsonb_build_object('ok',true,'person_id',p_person_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.p139_remove_person_from_group(p_org_id uuid,p_person_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT public.p139_is_member(p_org_id,true) THEN RAISE EXCEPTION 'not authorized'; END IF;
  UPDATE public."TblP139GroupPerson" SET is_active=false WHERE organization_id=p_org_id AND person_id=p_person_id;
  RETURN jsonb_build_object('ok',true);
END;
$$;

DROP FUNCTION IF EXISTS public.p139_set_person_active(uuid,boolean);
CREATE OR REPLACE FUNCTION public.p139_set_person_active(p_org_id uuid,p_person_id uuid,p_is_active boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT public.p139_is_member(p_org_id,true) THEN RAISE EXCEPTION 'not authorized'; END IF;
  UPDATE public."TblP139GroupPerson" SET is_active=p_is_active WHERE organization_id=p_org_id AND person_id=p_person_id;
  RETURN jsonb_build_object('ok',true);
END;
$$;

DROP FUNCTION IF EXISTS public.p139_save_person(uuid,uuid,text,jsonb,text,smallint);
CREATE FUNCTION public.p139_save_person(p_org_id uuid,p_person_id uuid,p_display_name text,p_aliases jsonb,p_photo_path text,p_recognition_priority smallint DEFAULT 2)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE v_alias text; v_norm text; v_primary_org uuid; v_primary_photo text;
BEGIN
  IF NOT public.p139_is_member(p_org_id,true) THEN RAISE EXCEPTION 'not authorized'; END IF;
  IF p_person_id IS NULL OR length(btrim(COALESCE(p_display_name,''))) NOT BETWEEN 1 AND 120 OR p_recognition_priority NOT BETWEEN 1 AND 3 THEN RAISE EXCEPTION 'invalid person data'; END IF;
  IF jsonb_typeof(COALESCE(p_aliases,'[]'::jsonb))<>'array' THEN RAISE EXCEPTION 'aliases must be a list'; END IF;
  IF EXISTS(
    SELECT 1 FROM public."TblP139GroupPerson" gp JOIN public."TblP139Person" p ON p.id=gp.person_id
    WHERE gp.organization_id=p_org_id AND gp.is_active AND p.id<>p_person_id
      AND lower(regexp_replace(p.display_name,'\s+','','g'))=lower(regexp_replace(btrim(p_display_name),'\s+','','g'))
  ) THEN RAISE EXCEPTION 'duplicate name in group'; END IF;
  SELECT organization_id,photo_path INTO v_primary_org,v_primary_photo FROM public."TblP139Person" WHERE id=p_person_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'person profile not found; create it in the person directory first';
  ELSIF v_primary_org IS NULL THEN
    IF NOT public.p139_is_system_admin() THEN RAISE EXCEPTION 'system administrator required to edit a shared profile'; END IF;
    IF p_photo_path<>p_person_id::text||'/'||p_person_id::text||'.jpg' THEN RAISE EXCEPTION 'invalid photo path'; END IF;
    UPDATE public."TblP139Person" SET display_name=btrim(p_display_name),photo_path=p_photo_path,is_active=true,updated_at=now() WHERE id=p_person_id;
  ELSE
    IF p_photo_path<>v_primary_org::text||'/'||p_person_id::text||'.jpg' THEN RAISE EXCEPTION 'invalid photo path'; END IF;
    IF v_primary_org<>p_org_id AND NOT public.p139_is_system_admin() THEN RAISE EXCEPTION 'system administrator required to edit a shared profile'; END IF;
    UPDATE public."TblP139Person" SET display_name=btrim(p_display_name),photo_path=p_photo_path,is_active=true,updated_at=now() WHERE id=p_person_id;
  END IF;
  INSERT INTO public."TblP139GroupPerson"(organization_id,person_id,recognition_priority,is_active)
  VALUES(p_org_id,p_person_id,p_recognition_priority,true)
  ON CONFLICT(organization_id,person_id) DO UPDATE SET recognition_priority=EXCLUDED.recognition_priority,is_active=true;
  DELETE FROM public."TblP139Alias" WHERE person_id=p_person_id;
  FOR v_alias IN SELECT btrim(t.alias_value) FROM jsonb_array_elements_text(COALESCE(p_aliases,'[]'::jsonb)) AS t(alias_value) LOOP
    IF v_alias<>'' THEN
      v_norm:=lower(regexp_replace(v_alias,'\s+','','g'));
      IF lower(regexp_replace(btrim(p_display_name),'\s+','','g'))=v_norm THEN CONTINUE; END IF;
      IF EXISTS(SELECT 1 FROM public."TblP139GroupPerson" gp JOIN public."TblP139Person" p ON p.id=gp.person_id
        WHERE gp.organization_id=p_org_id AND gp.is_active AND p.id<>p_person_id AND lower(regexp_replace(p.display_name,'\s+','','g'))=v_norm)
       OR EXISTS(SELECT 1 FROM public."TblP139Alias" a JOIN public."TblP139GroupPerson" gp ON gp.person_id=a.person_id
        WHERE gp.organization_id=p_org_id AND gp.is_active AND a.person_id<>p_person_id AND lower(regexp_replace(a.alias,'\s+','','g'))=v_norm)
      THEN RAISE EXCEPTION 'alias conflicts with another person in group'; END IF;
      INSERT INTO public."TblP139Alias"(person_id,alias) VALUES(p_person_id,v_alias) ON CONFLICT(person_id,alias) DO NOTHING;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('ok',true,'person_id',p_person_id);
END;
$$;

-- V0.7 removes old-photo migration. Keep the old bucket inaccessible through P139 policies.
DROP POLICY IF EXISTS "P139 legacy photo migration read" ON storage.objects;

-- Public study photos are readable by anyone; only authorized administrators can edit them.
DROP POLICY IF EXISTS "P139 private photo read" ON storage.objects;
DROP POLICY IF EXISTS "P139 private photo insert" ON storage.objects;
DROP POLICY IF EXISTS "P139 private photo update" ON storage.objects;
DROP POLICY IF EXISTS "P139 private photo delete" ON storage.objects;
DROP POLICY IF EXISTS "P139 public photo insert" ON storage.objects;
CREATE POLICY "P139 public photo insert" ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id='p139-public' AND public.p139_can_access_storage((storage.foldername(name))[1],true));
DROP POLICY IF EXISTS "P139 public photo update" ON storage.objects;
CREATE POLICY "P139 public photo update" ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id='p139-public' AND public.p139_can_access_storage((storage.foldername(name))[1],true))
WITH CHECK (bucket_id='p139-public' AND public.p139_can_access_storage((storage.foldername(name))[1],true));
DROP POLICY IF EXISTS "P139 public photo delete" ON storage.objects;
CREATE POLICY "P139 public photo delete" ON storage.objects FOR DELETE TO authenticated
USING (bucket_id='p139-public' AND public.p139_can_access_storage((storage.foldername(name))[1],true));

-- Run after setup. Every row should report PASS.
WITH expected_tables(name) AS (
  VALUES ('TblP139Organization'),('TblP139Membership'),('TblP139SystemAdmin'),('TblP139Person'),('TblP139Alias'),('TblP139UserPriority'),('TblP139AnswerEvent')
), expected_rpcs(name,anonymous_access) AS (
  VALUES ('p139_public_list_groups',true),('p139_public_list_people',true),('p139_public_check_answer',true),
         ('p139_is_system_admin',false),('p139_create_group',false),('p139_list_my_organizations',false),
         ('p139_list_people_for_admin',false),('p139_save_person',false),('p139_set_person_active',false),('p139_can_access_storage',false)
)
SELECT 'TABLE RLS: '||t.name AS check_item,
       CASE WHEN c.oid IS NOT NULL AND c.relrowsecurity THEN 'PASS' ELSE 'FAIL' END AS result
FROM expected_tables t LEFT JOIN pg_class c ON c.relname=t.name AND c.relnamespace='public'::regnamespace
UNION ALL
SELECT 'NO DIRECT TABLE ACCESS: '||t.name,
       CASE WHEN c.oid IS NOT NULL
         AND NOT has_table_privilege('anon',c.oid,'SELECT') AND NOT has_table_privilege('anon',c.oid,'INSERT') AND NOT has_table_privilege('anon',c.oid,'UPDATE') AND NOT has_table_privilege('anon',c.oid,'DELETE')
         AND NOT has_table_privilege('authenticated',c.oid,'SELECT') AND NOT has_table_privilege('authenticated',c.oid,'INSERT') AND NOT has_table_privilege('authenticated',c.oid,'UPDATE') AND NOT has_table_privilege('authenticated',c.oid,'DELETE')
       THEN 'PASS' ELSE 'FAIL' END
FROM expected_tables t LEFT JOIN pg_class c ON c.relname=t.name AND c.relnamespace='public'::regnamespace
UNION ALL
SELECT 'RPC DEFINITION: '||r.name,
       CASE WHEN p.oid IS NOT NULL AND p.prosecdef AND p.proconfig @> ARRAY['search_path=pg_catalog, public'] THEN 'PASS' ELSE 'FAIL' END
FROM expected_rpcs r LEFT JOIN pg_proc p ON p.proname=r.name AND p.pronamespace='public'::regnamespace
UNION ALL
SELECT 'RPC EXECUTE SCOPE: '||r.name,
       CASE WHEN p.oid IS NULL THEN 'FAIL'
         WHEN r.anonymous_access AND has_function_privilege('anon',p.oid,'EXECUTE') THEN 'PASS'
         WHEN NOT r.anonymous_access AND NOT has_function_privilege('anon',p.oid,'EXECUTE') AND has_function_privilege('authenticated',p.oid,'EXECUTE') THEN 'PASS'
         ELSE 'FAIL' END
FROM expected_rpcs r LEFT JOIN pg_proc p ON p.proname=r.name AND p.pronamespace='public'::regnamespace
UNION ALL
SELECT 'PUBLIC PHOTO BUCKET p139-public',CASE WHEN EXISTS(SELECT 1 FROM storage.buckets WHERE id='p139-public' AND public=true) THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'P139 PHOTO WRITE POLICIES',CASE WHEN (SELECT count(*) FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname LIKE 'P139 public photo %')=3 THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'LEGACY PHOTO MIGRATION READ POLICY',CASE WHEN EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='P139 legacy photo migration read') THEN 'PASS' ELSE 'FAIL' END;

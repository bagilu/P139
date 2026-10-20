-- Run after setup. Every row should report PASS.
WITH expected_tables(name) AS (
  VALUES ('TblP139Organization'),('TblP139Membership'),('TblP139Person'),('TblP139Alias'),('TblP139UserPriority'),('TblP139AnswerEvent')
), expected_rpcs(name) AS (
  VALUES ('p139_list_my_organizations'),('p139_list_people_for_priority'),('p139_set_my_priority'),('p139_get_quiz_cycle'),('p139_submit_answer'),('p139_list_people_for_admin'),('p139_save_person'),('p139_set_person_active'),('p139_add_member'),('p139_bootstrap_organization'),('p139_can_access_storage')
)
SELECT 'TABLE '||t.name AS check_item,
       CASE WHEN c.oid IS NOT NULL AND c.relrowsecurity THEN 'PASS' ELSE 'FAIL' END AS result
FROM expected_tables t LEFT JOIN pg_class c ON c.relname=t.name AND c.relnamespace='public'::regnamespace
UNION ALL
SELECT 'NO DIRECT TABLE PRIVILEGE: '||t.name,
       CASE WHEN c.oid IS NOT NULL
         AND NOT has_table_privilege('anon',c.oid,'SELECT')
         AND NOT has_table_privilege('anon',c.oid,'INSERT')
         AND NOT has_table_privilege('anon',c.oid,'UPDATE')
         AND NOT has_table_privilege('anon',c.oid,'DELETE')
         AND NOT has_table_privilege('authenticated',c.oid,'SELECT')
         AND NOT has_table_privilege('authenticated',c.oid,'INSERT')
         AND NOT has_table_privilege('authenticated',c.oid,'UPDATE')
         AND NOT has_table_privilege('authenticated',c.oid,'DELETE') THEN 'PASS' ELSE 'FAIL' END
FROM expected_tables t LEFT JOIN pg_class c ON c.relname=t.name AND c.relnamespace='public'::regnamespace
UNION ALL
SELECT 'RPC '||r.name,
       CASE WHEN p.oid IS NOT NULL AND p.prosecdef AND p.proconfig @> ARRAY['search_path=pg_catalog, public'] THEN 'PASS' ELSE 'FAIL' END
FROM expected_rpcs r LEFT JOIN pg_proc p ON p.proname=r.name AND p.pronamespace='public'::regnamespace
UNION ALL
SELECT 'RPC EXECUTE POLICY: '||r.name,
       CASE WHEN p.oid IS NULL OR has_function_privilege('anon',p.oid,'EXECUTE') THEN 'FAIL'
         WHEN r.name='p139_bootstrap_organization'
           AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE') THEN 'PASS'
         WHEN r.name<>'p139_bootstrap_organization'
           AND has_function_privilege('authenticated',p.oid,'EXECUTE') THEN 'PASS'
         ELSE 'FAIL' END
FROM expected_rpcs r LEFT JOIN pg_proc p ON p.proname=r.name AND p.pronamespace='public'::regnamespace
UNION ALL
SELECT 'PRIVATE STORAGE BUCKET p139-private',
       CASE WHEN EXISTS(SELECT 1 FROM storage.buckets WHERE id='p139-private' AND public=false) THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'P139 STORAGE POLICIES',
       CASE WHEN (SELECT count(*) FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname LIKE 'P139 private photo %')=4 THEN 'PASS' ELSE 'FAIL' END;

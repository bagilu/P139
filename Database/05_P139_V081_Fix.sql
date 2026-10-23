-- P139 V0.8.1: allow a person to have zero groups. Safe incremental migration.
BEGIN;
ALTER TABLE public."TblP139Person" ALTER COLUMN organization_id DROP NOT NULL;
COMMIT;

-- Verify: is_nullable must be YES
SELECT column_name,is_nullable FROM information_schema.columns
WHERE table_schema='public' AND table_name='TblP139Person' AND column_name='organization_id';

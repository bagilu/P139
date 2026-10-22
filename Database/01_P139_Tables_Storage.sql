-- P139 only. Run as the Supabase project owner in SQL Editor.
-- Tables are private. Front-end database operations are provided only by P139 RPCs.

CREATE TABLE IF NOT EXISTS public."TblP139Organization" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 120),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public."TblP139Membership" (
  organization_id uuid NOT NULL REFERENCES public."TblP139Organization"(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('admin','participant')),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id,user_id)
);

CREATE TABLE IF NOT EXISTS public."TblP139SystemAdmin" (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public."TblP139Person" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public."TblP139Organization"(id) ON DELETE CASCADE,
  display_name text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 1 AND 120),
  recognition_priority smallint NOT NULL DEFAULT 2 CHECK (recognition_priority BETWEEN 1 AND 3),
  photo_path text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id,id)
);

ALTER TABLE public."TblP139Person"
  ADD COLUMN IF NOT EXISTS recognition_priority smallint NOT NULL DEFAULT 2
  CHECK (recognition_priority BETWEEN 1 AND 3);

CREATE TABLE IF NOT EXISTS public."TblP139Alias" (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id uuid NOT NULL REFERENCES public."TblP139Person"(id) ON DELETE CASCADE,
  alias text NOT NULL CHECK (length(btrim(alias)) BETWEEN 1 AND 120),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (person_id,alias)
);

CREATE TABLE IF NOT EXISTS public."TblP139UserPriority" (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  person_id uuid NOT NULL REFERENCES public."TblP139Person"(id) ON DELETE CASCADE,
  priority smallint NOT NULL CHECK (priority BETWEEN 1 AND 3),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id,person_id)
);

CREATE TABLE IF NOT EXISTS public."TblP139AnswerEvent" (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  person_id uuid NOT NULL REFERENCES public."TblP139Person"(id) ON DELETE CASCADE,
  submitted_answer text NOT NULL CHECK (length(btrim(submitted_answer)) BETWEEN 1 AND 160),
  is_correct boolean NOT NULL,
  confused_with_person_id uuid REFERENCES public."TblP139Person"(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "IX_P139Membership_User" ON public."TblP139Membership"(user_id,is_active);
CREATE INDEX IF NOT EXISTS "IX_P139Person_Organization" ON public."TblP139Person"(organization_id,is_active);
CREATE INDEX IF NOT EXISTS "IX_P139Alias_Person" ON public."TblP139Alias"(person_id);
CREATE INDEX IF NOT EXISTS "IX_P139Priority_User_Person" ON public."TblP139UserPriority"(user_id,person_id);
CREATE INDEX IF NOT EXISTS "IX_P139Answer_User_Person_Time" ON public."TblP139AnswerEvent"(user_id,person_id,created_at DESC);

ALTER TABLE public."TblP139Organization" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."TblP139Membership" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."TblP139SystemAdmin" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."TblP139Person" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."TblP139Alias" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."TblP139UserPriority" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."TblP139AnswerEvent" ENABLE ROW LEVEL SECURITY;

-- Deny direct PostgREST table access. P139-owned SECURITY DEFINER RPCs validate auth.uid() and membership.
DROP POLICY IF EXISTS "P139 no direct access" ON public."TblP139Organization";
CREATE POLICY "P139 no direct access" ON public."TblP139Organization" FOR ALL TO anon,authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS "P139 no direct access" ON public."TblP139Membership";
CREATE POLICY "P139 no direct access" ON public."TblP139Membership" FOR ALL TO anon,authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS "P139 no direct access" ON public."TblP139SystemAdmin";
CREATE POLICY "P139 no direct access" ON public."TblP139SystemAdmin" FOR ALL TO anon,authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS "P139 no direct access" ON public."TblP139Person";
CREATE POLICY "P139 no direct access" ON public."TblP139Person" FOR ALL TO anon,authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS "P139 no direct access" ON public."TblP139Alias";
CREATE POLICY "P139 no direct access" ON public."TblP139Alias" FOR ALL TO anon,authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS "P139 no direct access" ON public."TblP139UserPriority";
CREATE POLICY "P139 no direct access" ON public."TblP139UserPriority" FOR ALL TO anon,authenticated USING (false) WITH CHECK (false);
DROP POLICY IF EXISTS "P139 no direct access" ON public."TblP139AnswerEvent";
CREATE POLICY "P139 no direct access" ON public."TblP139AnswerEvent" FOR ALL TO anon,authenticated USING (false) WITH CHECK (false);

-- Public bucket dedicated to intentionally public P139 learning portraits. Binary uploads use Storage's API;
-- all relational data changes remain behind P139 RPCs.
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES ('p139-public','p139-public',true,1048576,ARRAY['image/jpeg']::text[])
ON CONFLICT (id) DO UPDATE SET public=true,file_size_limit=1048576,allowed_mime_types=ARRAY['image/jpeg']::text[];

DROP POLICY IF EXISTS "P139 private photo read" ON storage.objects;
DROP POLICY IF EXISTS "P139 private photo insert" ON storage.objects;
DROP POLICY IF EXISTS "P139 private photo update" ON storage.objects;
DROP POLICY IF EXISTS "P139 private photo delete" ON storage.objects;
DROP POLICY IF EXISTS "P139 public photo insert" ON storage.objects;
DROP POLICY IF EXISTS "P139 public photo update" ON storage.objects;
DROP POLICY IF EXISTS "P139 public photo delete" ON storage.objects;

-- Policies are created after the P139 storage authorization helper in 02_P139_Functions.sql.

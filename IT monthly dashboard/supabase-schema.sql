-- ================================================================
-- IT Monthly Dashboard — Supabase Schema
-- Pacific Pipe PLC · IT Department
-- ================================================================
-- Run this SQL in: Supabase Dashboard → SQL Editor → New Query
-- ================================================================


-- ── 1. Profiles (extends auth.users) ─────────────────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email       TEXT,
  full_name   TEXT,
  role        TEXT NOT NULL DEFAULT 'viewer'
                   CHECK (role IN ('admin', 'editor', 'viewer')),
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.profiles IS 'User profiles with role-based access';
COMMENT ON COLUMN public.profiles.role IS 'admin: full access | editor: save reports | viewer: read-only';


-- ── 2. IT Reports (one record per month, upserted on save) ────────
CREATE TABLE IF NOT EXISTS public.it_reports (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  period_year      INT  NOT NULL,
  period_month     INT  NOT NULL CHECK (period_month BETWEEN 1 AND 12),
  data             JSONB NOT NULL DEFAULT '{}',
  updated_by       UUID REFERENCES public.profiles(id),
  updated_by_name  TEXT,
  updated_at       TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (period_year, period_month)
);

COMMENT ON TABLE public.it_reports IS 'Latest report data per period (year+month). Upserted on every save.';


-- ── 3. IT Report Versions (full audit trail) ──────────────────────
CREATE TABLE IF NOT EXISTS public.it_report_versions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  period_year     INT  NOT NULL,
  period_month    INT  NOT NULL,
  data            JSONB NOT NULL,
  saved_by        UUID REFERENCES public.profiles(id),
  saved_by_name   TEXT,
  saved_at        TIMESTAMPTZ DEFAULT NOW(),
  version_note    TEXT
);

CREATE INDEX IF NOT EXISTS idx_versions_period
  ON public.it_report_versions (period_year, period_month, saved_at DESC);

COMMENT ON TABLE public.it_report_versions IS 'Immutable audit trail — every save appends a new row.';


-- ================================================================
-- Row Level Security (RLS)
-- ================================================================

ALTER TABLE public.profiles           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_reports         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.it_report_versions ENABLE ROW LEVEL SECURITY;


-- ── profiles policies ─────────────────────────────────────────────
-- Users can always read their own profile
CREATE POLICY "profiles: read own"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

-- Admins can read all profiles
CREATE POLICY "profiles: admin read all"
  ON public.profiles FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role = 'admin'
  ));

-- Users can update their own profile (name only; role changes require admin)
CREATE POLICY "profiles: update own"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id AND role = (SELECT role FROM public.profiles WHERE id = auth.uid()));

-- Admins can update any profile (including role)
CREATE POLICY "profiles: admin update all"
  ON public.profiles FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role = 'admin'
  ));


-- ── it_reports policies ───────────────────────────────────────────
-- All authenticated users can read reports
CREATE POLICY "reports: authenticated read"
  ON public.it_reports FOR SELECT
  USING (auth.role() = 'authenticated');

-- Editors and admins can insert new reports
CREATE POLICY "reports: editor/admin insert"
  ON public.it_reports FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role IN ('admin', 'editor')
  ));

-- Editors and admins can update existing reports
CREATE POLICY "reports: editor/admin update"
  ON public.it_reports FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role IN ('admin', 'editor')
  ));


-- ── it_report_versions policies ───────────────────────────────────
-- All authenticated users can read version history
CREATE POLICY "versions: authenticated read"
  ON public.it_report_versions FOR SELECT
  USING (auth.role() = 'authenticated');

-- Editors and admins can append versions
CREATE POLICY "versions: editor/admin insert"
  ON public.it_report_versions FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role IN ('admin', 'editor')
  ));


-- ================================================================
-- Triggers
-- ================================================================

-- Auto-create profile row when a new Supabase Auth user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', SPLIT_PART(NEW.email, '@', 1)),
    'viewer'   -- default role; admin must promote via dashboard
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_updated_at ON public.profiles;
CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS reports_updated_at ON public.it_reports;
CREATE TRIGGER reports_updated_at
  BEFORE UPDATE ON public.it_reports
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ================================================================
-- Enable Realtime (so Dashboard auto-refreshes when data changes)
-- ================================================================
ALTER PUBLICATION supabase_realtime ADD TABLE public.it_reports;


-- ================================================================
-- Initial Setup — run AFTER creating users in Supabase Auth
-- ================================================================
-- Step 1: Create users via Supabase Dashboard → Authentication → Users
--         OR via the app's invite flow.
--
-- Step 2: Promote a user to admin:
--   UPDATE public.profiles
--   SET role = 'admin'
--   WHERE email = 'admin@pacificpipe.co.th';
--
-- Step 3: Promote editors:
--   UPDATE public.profiles
--   SET role = 'editor'
--   WHERE email IN ('editor1@pacificpipe.co.th', 'editor2@pacificpipe.co.th');
--
-- Viewers (read-only) need no changes — 'viewer' is the default role.
-- ================================================================

-- TraumaLink 360 / Supabase schema
-- Run this complete file once in Supabase Dashboard > SQL Editor.

begin;

create table if not exists public.trauma_cases (
  case_id text primary key,
  created_at timestamptz not null default now(),
  incident_time timestamptz not null default now(),
  moi text not null,
  patient_count smallint not null default 1 check (patient_count > 0),
  approx_age smallint check (approx_age between 0 and 120),
  sex text,
  eta_minutes integer check (eta_minutes >= 0),
  protection text,
  alcohol text,
  location text,
  gps text,
  ems_unit text,
  unit_level text,
  destination text,
  note text,
  status text not null default 'Dispatched',
  triage_level text not null default 'L3' check (triage_level in ('L1','L2','L3')),
  primary_survey jsonb,
  prearrival text,
  disposition text,
  disposition_note text,
  updated_at timestamptz not null default now()
);

create table if not exists public.case_timeline (
  case_id text not null references public.trauma_cases(case_id) on delete cascade,
  event_key text not null,
  label text not null,
  event_time timestamptz not null default now(),
  primary key (case_id, event_key)
);

create table if not exists public.vital_signs (
  id text primary key,
  case_id text not null references public.trauma_cases(case_id) on delete cascade,
  measured_at timestamptz not null default now(),
  sbp smallint,
  dbp smallint,
  hr smallint,
  rr smallint,
  spo2 smallint,
  gcs smallint,
  check (sbp is null or sbp between 0 and 350),
  check (dbp is null or dbp between 0 and 250),
  check (hr is null or hr between 0 and 300),
  check (rr is null or rr between 0 and 100),
  check (gcs is null or gcs between 3 and 15),
  check (spo2 is null or spo2 between 0 and 100)
);

create table if not exists public.interventions (
  id text primary key,
  case_id text not null references public.trauma_cases(case_id) on delete cascade,
  performed_at timestamptz not null default now(),
  intervention_type text not null,
  detail text not null
);

create table if not exists public.investigations (
  id text primary key,
  case_id text not null references public.trauma_cases(case_id) on delete cascade,
  ordered_at timestamptz not null default now(),
  item text not null,
  status text not null,
  result text
);

create table if not exists public.consultations (
  id text primary key,
  case_id text not null references public.trauma_cases(case_id) on delete cascade,
  requested_at timestamptz not null default now(),
  team text not null,
  status text not null,
  note text
);

create table if not exists public.ais_injuries (
  id text primary key,
  case_id text not null references public.trauma_cases(case_id) on delete cascade,
  body_region text not null,
  severity smallint not null check (severity between 1 and 6),
  description text
);

create table if not exists public.registry_records (
  case_id text primary key references public.trauma_cases(case_id) on delete cascade,
  final_diagnosis text,
  icu_los_days integer not null default 0 check (icu_los_days >= 0),
  hospital_los_days integer not null default 0 check (hospital_los_days >= 0),
  outcome text,
  updated_at timestamptz not null default now()
);

create table if not exists public.pips_flags (
  id text primary key,
  case_id text not null references public.trauma_cases(case_id) on delete cascade,
  flag text not null,
  detected_at timestamptz not null default now(),
  status text not null default 'Open' check (status in ('Open','Closed')),
  closed_at timestamptz,
  unique (case_id, flag)
);

create table if not exists public.app_settings (
  id text primary key default 'default' check (id = 'default'),
  hospital text not null default 'Trauma Center',
  si_l1 numeric(5,2) not null default 1.20 check (si_l1 > 0),
  ct_target_minutes integer not null default 30 check (ct_target_minutes >= 0),
  or_target_minutes integer not null default 60 check (or_target_minutes >= 0),
  scene_target_minutes integer not null default 10 check (scene_target_minutes >= 0),
  webhook_url text,
  updated_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id text primary key,
  event_time timestamptz not null default now(),
  role text not null,
  action text not null,
  case_id text,
  actor_user_id uuid default auth.uid(),
  actor_email text default (auth.jwt()->>'email')
);

-- Generates collision-free daily display IDs even with multiple dispatchers.
create table if not exists public.case_daily_sequences (
  case_date date primary key,
  last_value integer not null check (last_value > 0)
);

create index if not exists trauma_cases_created_at_idx on public.trauma_cases (created_at desc);
create index if not exists trauma_cases_status_idx on public.trauma_cases (status);
create index if not exists trauma_cases_triage_level_idx on public.trauma_cases (triage_level);
create index if not exists case_timeline_case_time_idx on public.case_timeline (case_id, event_time);
create index if not exists vital_signs_case_time_idx on public.vital_signs (case_id, measured_at);
create index if not exists interventions_case_time_idx on public.interventions (case_id, performed_at);
create index if not exists investigations_case_time_idx on public.investigations (case_id, ordered_at);
create index if not exists consultations_case_time_idx on public.consultations (case_id, requested_at);
create index if not exists ais_injuries_case_idx on public.ais_injuries (case_id);
create index if not exists pips_flags_status_idx on public.pips_flags (status, detected_at desc);
create index if not exists audit_logs_time_idx on public.audit_logs (event_time desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trauma_cases_set_updated_at on public.trauma_cases;
create trigger trauma_cases_set_updated_at before update on public.trauma_cases
for each row execute function public.set_updated_at();

drop trigger if exists registry_records_set_updated_at on public.registry_records;
create trigger registry_records_set_updated_at before update on public.registry_records
for each row execute function public.set_updated_at();

drop trigger if exists app_settings_set_updated_at on public.app_settings;
create trigger app_settings_set_updated_at before update on public.app_settings
for each row execute function public.set_updated_at();

create or replace function public.next_trauma_case_id()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_date date := (now() at time zone 'Asia/Bangkok')::date;
  v_value integer;
begin
  insert into public.case_daily_sequences (case_date, last_value)
  values (v_date, 1)
  on conflict (case_date) do update
    set last_value = public.case_daily_sequences.last_value + 1
  returning last_value into v_value;

  return 'TR-' || to_char(v_date, 'YYMMDD') || '-' || lpad(v_value::text, 4, '0');
end;
$$;

-- One RPC saves a complete case and all of its child records atomically.
create or replace function public.save_trauma_case(p_case jsonb)
returns text
language plpgsql
security invoker
set search_path = 'public'
as $$
declare
  v_case_id text := nullif(btrim(p_case->>'id'), '');
begin
  if v_case_id is null then
    raise exception 'Case ID is required';
  end if;

  insert into public.trauma_cases (
    case_id, created_at, incident_time, moi, patient_count, approx_age, sex,
    eta_minutes, protection, alcohol, location, gps, ems_unit, unit_level,
    destination, note, status, triage_level, primary_survey, prearrival,
    disposition, disposition_note
  ) values (
    v_case_id,
    coalesce(nullif(p_case->>'created','')::timestamptz, now()),
    coalesce(nullif(p_case->>'incidentTime','')::timestamptz, now()),
    coalesce(nullif(p_case->>'moi',''), 'Other'),
    greatest(1, coalesce(nullif(p_case->>'count','')::smallint, 1)),
    nullif(p_case->>'age','')::smallint,
    nullif(p_case->>'sex',''),
    nullif(p_case->>'eta','')::integer,
    nullif(p_case->>'protection',''),
    nullif(p_case->>'alcohol',''),
    nullif(p_case->>'location',''),
    nullif(p_case->>'gps',''),
    nullif(p_case->>'unit',''),
    nullif(p_case->>'unitLevel',''),
    nullif(p_case->>'destination',''),
    nullif(p_case->>'note',''),
    coalesce(nullif(p_case->>'status',''), 'Dispatched'),
    case when p_case->>'level' in ('L1','L2','L3') then p_case->>'level' else 'L3' end,
    p_case->'primary',
    nullif(p_case->>'prearrival',''),
    nullif(p_case->>'disposition',''),
    nullif(p_case->>'dispositionNote','')
  )
  on conflict (case_id) do update set
    created_at = excluded.created_at,
    incident_time = excluded.incident_time,
    moi = excluded.moi,
    patient_count = excluded.patient_count,
    approx_age = excluded.approx_age,
    sex = excluded.sex,
    eta_minutes = excluded.eta_minutes,
    protection = excluded.protection,
    alcohol = excluded.alcohol,
    location = excluded.location,
    gps = excluded.gps,
    ems_unit = excluded.ems_unit,
    unit_level = excluded.unit_level,
    destination = excluded.destination,
    note = excluded.note,
    status = excluded.status,
    triage_level = excluded.triage_level,
    primary_survey = excluded.primary_survey,
    prearrival = excluded.prearrival,
    disposition = excluded.disposition,
    disposition_note = excluded.disposition_note;

  delete from public.case_timeline where case_id = v_case_id;
  insert into public.case_timeline (case_id, event_key, label, event_time)
  select v_case_id, x->>'key', coalesce(nullif(x->>'label',''), x->>'key'),
         coalesce(nullif(x->>'time','')::timestamptz, now())
  from jsonb_array_elements(coalesce(p_case->'timeline', '[]'::jsonb)) x
  where nullif(x->>'key','') is not null;

  delete from public.vital_signs where case_id = v_case_id;
  insert into public.vital_signs (id, case_id, measured_at, sbp, dbp, hr, rr, spo2, gcs)
  select x->>'id', v_case_id, coalesce(nullif(x->>'time','')::timestamptz, now()),
         nullif(x->>'sbp','')::smallint, nullif(x->>'dbp','')::smallint,
         nullif(x->>'hr','')::smallint, nullif(x->>'rr','')::smallint,
         nullif(x->>'spo2','')::smallint, nullif(x->>'gcs','')::smallint
  from jsonb_array_elements(coalesce(p_case->'vitals', '[]'::jsonb)) x
  where nullif(x->>'id','') is not null;

  delete from public.interventions where case_id = v_case_id;
  insert into public.interventions (id, case_id, performed_at, intervention_type, detail)
  select x->>'id', v_case_id, coalesce(nullif(x->>'time','')::timestamptz, now()),
         coalesce(nullif(x->>'type',''), 'Other'), coalesce(x->>'detail','')
  from jsonb_array_elements(coalesce(p_case->'interventions', '[]'::jsonb)) x
  where nullif(x->>'id','') is not null;

  delete from public.investigations where case_id = v_case_id;
  insert into public.investigations (id, case_id, ordered_at, item, status, result)
  select x->>'id', v_case_id, coalesce(nullif(x->>'time','')::timestamptz, now()),
         coalesce(nullif(x->>'item',''), 'Other'), coalesce(nullif(x->>'status',''), 'Ordered'),
         nullif(x->>'result','')
  from jsonb_array_elements(coalesce(p_case->'investigations', '[]'::jsonb)) x
  where nullif(x->>'id','') is not null;

  delete from public.consultations where case_id = v_case_id;
  insert into public.consultations (id, case_id, requested_at, team, status, note)
  select x->>'id', v_case_id, coalesce(nullif(x->>'time','')::timestamptz, now()),
         coalesce(nullif(x->>'team',''), 'Other'), coalesce(nullif(x->>'status',''), 'Requested'),
         nullif(x->>'note','')
  from jsonb_array_elements(coalesce(p_case->'consults', '[]'::jsonb)) x
  where nullif(x->>'id','') is not null;

  delete from public.ais_injuries where case_id = v_case_id;
  insert into public.ais_injuries (id, case_id, body_region, severity, description)
  select x->>'id', v_case_id, coalesce(nullif(x->>'region',''), 'External'),
         greatest(1, least(6, coalesce(nullif(x->>'sev','')::smallint, 1))),
         nullif(x->>'desc','')
  from jsonb_array_elements(coalesce(p_case->'ais', '[]'::jsonb)) x
  where nullif(x->>'id','') is not null;

  delete from public.registry_records where case_id = v_case_id;
  insert into public.registry_records (
    case_id, final_diagnosis, icu_los_days, hospital_los_days, outcome, updated_at
  ) values (
    v_case_id,
    nullif(p_case#>>'{registry,dx}',''),
    greatest(0, coalesce(nullif(p_case#>>'{registry,icuLos}','')::integer, 0)),
    greatest(0, coalesce(nullif(p_case#>>'{registry,los}','')::integer, 0)),
    nullif(p_case#>>'{registry,outcome}',''),
    coalesce(nullif(p_case#>>'{registry,updated}','')::timestamptz, now())
  );

  delete from public.pips_flags where case_id = v_case_id;
  insert into public.pips_flags (id, case_id, flag, detected_at, status, closed_at)
  select x->>'id', v_case_id, x->>'flag',
         coalesce(nullif(x->>'time','')::timestamptz, now()),
         case when x->>'status' = 'Closed' then 'Closed' else 'Open' end,
         nullif(x->>'closed','')::timestamptz
  from jsonb_array_elements(coalesce(p_case->'pips', '[]'::jsonb)) x
  where nullif(x->>'id','') is not null and nullif(x->>'flag','') is not null;

  return v_case_id;
end;
$$;

insert into public.app_settings (id) values ('default') on conflict (id) do nothing;

-- Medical data must never be exposed to the public anon role.
revoke all on table
  public.trauma_cases, public.case_timeline, public.vital_signs,
  public.interventions, public.investigations, public.consultations,
  public.ais_injuries, public.registry_records, public.pips_flags,
  public.app_settings, public.audit_logs, public.case_daily_sequences
from anon;

revoke all on table public.case_daily_sequences from authenticated;

grant select, insert, update, delete on table
  public.trauma_cases, public.case_timeline, public.vital_signs,
  public.interventions, public.investigations, public.consultations,
  public.ais_injuries, public.registry_records, public.pips_flags,
  public.app_settings, public.audit_logs
to authenticated;

revoke all on function public.next_trauma_case_id() from public, anon;
revoke all on function public.save_trauma_case(jsonb) from public, anon;
grant execute on function public.next_trauma_case_id() to authenticated;
grant execute on function public.save_trauma_case(jsonb) to authenticated;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'trauma_cases','case_timeline','vital_signs','interventions','investigations',
    'consultations','ais_injuries','registry_records','pips_flags','app_settings','audit_logs'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('drop policy if exists authenticated_full_access on public.%I', table_name);
    execute format(
      'create policy authenticated_full_access on public.%I for all to authenticated using (true) with check (true)',
      table_name
    );
  end loop;
end $$;

commit;

-- Realtime is optional for writes, but enables automatic cross-device refresh.
-- These statements are outside the transaction so an already-added table can be ignored safely.
do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'trauma_cases','case_timeline','vital_signs','interventions','investigations',
    'consultations','ais_injuries','registry_records','pips_flags','app_settings','audit_logs'
  ] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', table_name);
    exception when duplicate_object then
      null;
    end;
  end loop;
end $$;

-- TraumaLink 360 / existing-project migration
-- Adds protected, case-linked storage for the complete ALS and BLS forms.

begin;

create table if not exists public.ems_assessments (
  case_id text not null references public.trauma_cases(case_id) on delete cascade,
  assessment_type text not null check (assessment_type in ('ALS','BLS')),
  form_data jsonb not null default '{}'::jsonb check (jsonb_typeof(form_data) = 'object'),
  assessed_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  primary key (case_id, assessment_type)
);

create index if not exists ems_assessments_type_time_idx
  on public.ems_assessments (assessment_type, assessed_at desc);

drop trigger if exists ems_assessments_set_updated_at on public.ems_assessments;
create trigger ems_assessments_set_updated_at
before update on public.ems_assessments
for each row execute function public.set_updated_at();

revoke all on table public.ems_assessments from anon;
grant select, insert, update, delete on table public.ems_assessments to authenticated;

alter table public.ems_assessments enable row level security;
drop policy if exists authenticated_full_access on public.ems_assessments;
create policy authenticated_full_access on public.ems_assessments
for all to authenticated using (true) with check (true);

commit;

do $$
begin
  alter publication supabase_realtime add table public.ems_assessments;
exception when duplicate_object then
  null;
end $$;

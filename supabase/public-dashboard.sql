-- Safe aggregate-only dashboard endpoint for signed-out visitors.
-- This file can be run independently on an existing TraumaLink 360 project.

begin;

create or replace function public.get_public_dashboard_stats()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
with
  local_clock as (
    select (now() at time zone 'Asia/Bangkok')::date as today
  ),
  case_totals as (
    select
      count(*) filter (
        where (c.created_at at time zone 'Asia/Bangkok')::date = clock.today
      )::integer as today,
      count(*) filter (
        where c.status in ('Incoming', 'Transport', 'En route')
      )::integer as incoming,
      count(*) filter (where c.triage_level = 'L1')::integer as level1,
      count(*)::integer as total
    from public.trauma_cases c
    cross join local_clock clock
  ),
  open_pips as (
    select count(distinct p.case_id)::integer as cases
    from public.pips_flags p
    where p.status = 'Open'
  ),
  triage as (
    select
      count(*) filter (where c.triage_level = 'L1')::integer as l1,
      count(*) filter (where c.triage_level = 'L2')::integer as l2,
      count(*) filter (where c.triage_level = 'L3')::integer as l3
    from public.trauma_cases c
  ),
  days as (
    select (clock.today - offset_value)::date as day
    from local_clock clock
    cross join generate_series(6, 0, -1) as offset_value
  ),
  volume as (
    select d.day, count(c.case_id)::integer as case_count
    from days d
    left join public.trauma_cases c
      on (c.created_at at time zone 'Asia/Bangkok')::date = d.day
    group by d.day
    order by d.day
  ),
  mechanism_counts as (
    select c.moi as name, count(*)::integer as case_count
    from public.trauma_cases c
    where nullif(btrim(c.moi), '') is not null
    group by c.moi
    order by count(*) desc, c.moi
    limit 5
  ),
  timeline as (
    select
      t.case_id,
      max(t.event_time) filter (where t.event_key = 'scene_arrival') as scene_arrival,
      max(t.event_time) filter (where t.event_key = 'depart_scene') as depart_scene,
      max(t.event_time) filter (where t.event_key = 'er_arrival') as er_arrival,
      max(t.event_time) filter (where t.event_key = 'ct_done') as ct_done,
      max(t.event_time) filter (where t.event_key = 'or_arrival') as or_arrival
    from public.case_timeline t
    group by t.case_id
  ),
  performance as (
    select
      round(avg(extract(epoch from (depart_scene - scene_arrival)) / 60)
        filter (where scene_arrival is not null and depart_scene is not null))::integer as scene_avg,
      count(*) filter (where scene_arrival is not null and depart_scene is not null)::integer as scene_count,
      round(avg(extract(epoch from (ct_done - er_arrival)) / 60)
        filter (where er_arrival is not null and ct_done is not null))::integer as ct_avg,
      count(*) filter (where er_arrival is not null and ct_done is not null)::integer as ct_count,
      round(avg(extract(epoch from (or_arrival - er_arrival)) / 60)
        filter (where er_arrival is not null and or_arrival is not null))::integer as or_avg,
      count(*) filter (where er_arrival is not null and or_arrival is not null)::integer as or_count
    from timeline
  ),
  targets as (
    select
      coalesce(max(s.scene_target_minutes), 10)::integer as scene_target,
      coalesce(max(s.ct_target_minutes), 30)::integer as ct_target,
      coalesce(max(s.or_target_minutes), 60)::integer as or_target
    from public.app_settings s
  )
select jsonb_build_object(
  'today', totals.today,
  'incoming', totals.incoming,
  'level1', totals.level1,
  'openPips', pips.cases,
  'total', totals.total,
  'triage', jsonb_build_object('L1', triage.l1, 'L2', triage.l2, 'L3', triage.l3),
  'volume', coalesce((
    select jsonb_agg(jsonb_build_object('date', v.day, 'count', v.case_count) order by v.day)
    from volume v
  ), '[]'::jsonb),
  'mechanisms', coalesce((
    select jsonb_agg(jsonb_build_object('name', m.name, 'count', m.case_count)
      order by m.case_count desc, m.name)
    from mechanism_counts m
  ), '[]'::jsonb),
  'performance', jsonb_build_object(
    'sceneAvg', perf.scene_avg, 'sceneCount', perf.scene_count,
    'ctAvg', perf.ct_avg, 'ctCount', perf.ct_count,
    'orAvg', perf.or_avg, 'orCount', perf.or_count
  ),
  'targets', jsonb_build_object(
    'scene', targets.scene_target, 'ct', targets.ct_target, 'or', targets.or_target
  ),
  'generatedAt', now()
)
from case_totals totals
cross join open_pips pips
cross join triage
cross join performance perf
cross join targets;
$$;

revoke all on function public.get_public_dashboard_stats() from public;
grant execute on function public.get_public_dashboard_stats() to anon, authenticated;

commit;

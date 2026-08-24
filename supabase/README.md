# Supabase setup for TraumaLink 360

1. Create a Supabase project.
2. In **Authentication > Providers**, keep Email enabled. Public sign-up is not
   used by the app.
3. Open **SQL Editor**, paste all of [`schema.sql`](./schema.sql), and run it once.
4. Open **Project Settings > API** and copy the Project URL and the publishable
   (or legacy anon) key. Never use a secret/service-role key in the browser.
5. Serve `index.html` over HTTP(S), open **Settings > Supabase Database**, save
   the URL/key, then sign in with a staff account.

## Admin and username login

The app converts a username such as `trauma.nurse` to the internal Auth email
`trauma.nurse@traumalink.app`. Existing staff can still sign in with a full email.

1. Create the first Admin user in **Authentication > Users** using the internal
   email `admin@traumalink.app`, a strong password, and automatic confirmation.
2. Run [`admin-bootstrap.sql`](./admin-bootstrap.sql) in SQL Editor to place the
   Admin role in protected `app_metadata`.
3. Deploy [`functions/admin-users/index.ts`](./functions/admin-users/index.ts)
   as the Edge Function named `admin-users` with JWT verification enabled.
4. Sign in with username `admin`. The protected **จัดการผู้ใช้** menu can then
   create confirmed Staff or Admin accounts. Passwords are handled only by
   Supabase Auth and the server-side function.

Never move `SUPABASE_SERVICE_ROLE_KEY` into `index.html`. Supabase injects that
secret into the Edge Function environment; the public browser receives only the
publishable key.

## Public dashboard aggregates

Signed-out visitors can call `get_public_dashboard_stats()` to see aggregate KPI,
7-day volume, triage mix, mechanism counts, and time-performance numbers. The
security-definer function returns no case IDs, demographics, locations, notes, or
clinical records. Existing projects can install or update it by running
[`public-dashboard.sql`](./public-dashboard.sql) in SQL Editor.

The browser keeps a local cache for temporary offline use. Supabase is the source
of truth after the first successful connection. On a first connection, any cases
already stored in the local browser are migrated into the empty project.

## ALS / BLS assessments

The full schema includes the protected `ems_assessments` table. For an existing
project that already has the earlier schema, run
[`ems-assessments.sql`](./ems-assessments.sql) once in SQL Editor. Each trauma
case can store one ALS and one BLS form in `form_data`, with the case foreign key,
assessment type, saved time, and updating Auth user recorded separately. Deleting
a trauma case cascades to its assessments.

## Tables used by each menu

| Menu | Tables |
| --- | --- |
| Dashboard | all case tables, `app_settings`, `pips_flags` |
| Dispatch | `trauma_cases`, `case_timeline`, `audit_logs` |
| Pre-hospital | `trauma_cases`, `case_timeline`, `vital_signs`, `interventions` |
| ER Command | `trauma_cases`, `case_timeline`, `investigations`, `consultations` |
| ประเมิน ALS / BLS | `trauma_cases`, `ems_assessments`, `audit_logs` |
| จัดการผู้ใช้ | Supabase Auth through the `admin-users` Edge Function |
| Registry | `trauma_cases`, `ais_injuries`, `registry_records` |
| PIPS | `pips_flags`, `trauma_cases` |
| Settings | `app_settings`, `audit_logs`; connection credentials stay on the device |

Row Level Security is enabled on every exposed table. The `anon` role has no
table access; authenticated staff users have access within this dedicated
hospital project. For a multi-hospital deployment, add a tenant/hospital ID and
restrict each policy before placing multiple organizations in one project.

# Supabase setup for TraumaLink 360

1. Create a Supabase project.
2. In **Authentication > Providers**, keep Email enabled. Create staff users in
   **Authentication > Users**. Public sign-up is not used by the app.
3. Open **SQL Editor**, paste all of [`schema.sql`](./schema.sql), and run it once.
4. Open **Project Settings > API** and copy the Project URL and the publishable
   (or legacy anon) key. Never use a secret/service-role key in the browser.
5. Serve `index.html` over HTTP(S), open **Settings > Supabase Database**, save
   the URL/key, then sign in with a staff account.

The browser keeps a local cache for temporary offline use. Supabase is the source
of truth after the first successful connection. On a first connection, any cases
already stored in the local browser are migrated into the empty project.

## Tables used by each menu

| Menu | Tables |
| --- | --- |
| Dashboard | all case tables, `app_settings`, `pips_flags` |
| Dispatch | `trauma_cases`, `case_timeline`, `audit_logs` |
| Pre-hospital | `trauma_cases`, `case_timeline`, `vital_signs`, `interventions` |
| ER Command | `trauma_cases`, `case_timeline`, `investigations`, `consultations` |
| Registry | `trauma_cases`, `ais_injuries`, `registry_records` |
| PIPS | `pips_flags`, `trauma_cases` |
| Settings | `app_settings`, `audit_logs`; connection credentials stay on the device |

Row Level Security is enabled on every exposed table. The `anon` role has no
table access; authenticated staff users have access within this dedicated
hospital project. For a multi-hospital deployment, add a tenant/hospital ID and
restrict each policy before placing multiple organizations in one project.

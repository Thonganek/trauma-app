-- Run after creating admin@traumalink.app in Supabase Authentication.
-- This grants server-verified Admin access without exposing any password in source code.
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
  || '{"role":"admin","username":"admin"}'::jsonb
where lower(email) = 'admin@traumalink.app';

select id, email, raw_app_meta_data
from auth.users
where lower(email) = 'admin@traumalink.app';

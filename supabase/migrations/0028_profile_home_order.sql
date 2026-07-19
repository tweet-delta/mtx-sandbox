-- Personal home-menu ordering: each person stores their preferred order of
-- home-screen button ids as an array of strings. NULL = use the app default.
-- Advisory display data only, never a security boundary. No RLS change needed:
-- profiles_update (0001) already lets a person update only their own row.
alter table public.profiles
  add column if not exists home_order text[];

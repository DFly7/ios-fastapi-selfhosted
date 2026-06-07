-- App profiles: one row per auth user, created automatically on signup.
-- RLS ensures each JWT can only see/update their own row.
-- No seed rows here: auth.users FK makes seeded profiles awkward; sign up once locally to create a row.

create table public.profiles (
  id uuid not null references auth.users (id) on delete cascade primary key,
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now()
);

comment on table public.profiles is 'User-facing profile; id matches auth.users.id';

alter table public.profiles enable row level security;

create policy "profiles_select_own"
  on public.profiles
  for select
  to authenticated
  using (id = auth.uid());

create policy "profiles_update_own"
  on public.profiles
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Inserts only happen from the trigger below (security definer). No insert policy for
-- "authenticated" → clients cannot insert rows directly.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    nullif(
      trim(
        coalesce(
          new.raw_user_meta_data ->> 'full_name',
          new.raw_user_meta_data ->> 'name',
          new.raw_user_meta_data ->> 'display_name',
          split_part(coalesce(new.email, ''), '@', 1)
        )
      ),
      ''
    )
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

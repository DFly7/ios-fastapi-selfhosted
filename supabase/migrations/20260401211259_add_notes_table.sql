-- Notes: user-owned text notes.
-- Demonstrates a full CRUD table pattern: RLS on all four operations,
-- a trigger to keep updated_at fresh, and a foreign-key to auth.users.

create table public.notes (
  id         uuid        not null default gen_random_uuid() primary key,
  user_id    uuid        not null references auth.users (id) on delete cascade,
  title      text        not null check (char_length(title) between 1 and 255),
  body       text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.notes is 'User-owned notes; user_id matches auth.users.id';

-- Index so listing a user''s notes (WHERE user_id = ?) is fast even with many rows.
create index notes_user_id_idx on public.notes (user_id);

alter table public.notes enable row level security;

-- Each authenticated user can only see their own notes.
create policy "notes_select_own"
  on public.notes
  for select
  to authenticated
  using (user_id = auth.uid());

-- Clients can insert only rows where they are the owner.
create policy "notes_insert_own"
  on public.notes
  for insert
  to authenticated
  with check (user_id = auth.uid());

-- Clients can update only their own notes.
create policy "notes_update_own"
  on public.notes
  for update
  to authenticated
  using  (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Clients can delete only their own notes.
create policy "notes_delete_own"
  on public.notes
  for delete
  to authenticated
  using (user_id = auth.uid());

-- Keep updated_at current whenever a row is modified.
create or replace function public.notes_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger notes_updated_at
  before update on public.notes
  for each row
  execute function public.notes_set_updated_at();

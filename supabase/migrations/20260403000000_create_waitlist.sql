-- Waitlist table: captures pre-launch email/phone signups from the GitHub Pages waitlist page.
-- Anon users can INSERT only. No SELECT/UPDATE/DELETE for anon — signups are private to service role.
-- A BEFORE INSERT trigger enforces per-IP rate limiting server-side.

create table public.waitlist (
  id         uuid        not null default gen_random_uuid() primary key,
  email      text        not null,
  phone      text,
  ip_address text,
  created_at timestamptz not null default now(),
  constraint waitlist_email_unique unique (email),
  constraint waitlist_email_format check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

comment on table public.waitlist is 'Pre-launch waitlist signups collected via the GitHub Pages landing page.';
comment on column public.waitlist.ip_address is 'Used by the rate-limit trigger; not exposed to anon callers.';

alter table public.waitlist enable row level security;

-- Anon users can sign up. No other operations permitted for anon.
create policy "waitlist_insert_anon"
  on public.waitlist
  for insert
  to anon
  with check (true);

-- ─── Rate-limit function ────────────────────────────────────────────────────
-- Raises an exception if the same IP has submitted more than RATE_LIMIT rows
-- within the last hour. Adjust the constant to change the threshold.
-- SECURITY DEFINER so it can read waitlist rows even though anon has no SELECT policy.

create or replace function public.check_waitlist_rate_limit()
  returns trigger
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  rate_limit  constant int := 5;  -- max sign-ups per IP per hour; adjust as needed
  recent_count int;
begin
  if new.ip_address is null then
    return new;
  end if;

  select count(*)
    into recent_count
    from public.waitlist
   where ip_address  = new.ip_address
     and created_at >= now() - interval '1 hour';

  if recent_count >= rate_limit then
    raise exception 'rate_limit_exceeded'
      using hint = 'Too many sign-ups from this IP address. Please try again later.';
  end if;

  return new;
end;
$$;

create trigger waitlist_rate_limit_trigger
  before insert on public.waitlist
  for each row
  execute function public.check_waitlist_rate_limit();

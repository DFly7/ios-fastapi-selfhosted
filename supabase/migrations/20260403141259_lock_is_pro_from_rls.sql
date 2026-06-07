-- Close the "open window" in the profiles update policy.
--
-- The old with check only confirmed the row still belonged to the user after
-- update, but did nothing to prevent an authenticated user from sending:
--   PATCH /profiles?id=eq.<their-uuid>  { "is_pro": true }
-- and granting themselves Pro status for free.
--
-- The fix: extend with check to assert that is_pro is unchanged.
-- The subquery reads the CURRENT (pre-update) value of is_pro for this user.
-- If the incoming payload tries to flip it the check fails and Postgres
-- rejects the update with a policy violation error before it hits the disk.
--
-- is_pro is owned exclusively by the RevenueCat webhook via the service role
-- key (which bypasses RLS). Authenticated users can never change it directly.

drop policy if exists "profiles_update_own" on public.profiles;

create policy "profiles_update_own"
  on public.profiles
  for update
  to authenticated
  using (id = auth.uid())
  with check (
    id = auth.uid()
    -- Prevent self-granting Pro: ensure is_pro is not modified by the client.
    and is_pro = (select is_pro from public.profiles where id = auth.uid())
  );

-- Add subscription status column to profiles.
-- Updated server-side by the RevenueCat webhook (service role key, bypasses RLS).
-- Readable by the authenticated user via the existing profiles_select_own RLS policy.

alter table public.profiles
    add column is_pro boolean not null default false;

comment on column public.profiles.is_pro is
    'True when the user has an active RevenueCat ''pro'' entitlement. '
    'Set exclusively by the POST /api/v1/webhooks/revenuecat backend endpoint — '
    'never write this from the client.';

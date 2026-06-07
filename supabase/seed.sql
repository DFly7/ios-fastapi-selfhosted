-- supabase/seed.sql — optional data loaded after migrations when seeding is enabled.
--
-- Seeding is on by default ([db.seed] enabled = true in supabase/config.toml). Disable there if unwanted.
-- Runs after migrations on: supabase db reset
--
-- Good candidates here:
--   • Reference / lookup rows (no foreign key to auth.users)
--   • Test fixtures for local-only tables you own end-to-end
--
-- Avoid (unless you know what you’re doing):
--   • Inserting into public.profiles — rows need a matching auth.users.id (created on signup).
--     For template dev, sign in once after reset, or use the dashboard / SQL as admin.
--
-- Example (commented):
-- insert into public.some_lookup (slug, label)
-- values ('demo', 'Demo')
-- on conflict (slug) do nothing;

select 1;
-- ↑ no-op placeholder (zero side effects) until you add real insert statements above

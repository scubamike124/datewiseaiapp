> **Note (v2 app):** the app no longer uses accounts or Supabase; this guide applies only to the old v1 web app.

# DateWise AI — Admin & Accounts Guide

This explains how to switch on user accounts and use the **Supabase dashboard as
your admin panel** (view users, see paid users, control accounts).

Accounts are **optional**. Until you complete setup below, the web app runs
exactly as before: no sign-up, all data stays in the visitor's browser.

---

## One-time setup (≈10 minutes)

### 1. Create a Supabase project
1. Go to <https://supabase.com> → sign in → **New project**.
2. Pick a name, a strong database password, and a region close to your users.
3. Wait ~2 min for it to provision.

### 2. Create the tables
1. In the project: **SQL Editor → New query**.
2. Open [`backend/supabase_schema.sql`](backend/supabase_schema.sql), copy
   **everything**, paste it in, and click **Run**.
3. You should see "Success". This created `profiles`, `subscriptions`, security
   rules, and the `admin_user_overview` view.

### 3. Get your two keys
1. **Settings → API**.
2. Copy the **Project URL** and the **anon public** key.
   (The anon key is meant to be public — safe to ship in a web build.)

### 4. Put the keys into the app
Either paste them into [`lib/services/supabase_config.dart`](lib/services/supabase_config.dart)
(`_inlineUrl` and `_inlineAnonKey`), **or** pass them at build time:

```bash
flutter build web --release \
  --dart-define=SUPABASE_URL=https://YOURPROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Rebuild and re-upload the `build/web` output to cPanel (same as before). The
moment these keys are present, **subscribing requires creating an account.**

### 5. Make yourself the admin
1. Open the live site and **sign up** with your own email.
2. Back in Supabase: **SQL Editor**, run:
   ```sql
   update public.profiles set role = 'admin' where email = 'you@example.com';
   ```

### 6. (Optional) Skip email confirmation while testing
By default Supabase emails a confirmation link before first login.
To let accounts work instantly during testing:
**Authentication → Providers → Email → turn OFF "Confirm email" → Save.**
(Turn it back on for production to stop fake sign-ups.)

---

## Using the admin panel (the Supabase dashboard)

### See all users
**Table Editor → `admin_user_overview`** — every user with email, name, plan,
status, and join date. Or run in the SQL Editor:
```sql
select * from public.admin_user_overview;
```

### See paid users / counts
Today (before real payments are wired) everyone who picks a plan is
`pending_payment`. Once you add billing, paying users become `active`.

```sql
-- Everyone currently paying:
select * from public.admin_user_overview where status = 'active';

-- How many paid, broken down by plan:
select tier, count(*)
from public.subscriptions
where status = 'active'
group by tier;

-- Signups in the last 7 days:
select count(*) from public.profiles
where created_at > now() - interval '7 days';
```

### Control a user
- **Suspend / ban or delete:** **Authentication → Users** → click the user →
  **Ban** (temporary) or **Delete** (permanent).
- **Change someone's plan manually:** **Table Editor → `subscriptions`** → edit
  their `tier` / `status` row.
- **Grant another admin:** set their `profiles.role` to `admin` (SQL above).

---

## What's NOT done yet (by design)

- **Real payments.** You chose to add billing later (in-app purchases for the
  mobile app, and/or a web gateway). Until then, "subscribe" records the chosen
  plan as `pending_payment` — nobody is actually charged, so treat `active`
  counts as zero for now.
- When you're ready, we add a payment provider whose webhook flips users to
  `status = 'active'` from a trusted server (a Supabase **Edge Function** using
  the service-role key — never from the app/browser). The admin queries above
  won't change; the numbers just become real.

---

## Security notes (important)

- The **anon key is safe** to ship; your data is protected by row-level security
  (already set up in the schema): a logged-in user can only read their own rows.
- **Never** put the **service_role** key in the Flutter app — it bypasses all
  security. It belongs only in server-side Edge Functions.
- "Paid" status must only ever be set by a trusted server after a real payment,
  never trusted from the client.

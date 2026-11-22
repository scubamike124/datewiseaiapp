# Admin guide (v1 only — obsolete)

The v1 web app (1.0.x) had optional user accounts backed by Supabase, and this
file explained how to set them up. **The v2 app has no accounts, no Supabase
and no server-side user data**: everything is stored on the device, the
subscription is managed by Apple (App Store Connect), and the coach backend is
the Cloudflare Worker in `backend/worker.js`.

There is nothing to administer in the app itself. The old instructions are in
the git history of this file if they are ever needed.

/// Configuration for the optional Supabase backend (accounts + the
/// user/subscription database that powers the admin panel).
///
/// DateWise AI works perfectly with **no backend at all** — when the values
/// below are empty, the app behaves exactly as it always has: no sign-up, all
/// data stays in the visitor's browser. Filling these in switches on accounts:
/// visitors must sign up before subscribing, and every user shows up in your
/// Supabase dashboard (your admin panel).
///
/// Both values are **safe to commit and ship in a web build** — the anon key is
/// a public client key designed to be exposed; row-level security in the
/// database (see `backend/supabase_schema.sql`) is what protects your data.
///
/// Set them at build time (recommended):
///   flutter build web --release \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJhbGci...
/// or paste them into the inline fallbacks below.
class SupabaseConfig {
  SupabaseConfig._();

  /// Your project URL, e.g. https://abcdefgh.supabase.co
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _inlineUrl,
  );

  /// Your project's **anon public** key (Settings → API). Public by design.
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: _inlineAnonKey,
  );

  // --- Paste your values here (or use --dart-define above) -----------------
  // datewisecom's Project (anon public key — safe to ship in a web build).
  static const String _inlineUrl = 'https://cprnegusibbmcyltylzk.supabase.co';
  static const String _inlineAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNwcm5lZ3VzaWJibWN5bHR5bHprIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA3ODU3MzMsImV4cCI6MjA5NjM2MTczM30.8OQ6Bm0u6Jb7Z4zfWKmWuTRyjTXA2_-P1xl7ru6mE8E';

  /// Whether accounts/admin are switched on. When false the app stays in its
  /// original no-sign-up, device-only mode.
  static bool get isConfigured =>
      url.trim().isNotEmpty && anonKey.trim().isNotEmpty;
}

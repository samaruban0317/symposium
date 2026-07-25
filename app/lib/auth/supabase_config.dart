/// Connection to the **shared Visionary Sparks Supabase** — the same project
/// that backs Classmate AI (/beta), careers, and team. Reusing it means one
/// Google account across the whole product family, and the Symposium host's
/// "student" tier already trusts JWTs this project issues (the host verifies
/// them against SUPABASE_JWT_SECRET), so a signed-in user gets higher limits
/// with zero extra backend.
///
/// Only the **anon** key lives here. It is public by design — it is already
/// embedded in the live web frontend (login.html) and served to every visitor;
/// row-level security, not secrecy, is what protects the data. The service-role
/// key and the JWT secret are server-only and never appear in this app.
library;

const String kSupabaseUrl = 'https://gpjozyrsvxvfaowgfrob.supabase.co';

// NOTE: anon (public) key — keep this exact ASCII string byte-for-byte.
const String kSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdwam96eXJzdnh2ZmFvd2dmcm9iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA0Mzc4MTcsImV4cCI6MjA5NjAxMzgxN30.CWlQLph_ARfC_LV99NrhaY1C2z5KfSA_LH_fX7_AeQc';

/// The loopback address Supabase redirects back to after Google sign-in. Must
/// be present in the Supabase dashboard's Auth ▸ URL Configuration ▸ Redirect
/// URLs allow-list, or the redirect is rejected. Port chosen next to the
/// Symposium proxy/discovery ports (47474/47475) to keep them together.
const int kOAuthLoopbackPort = 47476;

String get kOAuthRedirect => 'http://localhost:$kOAuthLoopbackPort/callback';

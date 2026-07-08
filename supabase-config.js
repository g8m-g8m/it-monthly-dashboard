// ================================================================
// supabase-config.js
// Pacific Pipe PLC · IT Dashboard — Supabase Client
// ================================================================
// ⚠️  Replace SUPABASE_URL_HERE with your project URL.
//     Found in: Supabase Dashboard → Settings → API → Project URL
//     Example:  https://abcdefghijklmnop.supabase.co
// ================================================================

(function () {
  const SUPABASE_URL      = 'https://rnpjiilastgjsbyfpfkl.supabase.co';
  const SUPABASE_ANON_KEY = 'sb_publishable_hZWtRGHc3mm5cRip6PYAjQ_hzGiUSml';

  // Guard: SDK must be loaded before this file
  if (!window.supabase) {
    console.error('[supabase-config] Supabase SDK not found. Make sure the CDN script is loaded first.');
    return;
  }
  if (SUPABASE_URL === 'SUPABASE_URL_HERE') {
    console.warn('[supabase-config] ⚠️  Please set SUPABASE_URL in supabase-config.js');
  }

  // Create singleton client
  window._sbClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: false
    },
    realtime: {
      params: { eventsPerSecond: 5 }
    }
  });

  // Convenience accessor
  window.getSupabaseClient = function () {
    return window._sbClient;
  };

  console.log('[supabase-config] ✓ Supabase client ready');
})();

// Supabase connection settings for the Route Checklist.
//
// These two values are SAFE to commit and to ship in the browser:
//   - The project URL is just the address of your database.
//   - The "publishable" key is public by design. Row-Level Security (the rules
//     in supabase/migrations/0001_init.sql) is what actually protects the data.
//
// NEVER put the `service_role` / secret key here — that one bypasses all
// security and must stay in the Supabase dashboard only.
window.SUPABASE_URL = "https://eccukivhjgiqwfnosevt.supabase.co";
window.SUPABASE_PUBLISHABLE_KEY = "sb_publishable_YsnL38EMpfeb0qdVGPmdjA__RA-T1HB";

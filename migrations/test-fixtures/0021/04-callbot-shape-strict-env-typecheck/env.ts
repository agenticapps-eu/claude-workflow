// Callbot-shape strict Env interface — NO index signature.
// If this fails to satisfy withCronMonitor / withQueueMonitor's generic,
// SC5 fails. This is the acceptance proxy per issue #56's check #3.
export interface CallbotEnv {
  SENTRY_DSN: string;
  SERVICE_NAME: string;
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
  OPENAI_API_KEY: string;
  // intentionally NO [key: string]: unknown
}

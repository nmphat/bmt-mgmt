import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!supabaseUrl || !supabaseAnonKey) {
  console.warn('Supabase URL or Anon Key is missing. Check your .env file.')
}

/**
 * Root cause of "no API calls after alt-tab" bug (Supabase JS >= 2.33):
 *
 * Supabase registers its own `visibilitychange` listener in _handleVisibilityChange().
 * Every time the tab becomes visible it fires _onVisibilityChanged() which
 * unconditionally calls _acquireLock() → _recoverAndRefresh() → _callRefreshToken()
 * → HTTP fetch to the auth server.
 *
 * When the user alt-tabs back, the OS-level network stack is still warming up
 * (~100-500 ms delay). The auth refresh fetch hangs. Because every
 * supabase.from().select() also calls _acquireLock(), they all queue behind the
 * stuck refresh inside `pendingInLock` and never reach the network.
 *
 * Worse: In In() (GoTrue's fetch wrapper) *any* error including AbortError is
 * re-thrown as AuthRetryableFetchError, causing the bn() retry loop to keep
 * retrying for up to 60 seconds before giving up.
 *
 * THE FIX:
 * After initialization, remove Supabase's visibilityChangedCallback and replace
 * it with our own handler in App.vue that waits 500 ms before doing any auth
 * work, giving the network time to stabilize.
 *
 * Additionally, bypass navigator.locks (also can deadlock on OS focus switches)
 * because single-tab SPAs don't need cross-tab token-refresh isolation.
 */
export const supabase = createClient(supabaseUrl || '', supabaseAnonKey || '', {
  auth: {
    // Bypass navigator.locks — can deadlock when the OS releases the tab from background
    lock: async <R>(_name: string, _acquireTimeout: number, fn: () => Promise<R>): Promise<R> =>
      fn(),
  },
})

/**
 * Call once after supabase.auth is initialized.
 * Removes Supabase's built-in visibilitychange listener so it can be
 * replaced by a delayed version in App.vue.
 */
export function detachSupabaseVisibilityHandler(): void {
  if (typeof window === 'undefined') return
  const auth = supabase.auth as any
  if (auth.visibilityChangedCallback) {
    window.removeEventListener('visibilitychange', auth.visibilityChangedCallback)
    auth.visibilityChangedCallback = null
  }
}

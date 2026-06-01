import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import { supabase, detachSupabaseVisibilityHandler } from '@/lib/supabase'
import type { User, Subscription } from '@supabase/supabase-js'

interface MemberProfile {
  id: string
  role: 'admin' | 'member'
  display_name: string
}

export const useAuthStore = defineStore('auth', () => {
  const user = ref<User | null>(null)
  const profile = ref<MemberProfile | null>(null)
  const loading = ref(true)
  // Track initialization state to prevent duplicate subscriptions
  let isInitialized = false
  let authSubscription: Subscription | null = null

  const isAuthenticated = computed(() => !!user.value)
  const isAdmin = computed(() => profile.value?.role === 'admin')

  async function fetchProfile(userId: string) {
    try {
      const { data, error } = await supabase
        .from('members')
        .select('id, role, display_name')
        .eq('user_id', userId)
        .single()

      if (error) {
        console.warn('Error fetching member profile:', error)
        return
      }
      profile.value = data as MemberProfile
    } catch (e) {
      console.error('Exception fetching profile:', e)
    }
  }

  async function initialize() {
    // Prevent double-initialization (e.g. called from both App.vue and router guard)
    if (isInitialized) return
    isInitialized = true

    loading.value = true
    const {
      data: { session },
    } = await supabase.auth.getSession()

    // Remove Supabase's own visibilitychange handler (registered during
    // getSession → initializePromise resolution). We replace it with a
    // delayed version in App.vue to avoid the "no API calls after alt-tab" bug.
    detachSupabaseVisibilityHandler()

    user.value = session?.user ?? null

    if (user.value) {
      await fetchProfile(user.value.id)
    }

    loading.value = false

    // Register the auth state listener only once and store the subscription
    if (!authSubscription) {
      const { data } = supabase.auth.onAuthStateChange(async (_event, session) => {
        user.value = session?.user ?? null
        if (user.value) {
          await fetchProfile(user.value.id)
        } else {
          profile.value = null
        }
      })
      authSubscription = data.subscription
    }
  }

  /**
   * Re-sync auth state from Supabase — call this when the tab regains focus.
   * Supabase auto-refreshes the token on visibilitychange, but user.value can
   * temporarily become null during the refresh window. This ensures the store
   * is brought back in sync without a full page reload.
   */
  async function syncSession() {
    const {
      data: { session },
    } = await supabase.auth.getSession()
    const freshUser = session?.user ?? null
    user.value = freshUser
    if (freshUser) {
      if (!profile.value || profile.value.id !== freshUser.id) {
        await fetchProfile(freshUser.id)
      }
    } else {
      profile.value = null
    }
  }

  async function signOut() {
    authSubscription?.unsubscribe()
    authSubscription = null
    isInitialized = false
    await supabase.auth.signOut()
    user.value = null
    profile.value = null
  }

  return {
    user,
    profile,
    loading,
    isAuthenticated,
    isAdmin,
    initialize,
    syncSession,
    signOut,
  }
})

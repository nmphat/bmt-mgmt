import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import { supabase } from '@/lib/supabase'
import type { User } from '@supabase/supabase-js'

interface MemberProfile {
  id: string
  role: 'admin' | 'member'
  display_name: string
}

export const useAuthStore = defineStore('auth', () => {
  const user = ref<User | null>(null)
  const profile = ref<MemberProfile | null>(null)
  const loading = ref(true)

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
    loading.value = true
    const {
      data: { session },
    } = await supabase.auth.getSession()
    user.value = session?.user ?? null

    if (user.value) {
      await fetchProfile(user.value.id)
    }

    loading.value = false

    supabase.auth.onAuthStateChange(async (_event, session) => {
      user.value = session?.user ?? null
      if (user.value) {
        await fetchProfile(user.value.id)
      } else {
        profile.value = null
      }
    })
  }

  async function signOut() {
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
    signOut,
  }
})

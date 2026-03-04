<script setup lang="ts">
import { onMounted, onUnmounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { supabase } from '@/lib/supabase'
import AppHeader from '@/components/AppHeader.vue'

const authStore = useAuthStore()

/**
 * Replacement for Supabase's own visibilitychange handler (which we remove in
 * authStore.initialize()). The 500 ms delay lets the OS-level network stack
 * finish warming up after an app switch before we attempt any auth work,
 * preventing _callRefreshToken() from hanging and deadlocking all API calls.
 */
async function handleVisibilityChange() {
  if (document.hidden) return

  // Give the network stack ~500 ms to stabilize after the OS-level focus switch.
  await new Promise((resolve) => setTimeout(resolve, 500))

  if (document.hidden) return // user switched away again during the delay

  // Recover the session: reads from localStorage, refreshes only if the token
  // is expired or near expiry. By now the network is available.
  try {
    const {
      data: { session },
    } = await supabase.auth.getSession()
    if (session?.user && !authStore.user) {
      // Sync back into the store if onAuthStateChange missed it
      authStore.syncSession()
    }
  } catch (e) {
    console.warn('[auth] session recovery on visibility change failed:', e)
  }
}

onMounted(async () => {
  await authStore.initialize()
  window.addEventListener('visibilitychange', handleVisibilityChange)
})

onUnmounted(() => {
  window.removeEventListener('visibilitychange', handleVisibilityChange)
})
</script>

<template>
  <div class="min-h-screen bg-gray-50">
    <AppHeader />

    <main>
      <router-view />
    </main>
  </div>
</template>

<style>
/* Any global styles if needed */
</style>

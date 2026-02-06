<script setup lang="ts">
import { computed } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useRouter } from 'vue-router'
import { LogOut, LogIn, User } from 'lucide-vue-next'

const authStore = useAuthStore()
const router = useRouter()

const displayName = computed(() => {
  if (authStore.profile?.display_name) {
    return authStore.profile.display_name
  }
  return authStore.user?.email || 'User'
})

async function handleLogout() {
  await authStore.signOut()
  router.push('/login')
}

function handleLogin() {
  router.push('/login')
}
</script>

<template>
  <header class="bg-white shadow-sm border-b border-gray-100 sticky top-0 z-50">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
      <!-- Logo / Title -->
      <router-link to="/" class="flex items-center gap-2 group">
        <div class="bg-indigo-600 text-white p-1.5 rounded-lg group-hover:bg-indigo-700 transition">
          <!-- Simple Shuttlecock icon representation or similar -->
          <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-activity"><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg>
        </div>
        <span class="text-xl font-bold text-gray-900 group-hover:text-indigo-600 transition">Badminton Mgmt</span>
      </router-link>

      <!-- Right Side Actions -->
      <div class="flex items-center gap-4">
        <template v-if="authStore.isAuthenticated">
          <div class="flex items-center gap-2 text-sm text-gray-700 bg-gray-50 px-3 py-1.5 rounded-full border border-gray-200">
            <User class="w-4 h-4 text-gray-500" />
            <span class="font-medium max-w-[150px] truncate">{{ displayName }}</span>
            <span v-if="authStore.isAdmin" class="text-xs bg-indigo-100 text-indigo-700 px-1.5 py-0.5 rounded ml-1">Admin</span>
          </div>
          
          <button
            @click="handleLogout"
            class="flex items-center gap-2 px-3 py-2 text-sm font-medium text-gray-600 hover:text-red-600 hover:bg-red-50 rounded-md transition"
            title="Logout"
          >
            <LogOut class="w-4 h-4" />
            <span class="hidden sm:inline">Logout</span>
          </button>
        </template>

        <template v-else>
          <button
            @click="handleLogin"
            class="flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 rounded-md shadow-sm transition"
          >
            <LogIn class="w-4 h-4" />
            <span>Login</span>
          </button>
        </template>
      </div>
    </div>
  </header>
</template>

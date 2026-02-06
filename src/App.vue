<script setup lang="ts">
import { onMounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import AppHeader from '@/components/AppHeader.vue'

const authStore = useAuthStore()

onMounted(async () => {
  await authStore.initialize()
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
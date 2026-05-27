<script setup lang="ts">
import { onMounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import AppHeader from '@/components/AppHeader.vue'
import BottomNav from '@/components/BottomNav.vue'

const authStore = useAuthStore()

onMounted(async () => {
  await authStore.initialize()
})
</script>

<template>
  <div class="min-h-screen bg-gray-50">
    <AppHeader />

    <!--
      Fixed-layer contract:
      - Mobile bottom nav: z-40.
      - Sticky group payment bars: above nav with bottom offset, below sheets/modals.
      - Modal/sheet overlays and footers: above fixed bars.
      - Toasts: above non-modal fixed bars, offset on mobile so they do not cover nav/group CTAs.
    -->
    <main class="app-main-safe">
      <router-view />
    </main>

    <BottomNav />
  </div>
</template>

<style>
.app-main-safe {
  padding-bottom: calc(96px + env(safe-area-inset-bottom));
}

@media (min-width: 768px) {
  .app-main-safe {
    padding-bottom: 0;
  }
}

@media (max-width: 767px) {
  .Vue-Toastification__container.bottom-left,
  .Vue-Toastification__container.bottom-right,
  .Vue-Toastification__container.bottom-center {
    bottom: calc(148px + env(safe-area-inset-bottom));
  }
}
</style>

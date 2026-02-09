<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { useRouter } from 'vue-router'
import { LogOut, LogIn, User, Languages, ChevronDown } from 'lucide-vue-next'

const authStore = useAuthStore()
const langStore = useLangStore()
const router = useRouter()

const isLangOpen = ref(false)
const langRef = ref<HTMLElement | null>(null)

const displayName = computed(() => {
  if (authStore.profile?.display_name) {
    return authStore.profile.display_name
  }
  return authStore.user?.email || t.value('common.user')
})

const t = computed(() => langStore.t)

async function handleLogout() {
  await authStore.signOut()
  router.push('/login')
}

function handleLogin() {
  router.push('/login')
}

function selectLang(lang: 'vi' | 'en') {
  langStore.setLang(lang)
  isLangOpen.value = false
}

function handleClickOutside(event: MouseEvent) {
  if (langRef.value && !langRef.value.contains(event.target as Node)) {
    isLangOpen.value = false
  }
}

onMounted(() => {
  document.addEventListener('click', handleClickOutside)
})

onUnmounted(() => {
  document.removeEventListener('click', handleClickOutside)
})
</script>

<template>
  <header class="bg-white shadow-sm border-b border-gray-100 sticky top-0 z-50">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
      <!-- Logo / Title -->
      <router-link to="/" class="flex items-center gap-2 group">
        <div class="bg-indigo-600 text-white p-1.5 rounded-lg group-hover:bg-indigo-700 transition">
          <!-- Simple Shuttlecock icon representation or similar -->
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="24"
            height="24"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            class="lucide lucide-activity"
          >
            <path d="M22 12h-4l-3 9L9 3l-3 9H2" />
          </svg>
        </div>
        <span class="text-xl font-bold text-gray-900 group-hover:text-indigo-600 transition"
          >Badminton Mgmt</span
        >
      </router-link>

      <!-- Navigation -->
      <nav v-if="authStore.isAuthenticated" class="hidden md:flex items-center gap-6 mx-6">
        <router-link
          to="/"
          active-class="text-indigo-600"
          class="text-sm font-medium text-gray-700 hover:text-indigo-600 transition"
        >
          {{ t('dashboard.title') }}
        </router-link>
        <router-link
          to="/create-session"
          active-class="text-indigo-600"
          class="text-sm font-medium text-gray-700 hover:text-indigo-600 transition"
        >
          {{ t('dashboard.newSession') }}
        </router-link>
        <router-link
          to="/members"
          active-class="text-indigo-600"
          class="text-sm font-medium text-gray-700 hover:text-indigo-600 transition"
        >
          {{ t('common.member') }}
        </router-link>
      </nav>

      <!-- Right Side Actions -->
      <div class="flex items-center gap-2 sm:gap-4">
        <!-- Language Dropdown -->
        <div class="relative" ref="langRef">
          <button
            @click="isLangOpen = !isLangOpen"
            class="flex items-center gap-1.5 px-2 py-1.5 text-xs font-bold rounded-md border transition-all duration-200 shadow-sm"
            :class="
              langStore.currentLang === 'vi'
                ? 'bg-red-50 text-red-700 border-red-200 hover:bg-red-100'
                : 'bg-blue-50 text-blue-700 border-blue-200 hover:bg-blue-100'
            "
            :title="langStore.currentLang === 'vi' ? t('nav.switchEn') : t('nav.switchVi')"
          >
            <Languages class="w-4 h-4" />
            <span class="uppercase w-4 text-center">{{ langStore.currentLang }}</span>
            <ChevronDown
              class="w-3 h-3 transition-transform duration-200"
              :class="{ 'rotate-180': isLangOpen }"
            />
          </button>

          <transition
            enter-active-class="transition ease-out duration-100"
            enter-from-class="transform opacity-0 scale-95"
            enter-to-class="transform opacity-100 scale-100"
            leave-active-class="transition ease-in duration-75"
            leave-from-class="transform opacity-100 scale-100"
            leave-to-class="transform opacity-0 scale-95"
          >
            <div
              v-if="isLangOpen"
              class="absolute right-0 mt-2 w-40 rounded-md shadow-lg bg-white ring-1 ring-black ring-opacity-5 z-[60] py-1 focus:outline-none"
            >
              <button
                @click="selectLang('vi')"
                class="flex items-center w-full px-4 py-2 text-sm text-gray-700 hover:bg-indigo-50 hover:text-indigo-600 transition-colors"
                :class="{ 'bg-gray-50 font-bold text-indigo-600': langStore.currentLang === 'vi' }"
              >
                <span class="mr-3 text-base">🇻🇳</span> {{ t('nav.vietnamese') }}
              </button>
              <button
                @click="selectLang('en')"
                class="flex items-center w-full px-4 py-2 text-sm text-gray-700 hover:bg-indigo-50 hover:text-indigo-600 transition-colors"
                :class="{ 'bg-gray-50 font-bold text-indigo-600': langStore.currentLang === 'en' }"
              >
                <span class="mr-3 text-base">🇺🇸</span> {{ t('nav.english') }}
              </button>
            </div>
          </transition>
        </div>

        <template v-if="authStore.isAuthenticated">
          <div
            class="flex items-center gap-2 text-sm text-gray-700 bg-gray-50 px-3 py-1.5 rounded-full border border-gray-200"
          >
            <User class="w-4 h-4 text-gray-500" />
            <span class="font-medium max-w-[150px] truncate">{{ displayName }}</span>
            <span
              v-if="authStore.isAdmin"
              class="text-[10px] bg-indigo-100 text-indigo-700 px-1 py-0.5 rounded ml-1 font-bold uppercase tracking-wider"
              >{{ t('common.admin') }}</span
            >
          </div>

          <button
            @click="handleLogout"
            class="flex items-center gap-2 px-3 py-2 text-sm font-medium text-gray-600 hover:text-red-600 hover:bg-red-50 rounded-md transition"
            :title="t('auth.logout')"
          >
            <LogOut class="w-4 h-4" />
            <span class="hidden sm:inline">{{ t('auth.logout') }}</span>
          </button>
        </template>

        <template v-else>
          <button
            @click="handleLogin"
            class="flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 rounded-md shadow-sm transition"
          >
            <LogIn class="w-4 h-4" />
            <span>{{ t('auth.login') }}</span>
          </button>
        </template>
      </div>
    </div>
  </header>
</template>

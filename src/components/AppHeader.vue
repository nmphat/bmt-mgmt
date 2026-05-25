<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { useRouter } from 'vue-router'
import { LogOut, Menu, User, Wallet } from 'lucide-vue-next'
import { supabase } from '@/lib/supabase'

const authStore = useAuthStore()
const langStore = useLangStore()
const router = useRouter()

const myDebt = ref(0)
const loadingDebt = ref(false)
const userMenuOpen = ref(false)
let debtFetchToken = 0

const displayName = computed(() => {
  if (authStore.profile?.display_name) {
    return authStore.profile.display_name
  }
  return authStore.user?.email || t.value('common.user')
})

const t = computed(() => langStore.t)

async function fetchMyDebt() {
  const profileId = authStore.profile?.id
  const token = ++debtFetchToken

  if (!authStore.isAuthenticated || !profileId) {
    myDebt.value = 0
    loadingDebt.value = false
    return
  }

  try {
    loadingDebt.value = true
    const { data, error } = await supabase
      .from('view_member_debt_summary')
      .select('total_debt')
      .eq('member_id', profileId)

    if (error) {
      console.warn('Error fetching debt:', error)
      return
    }

    if (token === debtFetchToken && authStore.profile?.id === profileId && authStore.isAuthenticated) {
      myDebt.value = data?.[0]?.total_debt || 0
    }
  } catch (e) {
    console.error('Exception fetching debt:', e)
  } finally {
    if (token === debtFetchToken) {
      loadingDebt.value = false
    }
  }
}

async function handleLogout() {
  userMenuOpen.value = false
  debtFetchToken++
  myDebt.value = 0
  loadingDebt.value = false
  await authStore.signOut()
  router.push('/')
}

function selectLang(lang: 'vi' | 'en') {
  langStore.setLang(lang)
}

const formatCurrency = (value: number) => {
  return new Intl.NumberFormat(langStore.currentLang === 'vi' ? 'vi-VN' : 'en-US', {
    style: 'currency',
    currency: 'VND',
    maximumFractionDigits: 0,
  }).format(value)
}

watch(
  () => authStore.profile?.id,
  (newId) => {
    if (newId) {
      fetchMyDebt()
    } else {
      debtFetchToken++
      myDebt.value = 0
      loadingDebt.value = false
    }
  },
  { immediate: true },
)
</script>

<template>
  <header class="bg-white shadow-sm border-b border-gray-100 sticky top-0 z-50">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-14 flex items-center justify-between">
      <!-- Logo / Title -->
      <router-link to="/" class="flex items-center gap-2 group">
        <div class="bg-indigo-600 text-white p-1.5 rounded-lg group-hover:bg-indigo-700 transition">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="20"
            height="20"
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
        <span class="text-lg font-bold text-gray-900 group-hover:text-indigo-600 transition"
          >Badminton Mgmt</span
        >
      </router-link>

      <!-- Desktop public navigation mirrors the three mobile tabs without exposing login/admin. -->
      <nav class="hidden md:flex items-center gap-6 mx-6">
        <router-link
          to="/"
          active-class="text-indigo-600"
          class="text-sm font-medium text-gray-700 hover:text-indigo-600 transition"
        >
          {{ t('nav.home') }}
        </router-link>
        <router-link
          to="/sessions"
          active-class="text-indigo-600"
          class="text-sm font-medium text-gray-700 hover:text-indigo-600 transition"
        >
          {{ t('nav.sessions') }}
        </router-link>
        <router-link
          to="/members"
          active-class="text-indigo-600"
          class="text-sm font-medium text-gray-700 hover:text-indigo-600 transition"
        >
          {{ t('nav.members') }}
        </router-link>
      </nav>

      <!-- Right Side Actions -->
      <div class="flex items-center gap-2 sm:gap-4">
        <!-- 1. Language Switcher -->
        <button
          @click="selectLang(langStore.currentLang === 'vi' ? 'en' : 'vi')"
          class="flex min-h-11 min-w-11 items-center justify-center gap-1 rounded-md px-2 py-1 text-sm transition hover:bg-gray-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
          :title="langStore.currentLang === 'vi' ? t('nav.switchEn') : t('nav.switchVi')"
          :aria-label="t('shell.languageSwitcher')"
        >
          <span class="text-base leading-none">{{
            langStore.currentLang === 'vi' ? '🇻🇳' : '🇺🇸'
          }}</span>
        </button>

        <!-- 2. Debt Badge (Logged in only) -->
        <div
          v-if="authStore.isAuthenticated"
          class="hidden sm:flex min-h-11 items-center px-3 py-1.5 rounded-full border text-xs font-semibold shadow-sm transition-colors cursor-default"
          :class="
            myDebt > 0
              ? 'bg-red-50 text-red-700 border-red-200'
              : 'bg-green-50 text-green-700 border-green-200'
          "
        >
          <Wallet class="w-3.5 h-3.5 mr-1.5" />
          <span v-if="myDebt > 0">{{ t('debt.prefix') }}: {{ formatCurrency(myDebt) }}</span>
          <span v-else>{{ t('debt.clean') }}</span>
        </div>

        <!-- 3. Authenticated user menu. Guests intentionally get no login link/button. -->
        <template v-if="authStore.isAuthenticated">
          <div class="relative">
            <button
              @click="userMenuOpen = !userMenuOpen"
              class="flex min-h-11 min-w-11 items-center justify-center gap-2 text-sm text-gray-700 transition-colors hover:text-indigo-600 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
              :aria-label="t('shell.openUserMenu')"
              :aria-expanded="userMenuOpen"
              aria-haspopup="menu"
            >
              <div
                class="w-8 h-8 rounded-full bg-indigo-100 flex items-center justify-center border border-indigo-200 text-indigo-700 font-bold"
              >
                {{ displayName.charAt(0).toUpperCase() }}
              </div>
              <Menu class="hidden h-4 w-4 sm:block" aria-hidden="true" />
            </button>

            <!-- Dropdown Menu -->
            <div
              v-if="userMenuOpen"
              class="absolute right-0 z-[60] mt-2 w-56 rounded-md bg-white py-1 shadow-lg ring-1 ring-black ring-opacity-5"
              role="menu"
            >
              <div class="px-4 py-2 border-b border-gray-100">
                <p class="text-sm font-medium text-gray-900 truncate">{{ displayName }}</p>
                <p class="text-xs text-gray-500 truncate">{{ authStore.user?.email }}</p>
              </div>

              <router-link
                v-if="authStore.profile?.id"
                :to="'/member/' + authStore.profile.id"
                class="flex min-h-11 items-center gap-2 px-4 py-2 text-sm text-gray-700 hover:bg-gray-50"
                role="menuitem"
                @click="userMenuOpen = false"
              >
                <User class="h-4 w-4" aria-hidden="true" />
                {{ t('auth.profile') }}
              </router-link>

              <router-link
                v-if="authStore.isAdmin"
                to="/sessions"
                class="block min-h-11 px-4 py-2 text-sm text-gray-700 hover:bg-gray-50"
                role="menuitem"
                @click="userMenuOpen = false"
              >
                {{ t('auth.admin_settings') }}
              </router-link>

              <button
                @click="handleLogout"
                class="flex min-h-11 w-full items-center px-4 py-2 text-left text-sm text-red-600 hover:bg-red-50"
                role="menuitem"
              >
                <LogOut class="w-4 h-4 mr-2" />
                {{ t('auth.logout') }}
              </button>
            </div>
          </div>
        </template>
      </div>
    </div>
  </header>
</template>

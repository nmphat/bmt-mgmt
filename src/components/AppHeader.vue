<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted, watch } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { useRouter } from 'vue-router'
import { LogOut, LogIn, User, Languages, ChevronDown, Wallet } from 'lucide-vue-next'
import { supabase } from '@/lib/supabase'

const authStore = useAuthStore()
const langStore = useLangStore()
const router = useRouter()

const isLangOpen = ref(false)
const langRef = ref<HTMLElement | null>(null)
const myDebt = ref(0)
const loadingDebt = ref(false)

const displayName = computed(() => {
  if (authStore.profile?.display_name) {
    return authStore.profile.display_name
  }
  return authStore.user?.email || t.value('common.user')
})

const t = computed(() => langStore.t)

async function fetchMyDebt() {
  if (!authStore.profile?.id) return

  try {
    loadingDebt.value = true
    const { data, error } = await supabase
      .from('view_member_debt_summary')
      .select('total_debt')
      .eq('member_id', authStore.profile.id)

    if (error) {
      console.warn('Error fetching debt:', error)
      return
    }

    myDebt.value = data?.[0]?.total_debt || 0
  } catch (e) {
    console.error('Exception fetching debt:', e)
  } finally {
    loadingDebt.value = false
  }
}

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
      myDebt.value = 0
    }
  },
  { immediate: true },
)

onMounted(() => {
  document.addEventListener('click', handleClickOutside)
  if (authStore.profile?.id) {
    fetchMyDebt()
  }
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
        <div class="relative" ref="langRef">
          <button
            @click="isLangOpen = !isLangOpen"
            class="flex items-center gap-1.5 px-2 py-1.5 rounded-md border transition-all duration-200 shadow-sm bg-white hover:bg-gray-50"
            :title="langStore.currentLang === 'vi' ? t('nav.switchEn') : t('nav.switchVi')"
          >
            <span class="text-xl leading-none">{{
              langStore.currentLang === 'vi' ? '🇻🇳' : '🇺🇸'
            }}</span>
            <ChevronDown
              class="w-3 h-3 text-gray-400 transition-transform duration-200"
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

        <!-- 2. Debt Badge (Logged in only) -->
        <div
          v-if="authStore.isAuthenticated"
          class="hidden sm:flex items-center px-3 py-1.5 rounded-full border text-xs font-semibold shadow-sm transition-colors cursor-default"
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

        <!-- 3. User Menu / Login -->
        <template v-if="authStore.isAuthenticated">
          <div class="relative group">
            <button
              class="flex items-center gap-2 text-sm text-gray-700 hover:text-indigo-600 transition-colors focus:outline-none"
            >
              <div
                class="w-8 h-8 rounded-full bg-indigo-100 flex items-center justify-center border border-indigo-200 text-indigo-700 font-bold"
              >
                {{ displayName.charAt(0).toUpperCase() }}
              </div>
            </button>

            <!-- Dropdown Menu -->
            <div
              class="absolute right-0 mt-2 w-48 bg-white rounded-md shadow-lg py-1 ring-1 ring-black ring-opacity-5 opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all duration-200 z-[60]"
            >
              <div class="px-4 py-2 border-b border-gray-100">
                <p class="text-sm font-medium text-gray-900 truncate">{{ displayName }}</p>
                <p class="text-xs text-gray-500 truncate">{{ authStore.user?.email }}</p>
              </div>

              <router-link
                to="/profile"
                class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-50"
              >
                {{ t('auth.profile') }}
              </router-link>

              <router-link
                v-if="authStore.isAdmin"
                to="/admin"
                class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-50"
              >
                {{ t('auth.admin_settings') }}
              </router-link>

              <button
                @click="handleLogout"
                class="w-full text-left px-4 py-2 text-sm text-red-600 hover:bg-red-50 flex items-center"
              >
                <LogOut class="w-4 h-4 mr-2" />
                {{ t('auth.logout') }}
              </button>
            </div>
          </div>
        </template>

        <template v-else>
          <button
            @click="handleLogin"
            class="flex items-center gap-2 px-4 py-2 text-sm font-bold text-white bg-indigo-600 hover:bg-indigo-700 rounded-full shadow-sm transition hover:shadow-md"
          >
            <LogIn class="w-4 h-4" />
            <span>{{ t('auth.login') }}</span>
          </button>
        </template>
      </div>
    </div>
  </header>
</template>

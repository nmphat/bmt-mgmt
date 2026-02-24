<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted, watch } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { useRouter } from 'vue-router'
import { LogOut, LogIn, User, Languages, Wallet, Menu, X } from 'lucide-vue-next'
import { supabase } from '@/lib/supabase'

const authStore = useAuthStore()
const langStore = useLangStore()
const router = useRouter()

const myDebt = ref(0)
const loadingDebt = ref(false)
const isMobileMenuOpen = ref(false)

const toggleMobileMenu = () => {
  isMobileMenuOpen.value = !isMobileMenuOpen.value
}

const closeMobileMenu = () => {
  isMobileMenuOpen.value = false
}

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
  if (authStore.profile?.id) {
    fetchMyDebt()
  }
})
</script>

<template>
  <header class="bg-white shadow-sm border-b border-gray-100 sticky top-0 z-50">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
      <!-- Logo / Title -->
      <router-link to="/" class="flex items-center gap-2 group">
        <img
          src="/3pcl-logo.png"
          alt="3PCL Logo"
          class="h-8 w-auto object-contain transition-transform group-hover:scale-105"
        />
        <span class="block text-xl font-bold text-gray-900 group-hover:text-indigo-600 transition"
          >3PCL</span
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
        <button
          @click="selectLang(langStore.currentLang === 'vi' ? 'en' : 'vi')"
          class="flex items-center gap-1 px-2 py-1 rounded-md hover:bg-gray-100 transition text-sm"
          :title="langStore.currentLang === 'vi' ? t('nav.switchEn') : t('nav.switchVi')"
        >
          <span class="text-base leading-none">{{
            langStore.currentLang === 'vi' ? '🇻🇳' : '🇺🇸'
          }}</span>
        </button>

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
          <div class="relative group hidden md:block">
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
                v-if="authStore.profile?.id"
                :to="'/member/' + authStore.profile.id"
                class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-50"
              >
                {{ t('auth.profile') }}
              </router-link>

              <router-link
                v-if="authStore.isAdmin"
                to="/sessions"
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
            class="hidden md:flex items-center gap-2 px-4 py-2 text-sm font-bold text-white bg-indigo-600 hover:bg-indigo-700 rounded-full shadow-sm transition hover:shadow-md"
          >
            <LogIn class="w-4 h-4" />
            <span>{{ t('auth.login') }}</span>
          </button>
        </template>

        <!-- Hamburger Button (Mobile Only) -->
        <button
          @click="toggleMobileMenu"
          class="inline-flex md:hidden items-center justify-center p-2 rounded-md text-gray-700 hover:text-indigo-600 hover:bg-gray-100 transition focus:outline-none"
        >
          <Menu v-if="!isMobileMenuOpen" class="w-6 h-6" />
          <X v-else class="w-6 h-6" />
        </button>
      </div>
    </div>

    <!-- Mobile Menu Overlay -->
    <div v-if="isMobileMenuOpen" class="md:hidden border-t border-gray-100 bg-white">
      <div class="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
        <span class="text-sm font-medium text-gray-500">{{
          t('nav.languague') || 'Language'
        }}</span>
        <button
          @click="selectLang(langStore.currentLang === 'vi' ? 'en' : 'vi')"
          class="flex items-center gap-2 px-3 py-1.5 rounded-md bg-gray-50 hover:bg-gray-100 transition text-sm font-medium"
        >
          <span class="text-lg">{{ langStore.currentLang === 'vi' ? '🇻🇳' : '🇺🇸' }}</span>
          <span>{{ langStore.currentLang === 'vi' ? 'Tiếng Việt' : 'English' }}</span>
        </button>
      </div>
      <div class="px-4 pt-2 pb-6 space-y-1">
        <template v-if="authStore.isAuthenticated">
          <router-link
            to="/"
            @click="closeMobileMenu"
            active-class="bg-indigo-50 text-indigo-600"
            class="block px-3 py-2 rounded-md text-base font-medium text-gray-700 hover:text-indigo-600 hover:bg-gray-50 transition"
          >
            {{ t('nav.home') }}
          </router-link>
          <router-link
            to="/sessions"
            @click="closeMobileMenu"
            active-class="bg-indigo-50 text-indigo-600"
            class="block px-3 py-2 rounded-md text-base font-medium text-gray-700 hover:text-indigo-600 hover:bg-gray-50 transition"
          >
            {{ t('nav.sessions') }}
          </router-link>
          <router-link
            to="/members"
            @click="closeMobileMenu"
            active-class="bg-indigo-50 text-indigo-600"
            class="block px-3 py-2 rounded-md text-base font-medium text-gray-700 hover:text-indigo-600 hover:bg-gray-50 transition"
          >
            {{ t('nav.members') }}
          </router-link>
        </template>
        <template v-else>
          <button
            @click="handleLogin"
            class="w-full flex items-center justify-center gap-2 px-4 py-3 text-base font-bold text-white bg-indigo-600 hover:bg-indigo-700 rounded-xl shadow-sm transition"
          >
            <LogIn class="w-5 h-5" />
            <span>{{ t('auth.login') }}</span>
          </button>
        </template>

        <!-- Debt Badge in Mobile Menu -->
        <div
          v-if="authStore.isAuthenticated"
          class="flex items-center px-3 py-3 mt-4 rounded-lg border text-sm font-semibold shadow-sm transition-colors cursor-default"
          :class="
            myDebt > 0
              ? 'bg-red-50 text-red-700 border-red-200'
              : 'bg-green-50 text-green-700 border-green-200'
          "
        >
          <Wallet class="w-4 h-4 mr-2" />
          <span v-if="myDebt > 0">{{ t('debt.prefix') }}: {{ formatCurrency(myDebt) }}</span>
          <span v-else>{{ t('debt.clean') }}</span>
        </div>

        <!-- Mobile User Profile & Logout -->
        <div class="pt-4 border-t border-gray-100">
          <div class="px-3 py-2">
            <p class="text-base font-medium text-gray-900">{{ displayName }}</p>
            <p class="text-sm font-medium text-gray-500">{{ authStore.user?.email }}</p>
          </div>
          <div class="mt-3 space-y-1">
            <router-link
              v-if="authStore.profile?.id"
              :to="'/member/' + authStore.profile.id"
              @click="closeMobileMenu"
              class="block px-3 py-2 rounded-md text-base font-medium text-gray-700 hover:text-indigo-600 hover:bg-gray-50 transition"
            >
              {{ t('auth.profile') }}
            </router-link>
            <button
              @click="handleLogout"
              class="w-full text-left block px-3 py-2 rounded-md text-base font-medium text-red-600 hover:bg-red-50 transition flex items-center"
            >
              <LogOut class="w-5 h-5 mr-3" />
              {{ t('auth.logout') }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </header>
</template>

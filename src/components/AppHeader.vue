<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { useRouter } from 'vue-router'
import { LogOut, Menu, Settings, User, Wallet } from 'lucide-vue-next'
import { supabase } from '@/lib/supabase'
import Avatar from '@/components/ui/Avatar.vue'

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

    if (
      token === debtFetchToken &&
      authStore.profile?.id === profileId &&
      authStore.isAuthenticated
    ) {
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
  <header
    data-ds="App Header"
    :data-ds-auth="authStore.isAuthenticated ? 'Signed In' : 'Guest'"
    class="sticky top-0 z-50 border-b border-line-divider bg-surface-card/95 px-4 backdrop-blur supports-[backdrop-filter]:bg-surface-card/90 sm:px-6 lg:px-8"
  >
    <div class="mx-auto flex h-14 max-w-[76rem] items-center justify-between">
      <!-- Logo / Title -->
      <router-link
        to="/"
        data-ds="Brand Logo"
        data-ds-state="Default"
        class="group flex items-center gap-2 rounded-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-line-focus focus-visible:ring-offset-2"
      >
        <div
          class="shadow-brand rounded-xl bg-surface-brand p-1.5 text-fg-on-brand transition-colors duration-200 group-hover:bg-fg-brand-strong"
        >
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
        <span
          class="text-lg font-semibold tracking-tight text-fg-primary transition-colors duration-200 group-hover:text-fg-brand"
          >Badminton Mgmt</span
        >
      </router-link>

      <!-- Desktop public navigation mirrors the three mobile tabs without exposing login/admin. -->
      <nav class="hidden md:flex h-14 items-stretch gap-6 mx-6">
        <router-link v-slot="{ href, navigate, isActive, isExactActive }" to="/" custom>
          <a
            :href="href"
            data-ds="Header Nav Link"
            :data-ds-state="isActive ? 'Active' : 'Inactive'"
            :aria-current="isExactActive ? 'page' : undefined"
            class="flex items-center border-b-2 text-sm font-medium transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-line-focus"
            :class="
              isActive
                ? 'text-fg-brand border-line-brand'
                : 'border-transparent text-fg-secondary hover:text-fg-brand'
            "
            @click="navigate"
          >
            {{ t('nav.home') }}
          </a>
        </router-link>
        <router-link v-slot="{ href, navigate, isActive, isExactActive }" to="/sessions" custom>
          <a
            :href="href"
            data-ds="Header Nav Link"
            :data-ds-state="isActive ? 'Active' : 'Inactive'"
            :aria-current="isExactActive ? 'page' : undefined"
            class="flex items-center border-b-2 text-sm font-medium transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-line-focus"
            :class="
              isActive
                ? 'text-fg-brand border-line-brand'
                : 'border-transparent text-fg-secondary hover:text-fg-brand'
            "
            @click="navigate"
          >
            {{ t('nav.sessions') }}
          </a>
        </router-link>
        <router-link v-slot="{ href, navigate, isActive, isExactActive }" to="/members" custom>
          <a
            :href="href"
            data-ds="Header Nav Link"
            :data-ds-state="isActive ? 'Active' : 'Inactive'"
            :aria-current="isExactActive ? 'page' : undefined"
            class="flex items-center border-b-2 text-sm font-medium transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-line-focus"
            :class="
              isActive
                ? 'text-fg-brand border-line-brand'
                : 'border-transparent text-fg-secondary hover:text-fg-brand'
            "
            @click="navigate"
          >
            {{ t('nav.members') }}
          </a>
        </router-link>
      </nav>

      <!-- Right Side Actions -->
      <div class="flex items-center gap-2 sm:gap-4">
        <!-- 1. Language Switcher -->
        <button
          data-ds="Language Toggle"
          :data-ds-lang="langStore.currentLang === 'vi' ? 'VI' : 'EN'"
          @click="selectLang(langStore.currentLang === 'vi' ? 'en' : 'vi')"
          class="flex min-h-11 min-w-11 items-center justify-center gap-1 rounded-xl px-2 text-sm transition-colors duration-200 hover:bg-surface-muted active:scale-95 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-line-focus"
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
          data-ds="Debt Chip"
          :data-ds-state="myDebt > 0 ? 'Debt' : 'Clean'"
          class="hidden sm:flex h-11 cursor-default items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-semibold shadow-sm transition-colors"
          :class="
            myDebt > 0
              ? 'bg-status-danger-subtle text-status-danger-strong border-status-danger-border'
              : 'bg-status-success-subtle text-status-success-strong border-status-success-border'
          "
        >
          <Wallet class="size-3.5" />
          <span v-if="myDebt > 0">{{ t('debt.prefix') }}: {{ formatCurrency(myDebt) }}</span>
          <span v-else>{{ t('debt.clean') }}</span>
        </div>

        <!-- 3. Authenticated user menu. Guests intentionally get no login link/button. -->
        <template v-if="authStore.isAuthenticated">
          <div class="relative">
            <button
              data-ds="User Menu Trigger"
              data-ds-state="Default"
              @click="userMenuOpen = !userMenuOpen"
              class="flex min-h-11 min-w-11 items-center justify-center gap-2 text-sm text-fg-secondary transition-colors duration-200 hover:text-fg-brand active:scale-95 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-line-focus"
              :aria-label="t('shell.openUserMenu')"
              :aria-expanded="userMenuOpen"
              aria-haspopup="menu"
            >
              <Avatar size="32" :initial="displayName.charAt(0).toUpperCase()" />
              <Menu class="hidden size-4 text-fg-secondary sm:block" aria-hidden="true" />
            </button>

            <!-- Dropdown Menu -->
            <div
              v-if="userMenuOpen"
              data-ds="User Menu"
              data-ds-style="Default"
              class="absolute right-0 z-[60] mt-2 w-56 rounded-lg border border-line-subtle bg-surface-card py-1 shadow-lg"
              role="menu"
            >
              <div class="px-4 py-2 border-b border-line-divider">
                <p class="text-sm font-medium text-fg-primary truncate">{{ displayName }}</p>
                <p class="text-xs text-fg-muted truncate">{{ authStore.user?.email }}</p>
              </div>

              <router-link
                v-if="authStore.profile?.id"
                :to="'/member/' + authStore.profile.id"
                data-ds="Menu Item"
                data-ds-tone="Default"
                class="flex h-11 w-full items-center gap-2 px-4 py-2 text-sm text-fg-secondary transition-colors duration-150 hover:bg-surface-subtle focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-line-focus"
                role="menuitem"
                @click="userMenuOpen = false"
              >
                <User class="size-4" aria-hidden="true" />
                {{ t('auth.profile') }}
              </router-link>

              <router-link
                v-if="authStore.isAdmin"
                to="/settings"
                data-ds="Menu Item"
                data-ds-tone="Default"
                class="flex h-11 w-full items-center gap-2 px-4 py-2 text-sm text-fg-secondary transition-colors duration-150 hover:bg-surface-subtle focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-line-focus"
                role="menuitem"
                @click="userMenuOpen = false"
              >
                <Settings class="size-4" aria-hidden="true" />
                {{ t('auth.admin_settings') }}
              </router-link>

              <button
                data-ds="Menu Item"
                data-ds-tone="Danger"
                @click="handleLogout"
                class="flex h-11 w-full items-center gap-2 px-4 py-2 text-left text-sm text-status-danger-action transition-colors duration-150 hover:bg-status-danger-subtle focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-line-focus"
                role="menuitem"
              >
                <LogOut class="size-4" />
                {{ t('auth.logout') }}
              </button>
            </div>
          </div>
        </template>
      </div>
    </div>
  </header>
</template>

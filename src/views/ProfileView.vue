<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { useBankConfig } from '@/composables/useBankConfig'
import { supabase } from '@/lib/supabase'
import { formatCurrency } from '@/utils/formatters'
import {
  LogOut,
  LogIn,
  User,
  CreditCard,
  CheckCircle2,
  Circle,
  Trash2,
  Plus,
  ChevronRight,
  Loader2,
  AlertTriangle,
} from 'lucide-vue-next'

const authStore = useAuthStore()
const langStore = useLangStore()
const router = useRouter()
const t = computed(() => langStore.t)

const {
  configs,
  activeBank,
  loading: bankLoading,
  usingFallback,
  setActive,
  addConfig,
  removeConfig,
} = useBankConfig()

// ── Debt overview ──────────────────────────────────────────
const myDebt = ref(0)
const unpaidCount = ref(0)
const debtLoading = ref(false)

async function fetchDebt() {
  if (!authStore.profile?.id) return
  debtLoading.value = true
  try {
    const { data } = await supabase
      .from('view_member_debt_summary')
      .select('total_debt, unpaid_session_count')
      .eq('member_id', authStore.profile.id)
      .single()
    if (data) {
      myDebt.value = data.total_debt ?? 0
      unpaidCount.value = data.unpaid_session_count ?? 0
    }
  } finally {
    debtLoading.value = false
  }
}

onMounted(() => {
  if (authStore.isAuthenticated) fetchDebt()
})

// ── Logout ─────────────────────────────────────────────────
const loggingOut = ref(false)
async function handleLogout() {
  loggingOut.value = true
  await authStore.signOut()
  router.push('/login')
}

// ── Bank config form ───────────────────────────────────────
const showAddForm = ref(false)
const addLoading = ref(false)
const bankForm = ref({ bank_id: '', account_number: '', account_name: '', template: 'compact2' })
const bankFormError = ref('')

async function submitAddBank() {
  bankFormError.value = ''
  if (!bankForm.value.bank_id || !bankForm.value.account_number || !bankForm.value.account_name) {
    bankFormError.value = 'Vui lòng điền đầy đủ thông tin.'
    return
  }
  addLoading.value = true
  const { error } = await addConfig({
    bank_id: bankForm.value.bank_id.toUpperCase().trim(),
    account_number: bankForm.value.account_number.trim(),
    account_name: bankForm.value.account_name.trim(),
    template: bankForm.value.template.trim() || 'compact2',
  })
  addLoading.value = false
  if (error) {
    bankFormError.value = 'Lỗi lưu. Thử lại.'
  } else {
    bankForm.value = { bank_id: '', account_number: '', account_name: '', template: 'compact2' }
    showAddForm.value = false
  }
}

async function handleSetActive(id: string) {
  await setActive(id)
}

async function handleDelete(id: string) {
  if (!confirm(t.value('profile.deleteConfirm'))) return
  await removeConfig(id)
}

const displayName = computed(
  () => authStore.profile?.display_name || authStore.user?.email || t.value('common.user'),
)
const avatarChar = computed(() => displayName.value.charAt(0).toUpperCase())
const isAdmin = computed(() => authStore.isAdmin)
</script>

<template>
  <div class="max-w-2xl mx-auto px-4 py-6 space-y-5">
    <!-- ── Guest state ─────────────────────────────────── -->
    <template v-if="!authStore.isAuthenticated">
      <div class="flex flex-col items-center justify-center py-20 text-center space-y-4">
        <User class="w-16 h-16 text-gray-300" />
        <p class="text-gray-500 text-base">{{ t('profile.guestPrompt') }}</p>
        <router-link
          to="/login"
          class="inline-flex items-center gap-2 px-6 py-3 bg-indigo-600 text-white font-bold rounded-xl shadow-sm hover:bg-indigo-700 transition"
        >
          <LogIn class="w-4 h-4" />
          {{ t('auth.login') }}
        </router-link>
      </div>
    </template>

    <template v-else>
      <!-- ── User card ──────────────────────────────────── -->
      <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6">
        <div class="flex items-center gap-4">
          <!-- Avatar -->
          <div
            class="w-16 h-16 rounded-full bg-indigo-100 border-2 border-indigo-200 flex items-center justify-center text-2xl font-extrabold text-indigo-700 flex-shrink-0"
          >
            {{ avatarChar }}
          </div>
          <div class="flex-1 min-w-0">
            <h2 class="text-xl font-bold text-gray-900 truncate">{{ displayName }}</h2>
            <p class="text-sm text-gray-500 truncate">{{ authStore.user?.email }}</p>
            <span
              class="inline-block mt-1 px-2 py-0.5 text-xs font-semibold rounded-full"
              :class="isAdmin ? 'bg-indigo-100 text-indigo-700' : 'bg-gray-100 text-gray-600'"
            >
              {{ isAdmin ? t('common.admin') : t('common.member') }}
            </span>
          </div>
        </div>
      </div>

      <!-- ── Debt overview ──────────────────────────────── -->
      <div class="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
        <div class="px-5 py-4 border-b border-gray-100">
          <h3 class="text-sm font-semibold text-gray-500 uppercase tracking-wider">
            {{ t('profile.myDebt') }}
          </h3>
        </div>
        <div class="p-5">
          <div v-if="debtLoading" class="flex items-center gap-2 text-gray-400">
            <Loader2 class="w-4 h-4 animate-spin" />
            {{ t('common.loading') }}
          </div>
          <div v-else class="flex items-center justify-between">
            <div>
              <div
                class="text-2xl font-extrabold"
                :class="myDebt > 0 ? 'text-red-600' : 'text-green-600'"
              >
                {{ myDebt > 0 ? formatCurrency(myDebt) : t('profile.debtFree') }}
              </div>
              <div v-if="myDebt > 0" class="text-sm text-gray-500 mt-0.5">
                {{ t('profile.unpaidSessions', { count: unpaidCount }) }}
              </div>
            </div>
            <router-link
              v-if="authStore.profile?.id"
              :to="'/member/' + authStore.profile.id"
              class="flex items-center gap-1 text-sm font-medium text-indigo-600 hover:text-indigo-700"
            >
              {{ t('profile.viewHistory') }}
              <ChevronRight class="w-4 h-4" />
            </router-link>
          </div>
        </div>
      </div>

      <!-- ── Bank config (admin only) ───────────────────── -->
      <div
        v-if="isAdmin"
        class="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden"
      >
        <div class="px-5 py-4 border-b border-gray-100 flex items-center justify-between">
          <div class="flex items-center gap-2">
            <CreditCard class="w-4 h-4 text-gray-400" />
            <h3 class="text-sm font-semibold text-gray-500 uppercase tracking-wider">
              {{ t('profile.bankConfig') }}
            </h3>
          </div>
          <button
            @click="showAddForm = !showAddForm"
            class="flex items-center gap-1 text-sm font-medium text-indigo-600 hover:text-indigo-700 transition"
          >
            <Plus class="w-4 h-4" />
            {{ t('profile.addBank') }}
          </button>
        </div>

        <!-- Add form -->
        <Transition
          enter-active-class="transition-all duration-200 ease-out"
          enter-from-class="opacity-0 -translate-y-1"
          enter-to-class="opacity-100 translate-y-0"
          leave-active-class="transition-all duration-150 ease-in"
          leave-from-class="opacity-100 translate-y-0"
          leave-to-class="opacity-0 -translate-y-1"
        >
          <div v-if="showAddForm" class="px-5 py-4 bg-gray-50 border-b border-gray-100 space-y-3">
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="block text-xs font-medium text-gray-600 mb-1">{{
                  t('profile.bankId')
                }}</label>
                <input
                  v-model="bankForm.bank_id"
                  placeholder="TPB, MB, VCB..."
                  class="w-full px-3 py-2 text-sm border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500/30 focus:border-indigo-400 uppercase"
                />
              </div>
              <div>
                <label class="block text-xs font-medium text-gray-600 mb-1">{{
                  t('profile.templateLabel')
                }}</label>
                <input
                  v-model="bankForm.template"
                  placeholder="compact2"
                  class="w-full px-3 py-2 text-sm border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500/30 focus:border-indigo-400"
                />
              </div>
              <div>
                <label class="block text-xs font-medium text-gray-600 mb-1">{{
                  t('profile.accountNumber')
                }}</label>
                <input
                  v-model="bankForm.account_number"
                  placeholder="10003392871"
                  class="w-full px-3 py-2 text-sm border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500/30 focus:border-indigo-400"
                />
              </div>
              <div>
                <label class="block text-xs font-medium text-gray-600 mb-1">{{
                  t('profile.accountName')
                }}</label>
                <input
                  v-model="bankForm.account_name"
                  placeholder="NGUYEN VAN A"
                  class="w-full px-3 py-2 text-sm border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500/30 focus:border-indigo-400 uppercase"
                />
              </div>
            </div>
            <p v-if="bankFormError" class="text-xs text-red-600 flex items-center gap-1">
              <AlertTriangle class="w-3.5 h-3.5" />{{ bankFormError }}
            </p>
            <div class="flex gap-2 justify-end">
              <button
                @click="showAddForm = false"
                class="px-4 py-2 text-sm text-gray-600 hover:bg-gray-200 rounded-lg transition"
              >
                {{ t('common.cancel') }}
              </button>
              <button
                @click="submitAddBank"
                :disabled="addLoading"
                class="flex items-center gap-1.5 px-4 py-2 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 rounded-lg disabled:opacity-50 transition"
              >
                <Loader2 v-if="addLoading" class="w-3.5 h-3.5 animate-spin" />
                {{ t('profile.saveBank') }}
              </button>
            </div>
          </div>
        </Transition>

        <div class="divide-y divide-gray-100">
          <!-- Fallback notice when no DB rows -->
          <div v-if="usingFallback" class="px-5 py-4">
            <div class="flex items-start gap-3 p-3 bg-amber-50 rounded-xl border border-amber-200">
              <AlertTriangle class="w-4 h-4 text-amber-500 flex-shrink-0 mt-0.5" />
              <div>
                <p class="text-sm font-medium text-amber-800">{{ t('profile.noBank') }}</p>
                <p class="text-xs text-amber-600 mt-0.5">{{ t('profile.fallbackNote') }}</p>
                <div class="mt-2 text-xs text-amber-700 space-y-0.5">
                  <div><span class="font-medium">Bank:</span> TPB (TPBank)</div>
                  <div><span class="font-medium">STK:</span> 10003392871</div>
                </div>
              </div>
            </div>
          </div>

          <!-- Bank config rows -->
          <div v-for="config in configs" :key="config.id" class="px-5 py-4 flex items-center gap-3">
            <!-- Active indicator -->
            <button
              @click="handleSetActive(config.id)"
              class="flex-shrink-0 transition hover:scale-110"
              :title="t('profile.activateBank')"
            >
              <CheckCircle2 v-if="config.is_active" class="w-5 h-5 text-green-500" />
              <Circle v-else class="w-5 h-5 text-gray-300 hover:text-indigo-400" />
            </button>

            <!-- Bank info -->
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2 flex-wrap">
                <span class="font-bold text-gray-900 text-sm">{{ config.bank_id }}</span>
                <span
                  v-if="config.is_active"
                  class="px-1.5 py-0.5 text-[10px] font-bold rounded-full bg-green-100 text-green-700"
                >
                  {{ t('profile.activeLabel') }}
                </span>
              </div>
              <p class="text-xs text-gray-500 truncate">
                {{ config.account_number }} · {{ config.account_name }}
              </p>
            </div>

            <!-- Delete -->
            <button
              @click="handleDelete(config.id)"
              class="flex-shrink-0 p-1.5 text-gray-400 hover:text-red-500 hover:bg-red-50 rounded-lg transition"
            >
              <Trash2 class="w-4 h-4" />
            </button>
          </div>
        </div>

        <div v-if="bankLoading" class="px-5 py-3 text-xs text-gray-400 flex items-center gap-2">
          <Loader2 class="w-3.5 h-3.5 animate-spin" /> {{ t('common.loading') }}
        </div>
      </div>

      <!-- ── Logout ──────────────────────────────────────── -->
      <div class="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
        <button
          @click="handleLogout"
          :disabled="loggingOut"
          class="w-full flex items-center justify-between px-5 py-4 text-red-600 hover:bg-red-50 transition disabled:opacity-50"
        >
          <div class="flex items-center gap-3">
            <LogOut class="w-5 h-5" />
            <span class="font-medium">{{ t('auth.logout') }}</span>
          </div>
          <Loader2 v-if="loggingOut" class="w-4 h-4 animate-spin" />
        </button>
      </div>

      <!-- Bottom spacer for BottomNav on mobile -->
      <div class="h-2" />
    </template>
  </div>
</template>

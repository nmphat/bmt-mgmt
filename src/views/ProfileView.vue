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
  TriangleAlert,
} from 'lucide-vue-next'
import Alert from '@/components/ui/Alert.vue'
import Avatar from '@/components/ui/Avatar.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import FieldMessage from '@/components/ui/FieldMessage.vue'
import FormField from '@/components/ui/FormField.vue'
import IconButton from '@/components/ui/IconButton.vue'
import Input from '@/components/ui/Input.vue'
import RoleBadge from '@/components/ui/RoleBadge.vue'
import SectionHeader from '@/components/ui/SectionHeader.vue'

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
      <EmptyState :icon="User">
        {{ t('profile.guestPrompt') }}
        <template #action>
          <Button as="RouterLink" to="/login" size="Large" variant="Primary" :leading-icon="LogIn">
            {{ t('auth.login') }}
          </Button>
        </template>
      </EmptyState>
    </template>

    <template v-else>
      <!-- ── User card ──────────────────────────────────── -->
      <div
        class="flex items-center gap-4 rounded-xl border border-line-divider bg-surface-card p-6 shadow-sm"
      >
        <Avatar size="64" :initial="avatarChar" />
        <div class="flex min-w-0 flex-1 flex-col gap-1">
          <h2 class="truncate text-xl font-bold text-fg-primary">{{ displayName }}</h2>
          <p class="truncate text-sm text-fg-muted">{{ authStore.user?.email }}</p>
          <RoleBadge :role="isAdmin ? 'Admin' : 'Member'" size="Small" class="self-start" />
        </div>
      </div>

      <!-- ── Debt overview ──────────────────────────────── -->
      <div class="overflow-hidden rounded-xl border border-line-divider bg-surface-card shadow-sm">
        <SectionHeader :title="t('profile.myDebt')" :level="3" />
        <div class="p-5">
          <div v-if="debtLoading" class="flex items-center gap-2 text-sm text-fg-disabled">
            <Loader2 class="size-4 animate-spin" />
            {{ t('common.loading') }}
          </div>
          <div v-else class="flex items-center justify-between">
            <div>
              <div
                class="text-xl font-bold"
                :class="myDebt > 0 ? 'text-fg-danger' : 'text-fg-success'"
              >
                {{ myDebt > 0 ? formatCurrency(myDebt) : t('profile.debtFree') }}
              </div>
              <div v-if="myDebt > 0" class="text-sm text-fg-muted mt-0.5">
                {{ t('profile.unpaidSessions', { count: unpaidCount }) }}
              </div>
            </div>
            <Button
              v-if="authStore.profile?.id"
              as="RouterLink"
              :to="'/member/' + authStore.profile.id"
              size="Small"
              variant="Ghost"
              :trailing-icon="ChevronRight"
            >
              {{ t('profile.viewHistory') }}
            </Button>
          </div>
        </div>
      </div>

      <!-- ── Bank config (admin only) ───────────────────── -->
      <div
        v-if="isAdmin"
        class="overflow-hidden rounded-xl border border-line-divider bg-surface-card shadow-sm"
      >
        <SectionHeader :icon="CreditCard" :title="t('profile.bankConfig')" :level="3">
          <template #actions>
            <Button
              size="Default"
              variant="Ghost"
              :leading-icon="Plus"
              @click="showAddForm = !showAddForm"
            >
              {{ t('profile.addBank') }}
            </Button>
          </template>
        </SectionHeader>

        <!-- Add form -->
        <Transition
          enter-active-class="transition-all duration-200 ease-out"
          enter-from-class="opacity-0 -translate-y-1"
          enter-to-class="opacity-100 translate-y-0"
          leave-active-class="transition-all duration-150 ease-in"
          leave-from-class="opacity-100 translate-y-0"
          leave-to-class="opacity-0 -translate-y-1"
        >
          <div
            v-if="showAddForm"
            class="space-y-3 border-b border-line-divider bg-surface-subtle px-5 py-4"
          >
            <div class="grid grid-cols-2 gap-3">
              <FormField :label="t('profile.bankId')" label-style="Small" v-slot="{ controlProps }">
                <Input
                  v-model="bankForm.bank_id"
                  v-bind="controlProps"
                  class="uppercase"
                  placeholder="TPB, MB, VCB..."
                />
              </FormField>
              <FormField
                :label="t('profile.templateLabel')"
                label-style="Small"
                v-slot="{ controlProps }"
              >
                <Input v-model="bankForm.template" v-bind="controlProps" placeholder="compact2" />
              </FormField>
              <FormField
                :label="t('profile.accountNumber')"
                label-style="Small"
                v-slot="{ controlProps }"
              >
                <Input
                  v-model="bankForm.account_number"
                  v-bind="controlProps"
                  placeholder="10003392871"
                />
              </FormField>
              <FormField
                :label="t('profile.accountName')"
                label-style="Small"
                v-slot="{ controlProps }"
              >
                <Input
                  v-model="bankForm.account_name"
                  v-bind="controlProps"
                  class="uppercase"
                  placeholder="NGUYEN VAN A"
                />
              </FormField>
            </div>
            <FieldMessage v-if="bankFormError" tone="Error" size="Small" :icon="TriangleAlert">
              {{ bankFormError }}
            </FieldMessage>
            <div class="flex gap-2 justify-end">
              <Button variant="Ghost" @click="showAddForm = false">
                {{ t('common.cancel') }}
              </Button>
              <Button :disabled="addLoading" :loading="addLoading" @click="submitAddBank">
                {{ t('profile.saveBank') }}
              </Button>
            </div>
          </div>
        </Transition>

        <div>
          <!-- Fallback notice when no DB rows -->
          <div v-if="usingFallback" class="border-b border-line-subtle px-5 py-4 last:border-b-0">
            <Alert tone="Warning" :icon="TriangleAlert">
              <p class="font-bold">{{ t('profile.noBank') }}</p>
              <p>{{ t('profile.fallbackNote') }}</p>
              <div class="space-y-0.5 text-xs">
                <div><span class="font-medium">Bank:</span> TPB (TPBank)</div>
                <div><span class="font-medium">STK:</span> 10003392871</div>
              </div>
            </Alert>
          </div>

          <!-- Bank config rows -->
          <div
            v-for="config in configs"
            :key="config.id"
            class="flex items-center gap-3 border-b border-line-subtle px-5 py-4 last:border-b-0"
          >
            <!-- Active indicator -->
            <button
              @click="handleSetActive(config.id)"
              class="shrink-0 transition hover:scale-110 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-line-focus focus-visible:ring-offset-2"
              :title="t('profile.activateBank')"
            >
              <CheckCircle2 v-if="config.is_active" class="size-5 text-fg-success-soft" />
              <Circle v-else class="size-5 text-fg-faint hover:text-fg-brand" />
            </button>

            <!-- Bank info -->
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2 flex-wrap">
                <span class="font-bold text-fg-primary text-sm">{{ config.bank_id }}</span>
                <Badge v-if="config.is_active" size="Small" tone="Success">
                  {{ t('profile.activeLabel') }}
                </Badge>
              </div>
              <p class="text-xs text-fg-muted truncate">
                {{ config.account_number }} · {{ config.account_name }}
              </p>
            </div>

            <!-- Delete -->
            <IconButton
              :icon="Trash2"
              :label="t('settings.deleteBank')"
              size="Small"
              shape="Square"
              variant="Ghost"
              @click="handleDelete(config.id)"
            />
          </div>
        </div>

        <div v-if="bankLoading" class="flex items-center gap-2 px-5 py-3 text-xs text-fg-disabled">
          <Loader2 class="size-3.5 animate-spin" /> {{ t('common.loading') }}
        </div>
      </div>

      <!-- ── Logout ──────────────────────────────────────── -->
      <div class="overflow-hidden rounded-xl border border-line-divider bg-surface-card shadow-sm">
        <button
          @click="handleLogout"
          :disabled="loggingOut"
          class="flex w-full items-center justify-between px-5 py-4 text-status-danger-action transition hover:bg-status-danger-subtle focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-line-focus disabled:cursor-not-allowed disabled:opacity-50"
        >
          <div class="flex items-center gap-3">
            <LogOut class="size-5" />
            <span class="font-medium">{{ t('auth.logout') }}</span>
          </div>
          <Loader2 v-if="loggingOut" class="size-4 animate-spin" />
        </button>
      </div>

      <!-- Bottom spacer for BottomNav on mobile -->
      <div class="h-2" />
    </template>
  </div>
</template>

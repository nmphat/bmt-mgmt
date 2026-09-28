<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import {
  ChevronLeft,
  Circle,
  CircleCheck,
  CreditCard,
  Loader2,
  Plus,
  Trash2,
  X,
} from 'lucide-vue-next'
import { DEFAULT_BANK_CONFIG, type BankConfig, type ShuttleType } from '@/types'
import { useBankConfigStore } from '@/stores/bankConfig'
import { useShuttleTypes } from '@/composables/useShuttleTypes'
import { formatCurrency } from '@/utils/formatters'
import { useLangStore } from '@/stores/lang'
import { useToast } from 'vue-toastification'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import FormField from '@/components/ui/FormField.vue'
import IconButton from '@/components/ui/IconButton.vue'
import Input from '@/components/ui/Input.vue'
import PageHeader from '@/components/ui/PageHeader.vue'
import SectionHeader from '@/components/ui/SectionHeader.vue'

const langStore = useLangStore()
const bankConfigStore = useBankConfigStore()
const toast = useToast()
const t = computed(() => langStore.t)
const configs = computed(() => bankConfigStore.configs)

const showAddForm = ref(false)
const saving = ref(false)
const activeActionId = ref<string | null>(null)

const form = reactive({
  bank_id: DEFAULT_BANK_CONFIG.bank_id,
  account_number: DEFAULT_BANK_CONFIG.account_number,
  account_name: DEFAULT_BANK_CONFIG.account_name,
  template: DEFAULT_BANK_CONFIG.template,
})

onMounted(async () => {
  try {
    await bankConfigStore.fetchConfigs(true)
  } catch (error) {
    console.error('Error loading bank config:', error)
    toast.error(t.value('settings.loadError'))
  }
})

function resetForm() {
  form.bank_id = DEFAULT_BANK_CONFIG.bank_id
  form.account_number = DEFAULT_BANK_CONFIG.account_number
  form.account_name = DEFAULT_BANK_CONFIG.account_name
  form.template = DEFAULT_BANK_CONFIG.template
}

function toggleAddForm() {
  showAddForm.value = !showAddForm.value
  if (showAddForm.value) resetForm()
}

async function handleAddBank() {
  if (!form.bank_id.trim() || !form.account_number.trim() || !form.account_name.trim()) {
    toast.error(t.value('settings.requiredError'))
    return
  }

  try {
    saving.value = true
    await bankConfigStore.createConfig({
      bank_id: form.bank_id,
      account_number: form.account_number,
      account_name: form.account_name,
      template: form.template || DEFAULT_BANK_CONFIG.template,
      is_active: configs.value.length === 0,
    })
    toast.success(t.value('settings.saveSuccess'))
    showAddForm.value = false
    resetForm()
  } catch (error) {
    console.error('Error saving bank config:', error)
    toast.error(t.value('settings.saveError'))
  } finally {
    saving.value = false
  }
}

async function handleSetDefault(config: BankConfig) {
  if (config.is_active) return

  try {
    activeActionId.value = config.id
    await bankConfigStore.setDefault(config.id)
    toast.success(t.value('settings.defaultSuccess'))
  } catch (error) {
    console.error('Error setting default bank:', error)
    toast.error(t.value('settings.defaultError'))
  } finally {
    activeActionId.value = null
  }
}

async function handleDeleteBank(config: BankConfig) {
  if (!window.confirm(t.value('settings.deleteConfirm'))) return

  try {
    activeActionId.value = config.id
    await bankConfigStore.deleteConfig(config)
    toast.success(t.value('settings.deleteSuccess'))
  } catch (error) {
    console.error('Error deleting bank config:', error)
    toast.error(t.value('settings.deleteError'))
  } finally {
    activeActionId.value = null
  }
}

// Shuttle types
const {
  types: shuttleTypes,
  loading: shuttleLoading,
  fetchTypes,
  addType,
  toggleActive,
} = useShuttleTypes()
const showShuttleForm = ref(false)
const shuttleForm = reactive({
  name: '',
  tube_price: 0,
  per_tube: 12,
})

onMounted(async () => {
  try {
    await fetchTypes()
  } catch (error) {
    console.error('Error loading shuttle types:', error)
  }
})

async function handleAddShuttleType() {
  try {
    await addType({
      name: shuttleForm.name,
      tube_price: shuttleForm.tube_price,
      per_tube: shuttleForm.per_tube,
      is_active: true,
    })
    shuttleForm.name = ''
    shuttleForm.tube_price = 0
    shuttleForm.per_tube = 12
    showShuttleForm.value = false
    toast.success(t.value('common.save'))
  } catch (error: any) {
    toast.error(error.message || t.value('shuttle.addError'))
  }
}

async function handleToggleShuttleActive(st: ShuttleType) {
  try {
    await toggleActive(st)
  } catch (error: any) {
    toast.error(error.message || 'Error updating shuttle type')
  }
}
</script>

<template>
  <div class="mx-auto max-w-3xl px-4 py-6 sm:px-6 lg:px-8">
    <div class="mb-6">
      <Button as="RouterLink" to="/" size="Default" variant="Ghost" :leading-icon="ChevronLeft">
        {{ t('common.backToHome') }}
      </Button>
    </div>

    <section class="rounded-xl border border-line-divider bg-surface-card p-4 shadow-sm sm:p-6">
      <PageHeader
        layout="Icon Title"
        :icon="CreditCard"
        :title="t('settings.title')"
        :subtitle="t('settings.subtitle')"
        :level="1"
        class="mb-6"
      />

      <div class="overflow-hidden rounded-xl border border-line-divider bg-surface-card shadow-sm">
        <SectionHeader :icon="CreditCard" :title="t('settings.paymentTitle')">
          <template #actions>
            <Button
              size="Default"
              variant="Ghost"
              :leading-icon="showAddForm ? X : Plus"
              @click="toggleAddForm"
            >
              {{ t('settings.addBank') }}
            </Button>
          </template>
        </SectionHeader>

        <form
          v-if="showAddForm"
          class="grid gap-3 border-b border-line-divider bg-surface-subtle px-5 py-4 sm:grid-cols-2"
          @submit.prevent="handleAddBank"
        >
          <FormField :label="t('settings.bank')" label-style="Caps" v-slot="{ controlProps }">
            <Input
              v-model="form.bank_id"
              v-bind="controlProps"
              size="Default"
              class="uppercase"
              placeholder="TPB"
              required
            />
          </FormField>

          <FormField
            :label="t('settings.accountNumber')"
            label-style="Caps"
            v-slot="{ controlProps }"
          >
            <Input
              v-model="form.account_number"
              v-bind="controlProps"
              size="Default"
              placeholder="10003392871"
              required
            />
          </FormField>

          <FormField
            :label="t('settings.accountName')"
            label-style="Caps"
            v-slot="{ controlProps }"
          >
            <Input
              v-model="form.account_name"
              v-bind="controlProps"
              size="Default"
              class="uppercase"
              placeholder="CLB CAU LONG BMT"
              required
            />
          </FormField>

          <FormField :label="t('settings.qrTemplate')" label-style="Caps" v-slot="{ controlProps }">
            <Input
              v-model="form.template"
              v-bind="controlProps"
              size="Default"
              placeholder="compact2"
            />
          </FormField>

          <div class="sm:col-span-2">
            <Button
              type="submit"
              size="Default"
              :disabled="saving"
              :loading="saving"
              class="w-full sm:w-auto"
            >
              {{ t('settings.saveBank') }}
            </Button>
          </div>
        </form>

        <EmptyState v-if="bankConfigStore.loading" align="Left" size="Small">
          {{ t('common.loading') }}
        </EmptyState>
        <EmptyState v-else-if="configs.length === 0" align="Left" size="Small">
          {{ t('settings.noBanks') }}
        </EmptyState>
        <div v-else>
          <div
            v-for="config in configs"
            :key="config.id"
            class="flex items-center gap-3 border-b border-line-subtle px-5 py-4 last:border-b-0"
          >
            <button
              type="button"
              class="shrink-0 transition hover:scale-110 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-line-focus focus-visible:ring-offset-2 disabled:cursor-not-allowed"
              :title="t('settings.setDefault')"
              :aria-label="t('settings.setDefault')"
              :disabled="activeActionId === config.id"
              @click="handleSetDefault(config)"
            >
              <Loader2
                v-if="activeActionId === config.id"
                class="size-5 animate-spin text-fg-brand"
                aria-hidden="true"
              />
              <CircleCheck
                v-else-if="config.is_active"
                class="size-5 text-fg-success-soft"
                aria-hidden="true"
              />
              <Circle v-else class="size-5 text-fg-faint hover:text-fg-brand" aria-hidden="true" />
            </button>

            <div class="min-w-0 flex-1">
              <div class="flex flex-wrap items-center gap-2">
                <span class="text-sm font-bold text-fg-primary">{{ config.bank_id }}</span>
                <Badge v-if="config.is_active" size="Small" tone="Success">
                  {{ t('settings.inUse') }}
                </Badge>
              </div>
              <p class="truncate text-xs text-fg-muted">
                {{ config.account_number }} · {{ config.account_name }}
              </p>
            </div>

            <IconButton
              :icon="Trash2"
              :label="t('settings.deleteBank')"
              :title="t('settings.deleteBank')"
              size="Small"
              shape="Square"
              variant="Ghost"
              :disabled="activeActionId === config.id"
              @click="handleDeleteBank(config)"
            />
          </div>
        </div>
      </div>

      <p class="mt-4 text-sm leading-6 text-fg-secondary">
        {{ t('settings.qrNote') }}
      </p>
    </section>

    <!-- Shuttle Types Catalogue -->
    <section class="mt-6 rounded-xl border border-line-divider bg-surface-card shadow-sm">
      <SectionHeader variant="Plain Title" :title="t('shuttle.catalogTitle')">
        <template #actions>
          <Button
            size="Default"
            variant="Ghost"
            :leading-icon="showShuttleForm ? X : Plus"
            @click="showShuttleForm = !showShuttleForm"
          >
            {{ t('shuttle.addType') }}
          </Button>
        </template>
      </SectionHeader>

      <form
        v-if="showShuttleForm"
        class="grid gap-3 border-b border-line-divider bg-surface-subtle px-5 py-4 sm:grid-cols-2"
        @submit.prevent="handleAddShuttleType"
      >
        <FormField :label="t('shuttle.type')" label-style="Caps" v-slot="{ controlProps }">
          <Input v-model="shuttleForm.name" v-bind="controlProps" size="Default" required />
        </FormField>
        <FormField :label="t('shuttle.tubePrice')" label-style="Caps" v-slot="{ controlProps }">
          <Input
            v-model.number="shuttleForm.tube_price"
            v-bind="controlProps"
            size="Default"
            type="number"
            min="0"
            step="1000"
            required
          />
        </FormField>
        <FormField :label="t('shuttle.perTube')" label-style="Caps" v-slot="{ controlProps }">
          <Input
            v-model.number="shuttleForm.per_tube"
            v-bind="controlProps"
            size="Default"
            type="number"
            min="1"
            required
          />
        </FormField>
        <div class="flex items-end">
          <Button type="submit" size="Default" class="w-full sm:w-auto">
            {{ t('common.save') }}
          </Button>
        </div>
      </form>

      <EmptyState v-if="shuttleLoading" align="Left" size="Small">
        {{ t('common.loading') }}
      </EmptyState>
      <EmptyState v-else-if="shuttleTypes.length === 0" align="Left" size="Small">
        {{ t('shuttle.catalogEmpty') }}
      </EmptyState>
      <div v-else>
        <div
          v-for="st in shuttleTypes"
          :key="st.id"
          class="flex items-center gap-3 border-b border-line-subtle px-5 py-4 last:border-b-0"
        >
          <button
            type="button"
            class="inline-flex min-h-11 min-w-11 shrink-0 items-center justify-center transition hover:scale-110 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-line-focus focus-visible:ring-offset-2"
            :title="st.is_active ? t('shuttle.active') : t('shuttle.inactive')"
            :aria-label="st.is_active ? t('shuttle.active') : t('shuttle.inactive')"
            @click="handleToggleShuttleActive(st)"
          >
            <CircleCheck
              v-if="st.is_active"
              class="size-5 text-fg-success-soft"
              aria-hidden="true"
            />
            <Circle v-else class="size-5 text-fg-faint" aria-hidden="true" />
          </button>
          <div class="min-w-0 flex-1">
            <span class="text-sm font-bold text-fg-primary">{{ st.name }}</span>
            <p class="text-xs text-fg-muted">
              {{ formatCurrency(st.tube_price) }} / {{ st.per_tube }} {{ t('shuttle.perTube') }}
            </p>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>

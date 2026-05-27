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
import { DEFAULT_BANK_CONFIG, type BankConfig } from '@/types'
import { useBankConfigStore } from '@/stores/bankConfig'
import { useLangStore } from '@/stores/lang'
import { useToast } from 'vue-toastification'

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
</script>

<template>
  <div class="mx-auto max-w-3xl px-4 py-6 sm:px-6 lg:px-8">
    <div class="mb-6">
      <router-link
        to="/"
        class="inline-flex min-h-11 items-center text-sm font-bold text-indigo-600 transition hover:text-indigo-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
      >
        <ChevronLeft class="mr-1 h-5 w-5" aria-hidden="true" />
        {{ t('common.backToHome') }}
      </router-link>
    </div>

    <section class="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm sm:p-6">
      <div class="mb-6 flex items-start gap-3">
        <div
          class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-indigo-50 text-indigo-600"
        >
          <CreditCard class="h-5 w-5" aria-hidden="true" />
        </div>
        <div>
          <h1 class="text-[22px] font-bold leading-tight text-gray-900">
            {{ t('settings.title') }}
          </h1>
          <p class="mt-1 text-sm leading-6 text-gray-600">
            {{ t('settings.subtitle') }}
          </p>
        </div>
      </div>

      <div class="overflow-hidden rounded-2xl border border-gray-100 bg-white shadow-sm">
        <div class="flex items-center justify-between border-b border-gray-100 px-5 py-4">
          <div class="flex items-center gap-2">
            <CreditCard class="h-4 w-4 text-gray-400" aria-hidden="true" />
            <h2 class="text-sm font-bold uppercase tracking-wider text-gray-500">
              {{ t('settings.paymentTitle') }}
            </h2>
          </div>
          <button
            type="button"
            class="flex min-h-11 items-center gap-1 rounded-lg px-2 text-sm font-bold text-indigo-600 transition hover:text-indigo-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
            @click="toggleAddForm"
          >
            <X v-if="showAddForm" class="h-4 w-4" aria-hidden="true" />
            <Plus v-else class="h-4 w-4" aria-hidden="true" />
            {{ t('settings.addBank') }}
          </button>
        </div>

        <form
          v-if="showAddForm"
          class="grid gap-3 border-b border-gray-100 bg-gray-50 px-5 py-4 sm:grid-cols-2"
          @submit.prevent="handleAddBank"
        >
          <label class="block">
            <span class="text-xs font-bold uppercase tracking-wide text-gray-500">
              {{ t('settings.bank') }}
            </span>
            <input
              v-model="form.bank_id"
              class="mt-1 block min-h-11 w-full rounded-xl border border-gray-300 px-3 py-2 text-base uppercase shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
              placeholder="TPB"
              required
            />
          </label>

          <label class="block">
            <span class="text-xs font-bold uppercase tracking-wide text-gray-500">
              {{ t('settings.accountNumber') }}
            </span>
            <input
              v-model="form.account_number"
              class="mt-1 block min-h-11 w-full rounded-xl border border-gray-300 px-3 py-2 text-base shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
              placeholder="10003392871"
              required
            />
          </label>

          <label class="block">
            <span class="text-xs font-bold uppercase tracking-wide text-gray-500">
              {{ t('settings.accountName') }}
            </span>
            <input
              v-model="form.account_name"
              class="mt-1 block min-h-11 w-full rounded-xl border border-gray-300 px-3 py-2 text-base uppercase shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
              placeholder="CLB CAU LONG BMT"
              required
            />
          </label>

          <label class="block">
            <span class="text-xs font-bold uppercase tracking-wide text-gray-500">
              {{ t('settings.qrTemplate') }}
            </span>
            <input
              v-model="form.template"
              class="mt-1 block min-h-11 w-full rounded-xl border border-gray-300 px-3 py-2 text-base shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
              placeholder="compact2"
            />
          </label>

          <div class="sm:col-span-2">
            <button
              type="submit"
              :disabled="saving"
              class="inline-flex min-h-11 w-full items-center justify-center rounded-xl bg-indigo-600 px-4 py-2 text-sm font-bold text-white shadow-sm transition hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600 disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto"
            >
              <Loader2 v-if="saving" class="mr-2 h-4 w-4 animate-spin" aria-hidden="true" />
              {{ t('settings.saveBank') }}
            </button>
          </div>
        </form>

        <div v-if="bankConfigStore.loading" class="px-5 py-6 text-sm text-gray-500">
          {{ t('common.loading') }}
        </div>
        <div v-else-if="configs.length === 0" class="px-5 py-6 text-sm text-gray-500">
          {{ t('settings.noBanks') }}
        </div>
        <div v-else class="divide-y divide-gray-100">
          <div v-for="config in configs" :key="config.id" class="flex items-center gap-3 px-5 py-4">
            <button
              type="button"
              class="shrink-0 transition hover:scale-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
              :title="t('settings.setDefault')"
              :aria-label="t('settings.setDefault')"
              :disabled="activeActionId === config.id"
              @click="handleSetDefault(config)"
            >
              <Loader2
                v-if="activeActionId === config.id"
                class="h-5 w-5 animate-spin text-indigo-500"
                aria-hidden="true"
              />
              <CircleCheck
                v-else-if="config.is_active"
                class="h-5 w-5 text-green-500"
                aria-hidden="true"
              />
              <Circle v-else class="h-5 w-5 text-gray-300 hover:text-indigo-400" aria-hidden="true" />
            </button>

            <div class="min-w-0 flex-1">
              <div class="flex flex-wrap items-center gap-2">
                <span class="text-sm font-bold text-gray-900">{{ config.bank_id }}</span>
                <span
                  v-if="config.is_active"
                  class="rounded-full bg-green-100 px-1.5 py-0.5 text-[10px] font-bold text-green-700"
                >
                  {{ t('settings.inUse') }}
                </span>
              </div>
              <p class="truncate text-xs text-gray-500">
                {{ config.account_number }} · {{ config.account_name }}
              </p>
            </div>

            <button
              type="button"
              class="shrink-0 rounded-lg p-1.5 text-gray-400 transition hover:bg-red-50 hover:text-red-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-500"
              :title="t('settings.deleteBank')"
              :aria-label="t('settings.deleteBank')"
              :disabled="activeActionId === config.id"
              @click="handleDeleteBank(config)"
            >
              <Trash2 class="h-4 w-4" aria-hidden="true" />
            </button>
          </div>
        </div>
      </div>

      <p class="mt-4 text-sm leading-6 text-gray-600">
        {{ t('settings.qrNote') }}
      </p>
    </section>
  </div>
</template>

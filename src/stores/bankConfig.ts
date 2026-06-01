import { computed, ref } from 'vue'
import { defineStore } from 'pinia'
import { supabase } from '@/lib/supabase'
import {
  DEFAULT_BANK_CONFIG,
  type BankConfig,
  type BankConfigInput,
} from '@/types'

const normalizeBankConfig = (config: BankConfig): BankConfig => ({
  id: config.id,
  bank_id: config.bank_id.trim().toUpperCase(),
  account_number: config.account_number.trim(),
  account_name: config.account_name.trim(),
  template: (config.template || DEFAULT_BANK_CONFIG.template).trim(),
  is_active: Boolean(config.is_active),
})

const normalizeBankConfigInput = (config: BankConfigInput): BankConfigInput => ({
  bank_id: config.bank_id.trim().toUpperCase(),
  account_number: config.account_number.trim(),
  account_name: config.account_name.trim(),
  template: (config.template || DEFAULT_BANK_CONFIG.template).trim(),
  is_active: Boolean(config.is_active),
})

export const useBankConfigStore = defineStore('bankConfig', () => {
  const configs = ref<BankConfig[]>([])
  const loading = ref(false)
  const loaded = ref(false)
  const error = ref<string | null>(null)

  const activeBank = computed<BankConfigInput>(() => {
    return configs.value.find((config) => config.is_active) ?? configs.value[0] ?? DEFAULT_BANK_CONFIG
  })

  async function fetchConfigs(force = false) {
    if (loaded.value && !force) return configs.value
    if (loading.value) return configs.value

    loading.value = true
    error.value = null

    try {
      const { data, error: fetchError } = await supabase
        .from('bank_config')
        .select('id, bank_id, account_number, account_name, template, is_active')
        .order('is_active', { ascending: false })
        .order('bank_id', { ascending: true })

      if (fetchError) throw fetchError

      configs.value = (data ?? []).map((config) => normalizeBankConfig(config as BankConfig))
      loaded.value = true
      return configs.value
    } catch (fetchError) {
      const message = fetchError instanceof Error ? fetchError.message : 'Unable to load bank config'
      error.value = message
      throw fetchError
    } finally {
      loading.value = false
    }
  }

  async function createConfig(config: BankConfigInput) {
    const payload = normalizeBankConfigInput(config)

    if (!payload.bank_id || !payload.account_number || !payload.account_name) {
      throw new Error('Bank ID, account number, and account name are required')
    }

    if (payload.is_active) {
      const { error: clearError } = await supabase
        .from('bank_config')
        .update({ is_active: false })
        .neq('bank_id', payload.bank_id)

      if (clearError) throw clearError
    }

    const { error: insertError } = await supabase.from('bank_config').insert(payload)

    if (insertError) throw insertError
    return fetchConfigs(true)
  }

  async function setDefault(id: string) {
    const target = configs.value.find((config) => config.id === id)
    if (!target) throw new Error('Bank config not found')

    const { error: clearError } = await supabase
      .from('bank_config')
      .update({ is_active: false })
      .neq('id', id)

    if (clearError) throw clearError

    const { error: setError } = await supabase
      .from('bank_config')
      .update({ is_active: true })
      .eq('id', id)

    if (setError) throw setError

    return fetchConfigs(true)
  }

  async function deleteConfig(config: BankConfig) {
    if (configs.value.length <= 1) {
      throw new Error('At least one bank config is required')
    }

    const { error: deleteError } = await supabase.from('bank_config').delete().eq('id', config.id)
    if (deleteError) throw deleteError

    const remaining = await fetchConfigs(true)
    if (config.is_active && remaining.length > 0 && !remaining.some((item) => item.is_active)) {
      const nextDefault = remaining[0]
      if (nextDefault) await setDefault(nextDefault.id)
    }

    return configs.value
  }

  return {
    configs,
    loading,
    loaded,
    error,
    activeBank,
    fetchConfigs,
    createConfig,
    setDefault,
    deleteConfig,
  }
})

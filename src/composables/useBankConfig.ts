import { ref, computed } from 'vue'
import { supabase } from '@/lib/supabase'

export interface BankConfig {
  id: string
  bank_id: string
  account_number: string
  account_name: string
  template: string | null
  is_active: boolean
}

// Hardcoded fallback (used when bank_config table is empty)
export const BANK_FALLBACK: BankConfig = {
  id: '__fallback__',
  bank_id: 'TPB',
  account_number: '10003392871',
  account_name: 'CLB CẦU LÔNG 3PCL',
  template: 'compact2',
  is_active: true,
}

// Module-level singletons so every component shares the same state
const configs = ref<BankConfig[]>([])
const loading = ref(false)
let initialized = false

async function fetchConfigs() {
  initialized = true
  loading.value = true
  try {
    const { data, error } = await supabase
      .from('bank_config')
      .select('*')
      .order('is_active', { ascending: false })
    if (!error && data && data.length > 0) {
      configs.value = data as BankConfig[]
    } else {
      configs.value = []
    }
  } catch (e) {
    console.warn('[useBankConfig] fetch failed:', e)
    configs.value = []
  } finally {
    loading.value = false
  }
}

const activeBank = computed<BankConfig>(() => {
  const active = configs.value.find((c) => c.is_active)
  return active ?? BANK_FALLBACK
})

const usingFallback = computed(() => configs.value.length === 0)

async function setActive(id: string) {
  // Deactivate all, then activate target
  await supabase.from('bank_config').update({ is_active: false }).neq('id', id)
  await supabase.from('bank_config').update({ is_active: true }).eq('id', id)
  initialized = false
  await fetchConfigs()
}

async function addConfig(input: Omit<BankConfig, 'id' | 'is_active'>): Promise<{ error: unknown }> {
  const { data, error } = await supabase
    .from('bank_config')
    .insert({ ...input, is_active: configs.value.length === 0 })
    .select()
    .single()
  if (!error && data) {
    configs.value.push(data as BankConfig)
  }
  return { error }
}

async function removeConfig(id: string) {
  await supabase.from('bank_config').delete().eq('id', id)
  configs.value = configs.value.filter((c) => c.id !== id)
}

export function useBankConfig() {
  if (!initialized) fetchConfigs()
  return {
    configs,
    activeBank,
    loading,
    usingFallback,
    fetchConfigs,
    setActive,
    addConfig,
    removeConfig,
  }
}

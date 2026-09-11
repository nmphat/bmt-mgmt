import { ref, computed } from 'vue'
import { supabase } from '@/lib/supabase'
import type { ShuttleType } from '@/types'

const types = ref<ShuttleType[]>([])
const loading = ref(false)
let loaded = false

export function useShuttleTypes() {
  const activeTypes = computed(() => types.value.filter((t) => t.is_active))

  async function fetchTypes(force = false) {
    if (loaded && !force) return
    loading.value = true
    try {
      const { data, error } = await supabase
        .from('shuttle_types')
        .select('*')
        .order('name', { ascending: true })
      if (error) throw error
      types.value = data || []
      loaded = true
    } finally {
      loading.value = false
    }
  }

  async function addType(input: Omit<ShuttleType, 'id'>) {
    const { error } = await supabase.from('shuttle_types').insert(input)
    if (error) throw error
    await fetchTypes(true)
  }

  async function updateType(id: string, patch: Partial<Omit<ShuttleType, 'id'>>) {
    const { error } = await supabase.from('shuttle_types').update(patch).eq('id', id)
    if (error) throw error
    await fetchTypes(true)
  }

  async function toggleActive(type: ShuttleType) {
    await updateType(type.id, { is_active: !type.is_active })
  }

  return { types, activeTypes, loading, fetchTypes, addType, updateType, toggleActive }
}

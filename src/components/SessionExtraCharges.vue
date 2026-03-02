<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { useLangStore } from '@/stores/lang'
import { useToast } from 'vue-toastification'
import { Trash2, Plus, Loader2 } from 'lucide-vue-next'
import type { ExtraCharge, Member } from '@/types'

const props = defineProps<{
  sessionId: string
  members: Member[]
  isAdmin: boolean
  isReadOnly?: boolean
}>()

const emit = defineEmits<{
  changed: []
}>()

const langStore = useLangStore()
const toast = useToast()
const t = computed(() => langStore.t)

const charges = ref<(ExtraCharge & { display_name: string })[]>([])
const loading = ref(false)
const submitting = ref(false)

const showForm = ref(false)
const chargeForm = ref({
  memberId: '',
  amount: 0,
  note: '',
})

const currencyFormatter = new Intl.NumberFormat('vi-VN', {
  style: 'currency',
  currency: 'VND',
  maximumFractionDigits: 0,
})

function formatCurrency(value: number) {
  return currencyFormatter.format(value)
}

async function fetchCharges() {
  loading.value = true
  try {
    const { data, error } = await supabase
      .from('session_extra_charges')
      .select('*, member:members(display_name)')
      .eq('session_id', props.sessionId)
      .order('created_at', { ascending: true })

    if (error) throw error

    charges.value = (data || []).map((c: any) => ({
      ...c,
      display_name: c.member?.display_name || t.value('common.unknown'),
    }))
  } catch (error) {
    console.error('Error fetching extra charges:', error)
  } finally {
    loading.value = false
  }
}

async function addCharge() {
  if (!chargeForm.value.memberId || chargeForm.value.amount === 0) return

  try {
    submitting.value = true
    const { error } = await supabase.from('session_extra_charges').insert({
      session_id: props.sessionId,
      member_id: chargeForm.value.memberId,
      amount: chargeForm.value.amount,
      note: chargeForm.value.note,
    })

    if (error) throw error

    toast.success(t.value('toast.extraChargeAdded'))
    chargeForm.value = { memberId: '', amount: 0, note: '' }
    showForm.value = false
    await fetchCharges()
    emit('changed')
  } catch (error: any) {
    console.error('Error adding extra charge:', error)
    toast.error(error.message || t.value('toast.error', { message: 'Failed to add charge' }))
  } finally {
    submitting.value = false
  }
}

async function deleteCharge(chargeId: string) {
  if (!confirm(t.value('extraCharge.deleteConfirm'))) return

  try {
    const { error } = await supabase.from('session_extra_charges').delete().eq('id', chargeId)

    if (error) throw error

    toast.success(t.value('toast.extraChargeDeleted'))
    await fetchCharges()
    emit('changed')
  } catch (error: any) {
    console.error('Error deleting extra charge:', error)
    toast.error(error.message || t.value('toast.error', { message: 'Failed to delete charge' }))
  }
}

onMounted(() => {
  fetchCharges()
})

defineExpose({ fetchCharges })
</script>

<template>
  <div class="bg-white rounded-lg shadow-sm border border-gray-100">
    <div class="px-6 py-4 border-b border-gray-100 bg-gray-50 flex justify-between items-center">
      <h2 class="text-xl font-semibold text-gray-900">{{ t('extraCharge.title') }}</h2>
      <button
        v-if="isAdmin && !isReadOnly"
        @click="showForm = !showForm"
        class="flex items-center text-sm text-indigo-600 hover:text-indigo-800 font-medium transition"
      >
        <Plus class="w-4 h-4 mr-1" />
        {{ t('extraCharge.addCharge') }}
      </button>
    </div>

    <!-- Add Charge Form -->
    <div v-if="showForm && isAdmin" class="px-6 py-4 border-b border-gray-100 bg-indigo-50/50">
      <form @submit.prevent="addCharge" class="flex flex-wrap items-end gap-3">
        <div class="flex-1 min-w-[150px]">
          <label class="block text-xs font-medium text-gray-600 mb-1">{{
            t('extraCharge.member')
          }}</label>
          <select
            v-model="chargeForm.memberId"
            required
            class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-1.5"
          >
            <option value="" disabled>{{ t('session.selectMembers') }}</option>
            <option v-for="m in members" :key="m.id" :value="m.id">
              {{ m.display_name }}
            </option>
          </select>
        </div>
        <div class="w-32">
          <label class="block text-xs font-medium text-gray-600 mb-1">{{
            t('extraCharge.amount')
          }}</label>
          <input
            v-model.number="chargeForm.amount"
            type="number"
            required
            step="1000"
            class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-1.5"
          />
        </div>
        <div class="flex-1 min-w-[120px]">
          <label class="block text-xs font-medium text-gray-600 mb-1">{{
            t('extraCharge.note')
          }}</label>
          <input
            v-model="chargeForm.note"
            type="text"
            class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-1.5"
          />
        </div>
        <button
          type="submit"
          :disabled="submitting || !chargeForm.memberId || chargeForm.amount === 0"
          class="flex items-center px-4 py-1.5 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 transition disabled:opacity-50 text-sm font-medium shadow-sm"
        >
          <Loader2 v-if="submitting" class="w-4 h-4 mr-1 animate-spin" />
          {{ t('extraCharge.addCharge') }}
        </button>
      </form>
    </div>

    <!-- Charges List -->
    <div v-if="loading" class="flex justify-center py-8">
      <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-indigo-600"></div>
    </div>
    <div v-else-if="charges.length === 0" class="px-6 py-8 text-center text-gray-500 text-sm">
      {{ t('extraCharge.noCharges') }}
    </div>
    <div v-else class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <th
              scope="col"
              class="px-6 py-3 text-left text-sm font-medium text-gray-500 uppercase tracking-wider"
            >
              {{ t('extraCharge.member') }}
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-right text-sm font-medium text-gray-500 uppercase tracking-wider"
            >
              {{ t('extraCharge.amount') }}
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-left text-sm font-medium text-gray-500 uppercase tracking-wider"
            >
              {{ t('extraCharge.note') }}
            </th>
            <th v-if="isAdmin && !isReadOnly" scope="col" class="px-4 py-3 w-12">
              <span class="sr-only">{{ t('common.actions') }}</span>
            </th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <tr v-for="charge in charges" :key="charge.id">
            <td class="px-6 py-3 whitespace-nowrap text-sm font-medium text-gray-900">
              {{ charge.display_name }}
            </td>
            <td
              class="px-6 py-3 whitespace-nowrap text-sm text-right font-semibold"
              :class="charge.amount >= 0 ? 'text-red-600' : 'text-green-600'"
            >
              {{ charge.amount >= 0 ? '+' : '' }}{{ formatCurrency(charge.amount) }}
            </td>
            <td class="px-6 py-3 whitespace-nowrap text-sm text-gray-500">
              {{ charge.note || '—' }}
            </td>
            <td v-if="isAdmin && !isReadOnly" class="px-4 py-3 whitespace-nowrap text-center">
              <button
                @click="deleteCharge(charge.id)"
                class="text-gray-300 hover:text-red-500 transition focus:outline-none"
              >
                <Trash2 class="w-4 h-4" />
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

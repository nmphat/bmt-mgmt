<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
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

const allowedMemberIds = computed(() => new Set(props.members.map((m) => m.id)))

watch(
  () => props.members,
  () => {
    if (chargeForm.value.memberId && !allowedMemberIds.value.has(chargeForm.value.memberId)) {
      chargeForm.value.memberId = ''
    }
  },
  { deep: true },
)

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
  if (!allowedMemberIds.value.has(chargeForm.value.memberId)) {
    toast.error(t.value('toast.error', { message: t.value('session.registerError') }))
    return
  }

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
  <div class="rounded-2xl border border-gray-100 bg-white shadow-sm">
    <!-- ── Header ── -->
    <div
      class="px-4 md:px-6 py-4 border-b border-gray-100 bg-gray-50 flex justify-between items-center"
    >
      <h2 class="text-lg md:text-xl font-semibold text-gray-900">
        {{ t('extraCharge.title') }}
      </h2>
      <button
        v-if="isAdmin && !isReadOnly"
        @click="showForm = !showForm"
        class="flex items-center text-sm text-indigo-600 hover:text-indigo-800 font-medium transition"
      >
        <Plus class="w-4 h-4 mr-1" />
        {{ showForm ? t('common.close') : t('extraCharge.addCharge') }}
      </button>
    </div>

    <!-- ── Add Charge Form ── -->
    <div
      v-if="showForm && isAdmin"
      class="px-4 md:px-6 py-4 border-b border-gray-100 bg-indigo-50/50"
    >
      <!-- Mobile: stacked layout -->
      <form @submit.prevent="addCharge" class="space-y-3 md:hidden">
        <div>
          <label class="block text-xs font-medium text-gray-600 mb-1">
            {{ t('extraCharge.member') }}
          </label>
          <select
            v-model="chargeForm.memberId"
            required
            class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm border px-3 py-2"
          >
            <option value="" disabled>{{ t('session.selectMembers') }}</option>
            <option v-for="m in members" :key="m.id" :value="m.id">
              {{ m.display_name }}
            </option>
          </select>
        </div>
        <div class="grid grid-cols-2 gap-3">
          <div>
            <label class="block text-xs font-medium text-gray-600 mb-1">
              {{ t('extraCharge.amount') }}
            </label>
            <input
              v-model.number="chargeForm.amount"
              type="number"
              required
              step="1000"
              class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm border px-3 py-2"
            />
          </div>
          <div>
            <label class="block text-xs font-medium text-gray-600 mb-1">
              {{ t('extraCharge.note') }}
            </label>
            <input
              v-model="chargeForm.note"
              type="text"
              :placeholder="t('extraCharge.note')"
              class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm border px-3 py-2"
            />
          </div>
        </div>
        <button
          type="submit"
          :disabled="submitting || !chargeForm.memberId || chargeForm.amount === 0"
          class="w-full flex items-center justify-center px-4 py-2.5 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 transition disabled:opacity-50 text-sm font-medium shadow-sm"
        >
          <Loader2 v-if="submitting" class="w-4 h-4 mr-1.5 animate-spin" />
          <Plus v-else class="w-4 h-4 mr-1.5" />
          {{ t('extraCharge.addCharge') }}
        </button>
      </form>

      <!-- Desktop: horizontal layout -->
      <form @submit.prevent="addCharge" class="hidden md:flex md:items-end md:gap-3">
        <div class="flex-1 min-w-[150px]">
          <label class="block text-xs font-medium text-gray-600 mb-1">
            {{ t('extraCharge.member') }}
          </label>
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
          <label class="block text-xs font-medium text-gray-600 mb-1">
            {{ t('extraCharge.amount') }}
          </label>
          <input
            v-model.number="chargeForm.amount"
            type="number"
            required
            step="1000"
            class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-1.5"
          />
        </div>
        <div class="flex-1 min-w-[120px]">
          <label class="block text-xs font-medium text-gray-600 mb-1">
            {{ t('extraCharge.note') }}
          </label>
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

    <!-- ── Loading ── -->
    <div v-if="loading" class="flex justify-center py-8">
      <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-indigo-600"></div>
    </div>

    <!-- ── Empty State ── -->
    <div v-else-if="charges.length === 0" class="px-4 py-8 text-center">
      <svg
        class="w-8 h-8 mx-auto mb-2 text-gray-300"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="1.5"
          d="M9 14l6-6m-5.5.5h.01m4.99 5h.01M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16l3.5-2 3.5 2 3.5-2 3.5 2z"
        />
      </svg>
      <p class="text-sm text-gray-400">{{ t('extraCharge.noCharges') }}</p>
    </div>

    <!-- ── Mobile Cards (< md) ── -->
    <div v-else class="divide-y divide-gray-100 md:hidden">
      <div
        v-for="charge in charges"
        :key="charge.id"
        class="p-4 flex items-center justify-between"
      >
        <div class="flex flex-col min-w-0 mr-3">
          <span class="font-semibold text-gray-900 truncate">{{ charge.display_name }}</span>
          <span v-if="charge.note" class="text-xs text-gray-500 truncate">{{ charge.note }}</span>
        </div>
        <div class="flex items-center gap-2 shrink-0">
          <span
            class="font-bold text-base"
            :class="charge.amount >= 0 ? 'text-red-600' : 'text-green-600'"
          >
            {{ charge.amount >= 0 ? '+' : '' }}{{ formatCurrency(charge.amount) }}
          </span>
          <button
            v-if="isAdmin && !isReadOnly"
            @click="deleteCharge(charge.id)"
            class="text-gray-300 hover:text-red-500 transition p-1"
          >
            <Trash2 class="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>

    <!-- ── Desktop Table (≥ md) ── -->
    <div v-if="charges.length > 0" class="hidden md:block overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <th
              scope="col"
              class="px-6 py-3 text-left text-sm font-bold text-gray-500 uppercase tracking-wider"
            >
              {{ t('extraCharge.member') }}
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-right text-sm font-bold text-gray-500 uppercase tracking-wider"
            >
              {{ t('extraCharge.amount') }}
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-left text-sm font-bold text-gray-500 uppercase tracking-wider"
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
            <td class="px-6 py-4 whitespace-nowrap text-base font-bold text-gray-900">
              {{ charge.display_name }}
            </td>
            <td
              class="px-6 py-4 whitespace-nowrap text-base text-right font-bold"
              :class="charge.amount >= 0 ? 'text-red-600' : 'text-green-600'"
            >
              {{ charge.amount >= 0 ? '+' : '' }}{{ formatCurrency(charge.amount) }}
            </td>
            <td class="px-6 py-4 whitespace-nowrap text-base text-gray-500">
              {{ charge.note || '—' }}
            </td>
            <td v-if="isAdmin && !isReadOnly" class="px-4 py-4 whitespace-nowrap text-center">
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

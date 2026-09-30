<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { supabase } from '@/lib/supabase'
import { useLangStore } from '@/stores/lang'
import { useToast } from 'vue-toastification'
import { Trash2, Plus, Receipt } from 'lucide-vue-next'
import type { ExtraCharge, Member } from '@/types'
import Button from '@/components/ui/Button.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import FormField from '@/components/ui/FormField.vue'
import IconButton from '@/components/ui/IconButton.vue'
import Input from '@/components/ui/Input.vue'
import SectionHeader from '@/components/ui/SectionHeader.vue'
import Select from '@/components/ui/Select.vue'
import Spinner from '@/components/ui/Spinner.vue'
import TableHeaderCell from '@/components/ui/TableHeaderCell.vue'

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
  <div class="rounded-xl border border-line-divider bg-surface-card shadow-sm">
    <!-- ── Header ── -->
    <SectionHeader variant="Tinted" :title="t('extraCharge.title')">
      <template #actions>
        <Button
          v-if="isAdmin && !isReadOnly"
          size="Default"
          variant="Ghost"
          :leading-icon="Plus"
          :aria-expanded="showForm"
          @click="showForm = !showForm"
        >
          {{ showForm ? t('common.close') : t('extraCharge.addCharge') }}
        </Button>
      </template>
    </SectionHeader>

    <!-- ── Add Charge Form ── -->
    <div v-if="showForm && isAdmin">
      <!-- Mobile: stacked layout -->
      <form
        data-ds="Extra Charge Form"
        data-ds-viewport="Mobile"
        class="space-y-3 border-b border-line-divider bg-surface-brand-subtle px-4 py-4 md:hidden"
        @submit.prevent="addCharge"
      >
        <FormField
          :label="t('extraCharge.member')"
          control="Select"
          label-style="Small"
          v-slot="{ controlProps }"
        >
          <Select v-model="chargeForm.memberId" v-bind="controlProps" size="Small" required>
            <option value="" disabled>{{ t('session.selectMembers') }}</option>
            <option v-for="m in members" :key="m.id" :value="m.id">
              {{ m.display_name }}
            </option>
          </Select>
        </FormField>
        <div class="grid grid-cols-2 gap-3">
          <FormField :label="t('extraCharge.amount')" label-style="Small" v-slot="{ controlProps }">
            <Input
              v-model.number="chargeForm.amount"
              v-bind="controlProps"
              size="Small"
              type="number"
              required
              step="1000"
            />
          </FormField>
          <FormField :label="t('extraCharge.note')" label-style="Small" v-slot="{ controlProps }">
            <Input
              v-model="chargeForm.note"
              v-bind="controlProps"
              size="Small"
              type="text"
              :placeholder="t('extraCharge.note')"
            />
          </FormField>
        </div>
        <Button
          type="submit"
          size="Small"
          variant="Primary"
          :leading-icon="Plus"
          :loading="submitting"
          :disabled="submitting || !chargeForm.memberId || chargeForm.amount === 0"
          class="w-full"
        >
          {{ t('extraCharge.addCharge') }}
        </Button>
      </form>

      <!-- Desktop: horizontal layout -->
      <form
        data-ds="Extra Charge Form"
        data-ds-viewport="Desktop"
        class="hidden border-b border-line-divider bg-surface-brand-subtle px-6 py-4 md:flex md:items-end md:gap-3"
        @submit.prevent="addCharge"
      >
        <FormField
          :label="t('extraCharge.member')"
          control="Select"
          label-style="Small"
          class="min-w-[150px] flex-1"
          v-slot="{ controlProps }"
        >
          <Select v-model="chargeForm.memberId" v-bind="controlProps" size="Small" required>
            <option value="" disabled>{{ t('session.selectMembers') }}</option>
            <option v-for="m in members" :key="m.id" :value="m.id">
              {{ m.display_name }}
            </option>
          </Select>
        </FormField>
        <FormField
          :label="t('extraCharge.amount')"
          label-style="Small"
          class="w-32"
          v-slot="{ controlProps }"
        >
          <Input
            v-model.number="chargeForm.amount"
            v-bind="controlProps"
            size="Small"
            type="number"
            required
            step="1000"
          />
        </FormField>
        <FormField
          :label="t('extraCharge.note')"
          label-style="Small"
          class="min-w-[120px] flex-1"
          v-slot="{ controlProps }"
        >
          <Input v-model="chargeForm.note" v-bind="controlProps" size="Small" type="text" />
        </FormField>
        <Button
          type="submit"
          size="Small"
          variant="Primary"
          :loading="submitting"
          :disabled="submitting || !chargeForm.memberId || chargeForm.amount === 0"
        >
          {{ t('extraCharge.addCharge') }}
        </Button>
      </form>
    </div>

    <!-- ── Loading ── -->
    <div v-if="loading" class="flex justify-center py-8">
      <Spinner size="32" />
    </div>

    <!-- ── Empty State ── -->
    <EmptyState
      v-else-if="charges.length === 0"
      variant="Plain"
      align="Center"
      size="Small"
      :icon="Receipt"
    >
      {{ t('extraCharge.noCharges') }}
    </EmptyState>

    <!-- ── Mobile Cards (< md) ── -->
    <div v-else class="md:hidden">
      <div
        v-for="charge in charges"
        :key="charge.id"
        data-ds="Extra Charge Item"
        :data-ds-sign="charge.amount >= 0 ? 'Charge' : 'Refund'"
        class="flex items-center justify-between gap-3 border-b border-line-subtle p-4 last:border-b-0"
      >
        <div class="flex min-w-0 flex-col">
          <span class="truncate text-base font-semibold text-fg-primary">{{
            charge.display_name
          }}</span>
          <span v-if="charge.note" class="truncate text-xs text-fg-muted">{{ charge.note }}</span>
        </div>
        <div class="flex shrink-0 items-center gap-2">
          <span
            class="text-base font-bold"
            :class="charge.amount >= 0 ? 'text-fg-danger' : 'text-fg-success'"
          >
            {{ charge.amount >= 0 ? '+' : '' }}{{ formatCurrency(charge.amount) }}
          </span>
          <IconButton
            v-if="isAdmin && !isReadOnly"
            :icon="Trash2"
            :label="t('common.delete')"
            size="Small"
            shape="Square"
            variant="Ghost"
            @click="deleteCharge(charge.id)"
          />
        </div>
      </div>
    </div>

    <!-- ── Desktop Table (≥ md) ── -->
    <div v-if="charges.length > 0" class="hidden overflow-x-auto md:block">
      <table class="min-w-full">
        <thead>
          <tr>
            <TableHeaderCell align="Left">{{ t('extraCharge.member') }}</TableHeaderCell>
            <TableHeaderCell align="Right">{{ t('extraCharge.amount') }}</TableHeaderCell>
            <TableHeaderCell align="Left">{{ t('extraCharge.note') }}</TableHeaderCell>
            <TableHeaderCell v-if="isAdmin && !isReadOnly" density="Compact" class="w-16">
              <span class="sr-only">{{ t('common.actions') }}</span>
            </TableHeaderCell>
          </tr>
        </thead>
        <tbody class="bg-surface-card">
          <tr
            v-for="charge in charges"
            :key="charge.id"
            data-ds="Extra Charge Table Row"
            :data-ds-sign="charge.amount >= 0 ? 'Charge' : 'Refund'"
            class="border-b border-line-divider last:border-b-0"
          >
            <td class="whitespace-nowrap px-6 py-4 text-base font-bold text-fg-primary">
              {{ charge.display_name }}
            </td>
            <td
              class="whitespace-nowrap px-6 py-4 text-right text-base font-bold"
              :class="charge.amount >= 0 ? 'text-fg-danger' : 'text-fg-success'"
            >
              {{ charge.amount >= 0 ? '+' : '' }}{{ formatCurrency(charge.amount) }}
            </td>
            <td class="whitespace-nowrap px-6 py-4 text-base text-fg-muted">
              {{ charge.note || '—' }}
            </td>
            <td v-if="isAdmin && !isReadOnly" class="whitespace-nowrap px-3 py-4 text-center">
              <IconButton
                :icon="Trash2"
                :label="t('common.delete')"
                size="Small"
                shape="Square"
                variant="Ghost"
                @click="deleteCharge(charge.id)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

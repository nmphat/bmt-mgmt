<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { format } from 'date-fns'
import { UserX, UserPlus, Trash2, Loader2, ChevronLeft } from 'lucide-vue-next'
import { useLangStore } from '@/stores/lang'
import { useAuthStore } from '@/stores/auth'
import type { SessionSummary, Interval, SessionRegistration, Member } from '@/types'

const props = defineProps<{
  session: SessionSummary
  registrations: SessionRegistration[]
  intervals: Interval[]
  presence: Record<string, Record<string, boolean>>
  availableMembers: Member[]
  isRegistering: boolean
  autoOpenMemberDropdown?: boolean
}>()

const emit = defineEmits<{
  togglePresence: [memberId: string, intervalId: string]
  toggleAbsent: [reg: SessionRegistration]
  registerMembers: [memberIds: string[]]
  removeRegistration: [memberId: string, name: string]
}>()

const langStore = useLangStore()
const authStore = useAuthStore()
const t = computed(() => langStore.t)

const showMemberDropdown = ref(props.autoOpenMemberDropdown ?? false)
const selectedMemberIds = ref<string[]>([])
const dropdownRef = ref<HTMLElement | null>(null)

const formatTime = (iso: string) => format(new Date(iso), 'HH:mm')

const isReadOnly = computed(
  () =>
    props.session.status === 'waiting_for_payment' || props.session.status === 'done',
)

function handleClickOutside(e: MouseEvent) {
  if (dropdownRef.value && !dropdownRef.value.contains(e.target as Node)) {
    showMemberDropdown.value = false
  }
}

function handleRegister() {
  if (selectedMemberIds.value.length === 0) return
  emit('registerMembers', [...selectedMemberIds.value])
  selectedMemberIds.value = []
  showMemberDropdown.value = false
}

onMounted(() => document.addEventListener('click', handleClickOutside))
onUnmounted(() => document.removeEventListener('click', handleClickOutside))
</script>

<template>
  <div class="bg-white rounded-lg shadow-sm mb-6 border border-gray-100">
    <!-- Section header -->
    <div class="px-4 md:px-6 py-4 border-b border-gray-100 bg-gray-50 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3">
      <div class="flex items-center gap-2">
        <h2 class="text-lg md:text-xl font-semibold text-gray-900">
          {{ t('session.attendanceMatrix') }}
        </h2>
        <span v-if="!authStore.isAuthenticated" class="text-xs text-gray-500 italic">
          {{ t('session.readOnly') }}
        </span>
      </div>

      <!-- Add member controls (admin + open/not-done status) -->
      <div
        v-if="authStore.isAuthenticated && !isReadOnly"
        class="flex items-center gap-2 w-full sm:w-auto relative"
        ref="dropdownRef"
      >
        <div class="relative flex-1 sm:w-64">
          <button
            @click="showMemberDropdown = !showMemberDropdown"
            class="flex items-center justify-between w-full rounded-md border border-gray-300 shadow-sm bg-white px-3 py-1.5 text-sm cursor-pointer focus:ring-2 focus:ring-indigo-500 focus:outline-none"
          >
            <span v-if="selectedMemberIds.length === 0" class="text-gray-500">
              {{ t('session.selectMembers') }}
            </span>
            <span v-else class="text-gray-900 font-medium">
              {{ t('session.selectedCount', { count: selectedMemberIds.length }) }}
            </span>
            <ChevronLeft
              class="w-4 h-4 text-gray-400 transition-transform duration-200"
              :class="showMemberDropdown ? 'rotate-90' : '-rotate-90'"
            />
          </button>

          <div
            v-if="showMemberDropdown"
            class="absolute z-[60] left-0 right-0 mt-1 bg-white border border-gray-200 rounded-md shadow-lg max-h-60 overflow-y-auto"
          >
            <div
              v-if="availableMembers.length === 0"
              class="p-3 text-sm text-gray-500 italic text-center"
            >
              {{ t('session.noMoreMembers') }}
            </div>
            <label
              v-for="m in availableMembers"
              :key="m.id"
              class="flex items-center px-3 py-2 hover:bg-indigo-50 cursor-pointer transition select-none"
            >
              <input
                type="checkbox"
                :value="m.id"
                v-model="selectedMemberIds"
                class="h-4 w-4 text-indigo-600 rounded border-gray-300 mr-3"
              />
              <span class="text-sm text-gray-700">{{ m.display_name }}</span>
            </label>
          </div>
        </div>

        <button
          @click="handleRegister"
          :disabled="selectedMemberIds.length === 0 || isRegistering"
          class="flex items-center px-4 py-1.5 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 transition disabled:opacity-50 whitespace-nowrap text-sm font-medium shadow-sm"
        >
          <UserPlus v-if="!isRegistering" class="w-4 h-4 mr-1.5" />
          <Loader2 v-else class="w-4 h-4 mr-1.5 animate-spin" />
          {{ isRegistering ? t('common.loading') : t('session.register') }}
        </button>
      </div>
    </div>

    <!-- Presence grid (horizontal scroll, sticky first column) -->
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <!-- Sticky name column -->
            <th
              scope="col"
              class="sticky left-0 z-10 bg-gray-50 px-4 md:px-6 py-3 text-left text-sm font-medium text-gray-500 uppercase tracking-wider border-r border-gray-200 shadow-[2px_0_5px_rgba(0,0,0,0.05)] w-36 md:w-48"
            >
              {{ t('common.member') }}
            </th>
            <!-- Remove column -->
            <th
              v-if="authStore.isAuthenticated && !isReadOnly"
              scope="col"
              class="px-2 py-3 w-10 text-center text-sm font-medium text-gray-500 uppercase tracking-wider"
            >
              <span class="sr-only">{{ t('common.actions') }}</span>
            </th>
            <!-- Absent column -->
            <th
              v-if="authStore.isAuthenticated && !isReadOnly"
              scope="col"
              class="px-2 py-3 w-14 text-center text-sm font-medium text-gray-500 uppercase tracking-wider"
            >
              {{ t('session.absent') }}
            </th>
            <!-- Interval columns -->
            <th
              v-for="interval in intervals"
              :key="interval.id"
              scope="col"
              class="px-3 py-3 text-center text-xs md:text-sm font-medium text-gray-500 uppercase tracking-wider min-w-[80px] md:min-w-[100px]"
            >
              {{ formatTime(interval.start_time) }}<br class="md:hidden" />
              <span class="hidden md:inline">–</span>
              {{ formatTime(interval.end_time) }}
            </th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <tr
            v-for="reg in registrations"
            :key="reg.id"
            :class="{ 'opacity-60 bg-gray-50': reg.is_registered_not_attended }"
          >
            <!-- Sticky name cell -->
            <td
              class="sticky left-0 z-10 bg-white px-4 md:px-6 py-3 whitespace-nowrap text-sm md:text-base font-medium text-gray-900 border-r border-gray-200 shadow-[2px_0_5px_rgba(0,0,0,0.05)]"
              :class="{ 'bg-gray-50': reg.is_registered_not_attended }"
            >
              <div class="flex items-center gap-1">
                <span class="truncate max-w-[90px] md:max-w-none">
                  {{ reg.member?.display_name }}
                </span>
                <span
                  v-if="reg.is_registered_not_attended"
                  class="text-xs text-red-500 italic shrink-0"
                >({{ t('session.absent') }})</span>
              </div>
            </td>

            <!-- Remove button -->
            <td
              v-if="authStore.isAuthenticated && !isReadOnly"
              class="px-2 py-3 text-center"
            >
              <button
                @click="$emit('removeRegistration', reg.member_id, reg.member?.display_name || '')"
                class="text-gray-300 hover:text-red-500 transition focus:outline-none"
                :title="t('session.removeRegistrationTooltip')"
              >
                <Trash2 class="w-4 h-4 mx-auto" />
              </button>
            </td>

            <!-- Absent toggle -->
            <td
              v-if="authStore.isAuthenticated && !isReadOnly"
              class="px-2 py-3 text-center"
            >
              <button
                @click="$emit('toggleAbsent', reg)"
                class="text-gray-400 hover:text-red-600 transition focus:outline-none"
                :class="{ 'text-red-600': reg.is_registered_not_attended }"
                :title="t('session.markAbsentTooltip')"
              >
                <UserX class="w-5 h-5 mx-auto" />
              </button>
            </td>

            <!-- Presence cells -->
            <td
              v-for="interval in intervals"
              :key="interval.id"
              class="px-3 py-3 text-center"
            >
              <input
                type="checkbox"
                :checked="presence[reg.member_id]?.[interval.id] || false"
                @change="$emit('togglePresence', reg.member_id, interval.id)"
                :disabled="
                  !authStore.isAuthenticated ||
                  reg.is_registered_not_attended ||
                  isReadOnly
                "
                class="h-5 w-5 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

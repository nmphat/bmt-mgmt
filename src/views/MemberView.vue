<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import type { Member } from '@/types'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { Check, X, Edit, Save, Trash2, UserPlus, Loader2 } from 'lucide-vue-next'
import { useToast } from 'vue-toastification'
import { computed } from 'vue'

const authStore = useAuthStore()
const langStore = useLangStore()
const toast = useToast()
const t = computed(() => langStore.t)
const members = ref<Member[]>([])
const loading = ref(true)
const actionLoading = ref(false)
const editingMemberId = ref<string | null>(null)
const editForm = ref<Partial<Member>>({})

const showAddForm = ref(false)
const createAnother = ref(false)
const newMember = ref({
  display_name: '',
  role: 'member' as 'admin' | 'member',
  is_active: true,
  is_permanent: false,
})

async function fetchMembers() {
  try {
    loading.value = true
    const { data, error } = await supabase
      .from('members')
      .select('*')
      .order('display_name', { ascending: true })

    if (error) throw error
    const sortedMembers = (data || []) as Member[]
    const locale = langStore.currentLang
    sortedMembers.sort((a, b) => a.display_name.localeCompare(b.display_name, locale))
    members.value = sortedMembers
  } catch (error) {
    console.error('Error fetching members:', error)
    toast.error(t.value('member.fetchError'))
  } finally {
    loading.value = false
  }
}

async function addMember() {
  if (!authStore.isAuthenticated) return
  if (!newMember.value.display_name.trim()) {
    toast.error(t.value('member.nameRequired'))
    return
  }

  try {
    actionLoading.value = true
    const { data, error } = await supabase.from('members').insert([newMember.value]).select()

    if (error) throw error

    if (data) {
      members.value.push(data[0])
      const locale = langStore.currentLang
      members.value.sort((a, b) => a.display_name.localeCompare(b.display_name, locale))
    }

    toast.success(t.value('toast.memberAdded'))

    if (!createAnother.value) {
      showAddForm.value = false
    }

    newMember.value = {
      display_name: '',
      role: 'member',
      is_active: true,
      is_permanent: false,
    }
  } catch (error: any) {
    console.error('Error adding member:', error)
    toast.error(error.message || t.value('toast.error', { message: error.message }))
  } finally {
    actionLoading.value = false
  }
}

async function deleteMember(id: string, name: string) {
  if (!authStore.isAuthenticated) return
  if (!confirm(t.value('member.deleteConfirm', { name }))) {
    return
  }

  try {
    actionLoading.value = true
    const { error } = await supabase.from('members').delete().eq('id', id)

    if (error) throw error

    members.value = members.value.filter((m) => m.id !== id)
    toast.success(t.value('toast.memberDeleted'))
  } catch (error: any) {
    console.error('Error deleting member:', error)
    toast.error(error.message || t.value('toast.error', { message: error.message }))
  } finally {
    actionLoading.value = false
  }
}

function startEdit(member: Member) {
  if (!authStore.isAuthenticated) return
  editingMemberId.value = member.id
  editForm.value = { ...member }
}

function cancelEdit() {
  editingMemberId.value = null
  editForm.value = {}
}

async function saveEdit(id: string) {
  if (!authStore.isAuthenticated) return
  try {
    const updates = {
      display_name: editForm.value.display_name,
      role: editForm.value.role,
      is_active: editForm.value.is_active,
      is_permanent: editForm.value.is_permanent,
      updated_at: new Date().toISOString(),
    }

    const { error } = await supabase.from('members').update(updates).eq('id', id)

    if (error) throw error

    // Optimistic update
    const index = members.value.findIndex((m) => m.id === id)
    if (index !== -1) {
      members.value[index] = { ...members.value[index], ...updates } as Member
    }

    toast.success(t.value('toast.memberUpdated'))
    cancelEdit()
  } catch (error) {
    console.error('Error updating member:', error)
    toast.error(t.value('toast.error', { message: (error as any).message }))
  }
}

onMounted(fetchMembers)
</script>

<template>
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
    <div class="flex justify-between items-center mb-6">
      <h1 class="text-3xl font-bold text-gray-900">{{ t('member.title') }}</h1>
      <button
        v-if="authStore.isAuthenticated && !showAddForm"
        @click="showAddForm = true"
        class="flex items-center px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 transition shadow-sm"
      >
        <UserPlus class="w-5 h-5 mr-2" />
        {{ t('member.newName') }}
      </button>
    </div>

    <!-- Add Member Form -->
    <div
      v-if="showAddForm"
      class="bg-white shadow-sm rounded-lg border border-indigo-100 p-6 mb-8 animate-in fade-in slide-in-from-top-4 duration-300"
    >
      <div class="flex justify-between items-center mb-4">
        <h2 class="text-xl font-semibold text-gray-900">{{ t('member.addTitle') }}</h2>
        <button @click="showAddForm = false" class="text-gray-400 hover:text-gray-600">
          <X class="w-5 h-5" />
        </button>
      </div>
      <form @submit.prevent="addMember" class="grid grid-cols-1 md:grid-cols-4 gap-4 items-end">
        <div>
          <label class="block text-base font-medium text-gray-700 mb-1">{{
            t('member.displayName')
          }}</label>
          <input
            v-model="newMember.display_name"
            type="text"
            required
            class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-base border px-3 py-2"
            :placeholder="t('member.namePlaceholder')"
          />
        </div>
        <div>
          <label class="block text-base font-medium text-gray-700 mb-1">{{
            t('member.role')
          }}</label>
          <select
            v-model="newMember.role"
            class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-base border px-3 py-2"
          >
            <option value="member">{{ t('member.memberRole') }}</option>
            <option value="admin">{{ t('member.adminRole') }}</option>
          </select>
        </div>
        <div class="flex flex-wrap gap-4 mb-2 md:mb-0">
          <label class="flex items-center text-base text-gray-700 cursor-pointer">
            <input
              v-model="newMember.is_active"
              type="checkbox"
              class="h-4 w-4 text-indigo-600 rounded border-gray-300 mr-2"
            />
            {{ t('member.active') }}
          </label>
          <label class="flex items-center text-base text-gray-700 cursor-pointer">
            <input
              v-model="newMember.is_permanent"
              type="checkbox"
              class="h-4 w-4 text-indigo-600 rounded border-gray-300 mr-2"
            />
            {{ t('member.permanent') }}
          </label>
          <label
            class="flex items-center text-base text-indigo-600 font-medium cursor-pointer border-l pl-4 border-gray-200"
          >
            <input
              v-model="createAnother"
              type="checkbox"
              class="h-4 w-4 text-indigo-600 rounded border-gray-300 mr-2"
            />
            {{ t('member.createAnother') }}
          </label>
        </div>
        <div class="flex gap-2">
          <button
            type="submit"
            :disabled="actionLoading"
            class="flex-1 bg-indigo-600 text-white px-4 py-2 rounded-md hover:bg-indigo-700 transition disabled:opacity-50 flex justify-center items-center text-base"
          >
            <Loader2 v-if="actionLoading" class="w-4 h-4 mr-2 animate-spin" />
            {{ t('member.create') }}
          </button>
          <button
            type="button"
            @click="showAddForm = false"
            class="px-4 py-2 border border-gray-300 rounded-md text-gray-700 hover:bg-gray-50 transition text-base"
          >
            {{ t('common.cancel') }}
          </button>
        </div>
      </form>
    </div>

    <div v-if="loading" class="flex justify-center py-12">
      <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600"></div>
    </div>

    <div v-else class="bg-white shadow-sm rounded-lg border border-gray-100 overflow-hidden">
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th
                scope="col"
                class="px-6 py-3 text-left text-sm font-medium text-gray-500 uppercase tracking-wider"
              >
                {{ t('member.name') }}
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-sm font-medium text-gray-500 uppercase tracking-wider"
              >
                {{ t('member.role') }}
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-center text-sm font-medium text-gray-500 uppercase tracking-wider"
              >
                {{ t('member.active') }}
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-center text-sm font-medium text-gray-500 uppercase tracking-wider"
              >
                {{ t('member.permanent') }}
              </th>
              <th
                v-if="authStore.isAuthenticated"
                scope="col"
                class="px-6 py-3 text-right text-sm font-medium text-gray-500 uppercase tracking-wider"
              >
                {{ t('common.actions') }}
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <tr
              v-for="member in members"
              :key="member.id"
              :class="{ 'bg-gray-50': editingMemberId === member.id }"
            >
              <!-- Name -->
              <td class="px-6 py-4 whitespace-nowrap text-base text-gray-900">
                <input
                  v-if="editingMemberId === member.id"
                  v-model="editForm.display_name"
                  type="text"
                  class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-base border px-2 py-1"
                />
                <span v-else class="font-medium">{{ member.display_name }}</span>
              </td>

              <!-- Role -->
              <td class="px-6 py-4 whitespace-nowrap text-base text-gray-500">
                <select
                  v-if="editingMemberId === member.id"
                  v-model="editForm.role"
                  class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-base border px-2 py-1"
                >
                  <option value="member">{{ t('member.memberRole') }}</option>
                  <option value="admin">{{ t('member.adminRole') }}</option>
                </select>
                <span
                  v-else
                  :class="[
                    'px-2 py-1 text-sm font-medium rounded-full',
                    member.role === 'admin'
                      ? 'bg-indigo-100 text-indigo-800'
                      : 'bg-gray-100 text-gray-800',
                  ]"
                >
                  {{ member.role === 'admin' ? t('member.adminRole') : t('member.memberRole') }}
                </span>
              </td>

              <!-- Is Active -->
              <td class="px-6 py-4 whitespace-nowrap text-center text-base text-gray-500">
                <div v-if="editingMemberId === member.id" class="flex justify-center">
                  <input
                    v-model="editForm.is_active"
                    type="checkbox"
                    class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded cursor-pointer"
                  />
                </div>
                <div v-else>
                  <Check v-if="member.is_active" class="w-5 h-5 text-green-500 mx-auto" />
                  <X v-else class="w-5 h-5 text-gray-300 mx-auto" />
                </div>
              </td>

              <!-- Is Permanent -->
              <td class="px-6 py-4 whitespace-nowrap text-center text-base text-gray-500">
                <div v-if="editingMemberId === member.id" class="flex justify-center">
                  <input
                    v-model="editForm.is_permanent"
                    type="checkbox"
                    class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded cursor-pointer"
                  />
                </div>
                <div v-else>
                  <Check v-if="member.is_permanent" class="w-5 h-5 text-indigo-500 mx-auto" />
                  <span v-else class="text-gray-300">-</span>
                </div>
              </td>

              <!-- Actions -->
              <td
                v-if="authStore.isAuthenticated"
                class="px-6 py-4 whitespace-nowrap text-right text-base font-medium"
              >
                <div v-if="editingMemberId === member.id" class="flex justify-end gap-2">
                  <button
                    @click="saveEdit(member.id)"
                    class="text-green-600 hover:text-green-900"
                    :title="t('common.save')"
                  >
                    <Save class="w-5 h-5" />
                  </button>
                  <button
                    @click="cancelEdit"
                    class="text-red-600 hover:text-red-900"
                    :title="t('common.cancel')"
                  >
                    <X class="w-5 h-5" />
                  </button>
                </div>
                <div v-else class="flex justify-end gap-3">
                  <button
                    @click="startEdit(member)"
                    class="text-indigo-600 hover:text-indigo-900"
                    :title="t('common.edit')"
                  >
                    <Edit class="w-5 h-5" />
                  </button>
                  <button
                    @click="deleteMember(member.id, member.display_name)"
                    class="text-gray-400 hover:text-red-600"
                    :title="t('common.delete')"
                  >
                    <Trash2 class="w-5 h-5" />
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>

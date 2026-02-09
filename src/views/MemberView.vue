<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import type { Member } from '@/types'
import { useAuthStore } from '@/stores/auth'
import { Check, X, Edit, Save, Trash2, UserPlus, Loader2 } from 'lucide-vue-next'
import { useToast } from 'vue-toastification'

const authStore = useAuthStore()
const toast = useToast()
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
    sortedMembers.sort((a, b) => a.display_name.localeCompare(b.display_name, 'vi'))
    members.value = sortedMembers
  } catch (error) {
    console.error('Error fetching members:', error)
    toast.error('Failed to load members')
  } finally {
    loading.value = false
  }
}

async function addMember() {
  if (!authStore.isAuthenticated) return
  if (!newMember.value.display_name.trim()) {
    toast.error('Display name is required')
    return
  }

  try {
    actionLoading.value = true
    const { data, error } = await supabase.from('members').insert([newMember.value]).select()

    if (error) throw error

    if (data) {
      members.value.push(data[0])
      members.value.sort((a, b) => a.display_name.localeCompare(b.display_name, 'vi'))
    }

    toast.success('Member added successfully')

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
    toast.error(error.message || 'Failed to add member')
  } finally {
    actionLoading.value = false
  }
}

async function deleteMember(id: string, name: string) {
  if (!authStore.isAuthenticated) return
  if (!confirm(`Are you sure you want to delete member "${name}"? This action cannot be undone.`)) {
    return
  }

  try {
    actionLoading.value = true
    const { error } = await supabase.from('members').delete().eq('id', id)

    if (error) throw error

    members.value = members.value.filter((m) => m.id !== id)
    toast.success('Member deleted successfully')
  } catch (error: any) {
    console.error('Error deleting member:', error)
    toast.error(error.message || 'Failed to delete member')
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

    toast.success('Member updated successfully')
    cancelEdit()
  } catch (error) {
    console.error('Error updating member:', error)
    toast.error('Failed to update member')
  }
}

onMounted(fetchMembers)
</script>

<template>
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
    <div class="flex justify-between items-center mb-6">
      <h1 class="text-2xl font-bold text-gray-900">Member Management</h1>
      <button
        v-if="authStore.isAuthenticated && !showAddForm"
        @click="showAddForm = true"
        class="flex items-center px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 transition shadow-sm"
      >
        <UserPlus class="w-5 h-5 mr-2" />
        New Member
      </button>
    </div>

    <!-- Add Member Form -->
    <div
      v-if="showAddForm"
      class="bg-white shadow-sm rounded-lg border border-indigo-100 p-6 mb-8 animate-in fade-in slide-in-from-top-4 duration-300"
    >
      <div class="flex justify-between items-center mb-4">
        <h2 class="text-lg font-semibold text-gray-900">Add New Member</h2>
        <button @click="showAddForm = false" class="text-gray-400 hover:text-gray-600">
          <X class="w-5 h-5" />
        </button>
      </div>
      <form @submit.prevent="addMember" class="grid grid-cols-1 md:grid-cols-4 gap-4 items-end">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Display Name</label>
          <input
            v-model="newMember.display_name"
            type="text"
            required
            class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-2"
            placeholder="Enter name"
          />
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Role</label>
          <select
            v-model="newMember.role"
            class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-3 py-2"
          >
            <option value="member">Member</option>
            <option value="admin">Admin</option>
          </select>
        </div>
        <div class="flex flex-wrap gap-4 mb-2 md:mb-0">
          <label class="flex items-center text-sm text-gray-700 cursor-pointer">
            <input
              v-model="newMember.is_active"
              type="checkbox"
              class="h-4 w-4 text-indigo-600 rounded border-gray-300 mr-2"
            />
            Active
          </label>
          <label class="flex items-center text-sm text-gray-700 cursor-pointer">
            <input
              v-model="newMember.is_permanent"
              type="checkbox"
              class="h-4 w-4 text-indigo-600 rounded border-gray-300 mr-2"
            />
            Permanent
          </label>
          <label
            class="flex items-center text-sm text-indigo-600 font-medium cursor-pointer border-l pl-4 border-gray-200"
          >
            <input
              v-model="createAnother"
              type="checkbox"
              class="h-4 w-4 text-indigo-600 rounded border-gray-300 mr-2"
            />
            Create another
          </label>
        </div>
        <div class="flex gap-2">
          <button
            type="submit"
            :disabled="actionLoading"
            class="flex-1 bg-indigo-600 text-white px-4 py-2 rounded-md hover:bg-indigo-700 transition disabled:opacity-50 flex justify-center items-center"
          >
            <Loader2 v-if="actionLoading" class="w-4 h-4 mr-2 animate-spin" />
            Create
          </button>
          <button
            type="button"
            @click="showAddForm = false"
            class="px-4 py-2 border border-gray-300 rounded-md text-gray-700 hover:bg-gray-50 transition"
          >
            Cancel
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
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Name
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Role
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Active
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Permanent
              </th>
              <th
                v-if="authStore.isAuthenticated"
                scope="col"
                class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider"
              >
                Actions
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
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                <input
                  v-if="editingMemberId === member.id"
                  v-model="editForm.display_name"
                  type="text"
                  class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-2 py-1"
                />
                <span v-else class="font-medium">{{ member.display_name }}</span>
              </td>

              <!-- Role -->
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                <select
                  v-if="editingMemberId === member.id"
                  v-model="editForm.role"
                  class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm border px-2 py-1"
                >
                  <option value="member">Member</option>
                  <option value="admin">Admin</option>
                </select>
                <span
                  v-else
                  :class="[
                    'px-2 py-1 text-xs font-medium rounded-full',
                    member.role === 'admin'
                      ? 'bg-indigo-100 text-indigo-800'
                      : 'bg-gray-100 text-gray-800',
                  ]"
                >
                  {{ member.role }}
                </span>
              </td>

              <!-- Is Active -->
              <td class="px-6 py-4 whitespace-nowrap text-center text-sm text-gray-500">
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
              <td class="px-6 py-4 whitespace-nowrap text-center text-sm text-gray-500">
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
                class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium"
              >
                <div v-if="editingMemberId === member.id" class="flex justify-end gap-2">
                  <button
                    @click="saveEdit(member.id)"
                    class="text-green-600 hover:text-green-900"
                    title="Save"
                  >
                    <Save class="w-5 h-5" />
                  </button>
                  <button
                    @click="cancelEdit"
                    class="text-red-600 hover:text-red-900"
                    title="Cancel"
                  >
                    <X class="w-5 h-5" />
                  </button>
                </div>
                <div v-else class="flex justify-end gap-3">
                  <button
                    @click="startEdit(member)"
                    class="text-indigo-600 hover:text-indigo-900"
                    title="Edit"
                  >
                    <Edit class="w-5 h-5" />
                  </button>
                  <button
                    @click="deleteMember(member.id, member.display_name)"
                    class="text-gray-400 hover:text-red-600"
                    title="Delete"
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

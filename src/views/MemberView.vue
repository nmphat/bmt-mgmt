<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import type { Member } from '@/types'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { Check, X, Edit, Save, Trash2, UserPlus, Loader2, ChevronRight } from 'lucide-vue-next'
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
  if (!authStore.isAdmin) return
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
  if (!authStore.isAdmin) return
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
  if (!authStore.isAdmin) return
  editingMemberId.value = member.id
  editForm.value = { ...member }
}

function cancelEdit() {
  editingMemberId.value = null
  editForm.value = {}
}

async function saveEdit(id: string) {
  if (!authStore.isAdmin) return
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
      <h1 class="text-[20px] font-bold leading-[1.2] text-gray-900">{{ t('member.title') }}</h1>
      <button
        v-if="authStore.isAdmin && !showAddForm"
        @click="showAddForm = true"
        class="flex min-h-11 items-center rounded-xl bg-indigo-600 px-4 text-base font-bold text-white shadow-sm transition hover:bg-indigo-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
      >
        <UserPlus class="w-5 h-5 mr-2" />
        {{ t('member.newName') }}
      </button>
    </div>

    <!-- Add Member Form -->
    <div
      v-if="showAddForm && authStore.isAdmin"
      class="mb-8 rounded-2xl border border-indigo-100 bg-white p-6 shadow-sm animate-in fade-in slide-in-from-top-4 duration-300"
    >
      <div class="flex justify-between items-center mb-4">
        <h2 class="text-[20px] font-bold leading-[1.2] text-gray-900">{{ t('member.addTitle') }}</h2>
        <button
          @click="showAddForm = false"
          class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-xl text-gray-400 transition hover:text-gray-600 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
          :aria-label="t('common.cancel')"
        >
          <X class="w-5 h-5" />
        </button>
      </div>
      <form @submit.prevent="addMember" class="grid grid-cols-1 gap-4 md:grid-cols-4 items-end">
        <div>
          <label class="block text-base font-bold text-gray-700 mb-1">{{
            t('member.displayName')
          }}</label>
          <input
            v-model="newMember.display_name"
            type="text"
            required
            class="block min-h-11 w-full rounded-md border border-gray-300 px-3 py-2 text-base shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
            :placeholder="t('member.namePlaceholder')"
          />
        </div>
        <div>
          <label class="block text-base font-bold text-gray-700 mb-1">{{
            t('member.role')
          }}</label>
          <select
            v-model="newMember.role"
            class="block min-h-11 w-full rounded-md border border-gray-300 px-3 py-2 text-base shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
          >
            <option value="member">{{ t('member.memberRole') }}</option>
            <option value="admin">{{ t('member.adminRole') }}</option>
          </select>
        </div>
        <div class="flex flex-wrap gap-4 mb-2 md:mb-0">
          <label class="flex min-h-11 items-center text-base text-gray-700 cursor-pointer">
            <input
              v-model="newMember.is_active"
              type="checkbox"
              class="h-4 w-4 text-indigo-600 rounded border-gray-300 mr-2"
            />
            {{ t('member.active') }}
          </label>
          <label class="flex min-h-11 items-center text-base text-gray-700 cursor-pointer">
            <input
              v-model="newMember.is_permanent"
              type="checkbox"
              class="h-4 w-4 text-indigo-600 rounded border-gray-300 mr-2"
            />
            {{ t('member.permanent') }}
          </label>
          <label
            class="flex min-h-11 items-center text-base text-indigo-600 font-bold cursor-pointer border-l pl-4 border-gray-200"
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
            class="flex min-h-11 flex-1 items-center justify-center rounded-xl bg-indigo-600 px-4 text-base font-bold text-white transition hover:bg-indigo-700 disabled:opacity-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
          >
            <Loader2 v-if="actionLoading" class="w-4 h-4 mr-2 animate-spin" />
            {{ t('member.create') }}
          </button>
          <button
            type="button"
            @click="showAddForm = false"
            class="min-h-11 rounded-xl border border-gray-300 px-4 text-base font-bold text-gray-700 transition hover:bg-gray-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
          >
            {{ t('common.cancel') }}
          </button>
        </div>
      </form>
    </div>

    <div v-if="loading" class="flex justify-center py-12">
      <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600"></div>
    </div>

    <div v-else class="space-y-4">
      <div
        v-if="members.length === 0"
        class="rounded-2xl border border-gray-200 bg-white p-6 text-center text-base text-gray-600 shadow-sm"
      >
        {{ t('member.emptyState') }}
      </div>

      <div v-else class="space-y-3 md:hidden">
        <article
          v-for="member in members"
          :key="member.id"
          class="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm"
        >
          <form
            v-if="editingMemberId === member.id"
            @submit.prevent="saveEdit(member.id)"
            class="space-y-4 rounded-xl border border-indigo-100 bg-indigo-50/40 p-3"
          >
            <div>
              <label class="mb-1 block text-sm font-bold text-gray-700">
                {{ t('member.displayName') }}
              </label>
              <input
                v-model="editForm.display_name"
                type="text"
                class="block min-h-11 w-full rounded-xl border border-gray-300 px-3 text-base shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
              />
            </div>

            <div>
              <label class="mb-1 block text-sm font-bold text-gray-700">
                {{ t('member.role') }}
              </label>
              <select
                v-model="editForm.role"
                class="block min-h-11 w-full rounded-xl border border-gray-300 px-3 text-base shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
              >
                <option value="member">{{ t('member.memberRole') }}</option>
                <option value="admin">{{ t('member.adminRole') }}</option>
              </select>
            </div>

            <div class="space-y-2">
              <label
                class="flex min-h-11 items-center rounded-xl border border-gray-200 bg-white px-3 text-base text-gray-700"
              >
                <input
                  v-model="editForm.is_active"
                  type="checkbox"
                  class="mr-2 h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                />
                {{ t('member.active') }}
              </label>
              <label
                class="flex min-h-11 items-center rounded-xl border border-gray-200 bg-white px-3 text-base text-gray-700"
              >
                <input
                  v-model="editForm.is_permanent"
                  type="checkbox"
                  class="mr-2 h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                />
                {{ t('member.permanent') }}
              </label>
            </div>

            <div class="grid grid-cols-2 gap-2">
              <button
                type="submit"
                class="inline-flex min-h-11 items-center justify-center rounded-xl bg-green-600 px-4 text-base font-bold text-white transition hover:bg-green-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
              >
                <Save class="mr-2 h-4 w-4" />
                {{ t('common.save') }}
              </button>
              <button
                type="button"
                @click="cancelEdit"
                class="inline-flex min-h-11 items-center justify-center rounded-xl border border-gray-300 bg-white px-4 text-base font-bold text-gray-700 transition hover:bg-gray-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
              >
                <X class="mr-2 h-4 w-4" />
                {{ t('common.cancel') }}
              </button>
            </div>
          </form>

          <div v-else class="space-y-3">
            <div class="flex items-start justify-between gap-3">
              <div>
                <h2 class="text-[20px] font-bold leading-[1.2] text-gray-900">
                  {{ member.display_name }}
                </h2>
                <p class="mt-1 text-sm font-bold text-gray-500">{{ t('member.role') }}</p>
              </div>
              <span
                :class="[
                  'rounded-full px-3 py-1 text-sm font-bold',
                  member.role === 'admin'
                    ? 'bg-indigo-100 text-indigo-800'
                    : 'bg-gray-100 text-gray-800',
                ]"
              >
                {{ member.role === 'admin' ? t('member.adminRole') : t('member.memberRole') }}
              </span>
            </div>

            <div class="flex flex-wrap gap-2">
              <span
                :class="[
                  'rounded-full px-3 py-1 text-sm font-bold',
                  member.is_active ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-700',
                ]"
              >
                {{
                  member.is_active ? t('member.activeStatus') : t('member.inactiveStatus')
                }}
              </span>
              <span
                :class="[
                  'rounded-full px-3 py-1 text-sm font-bold',
                  member.is_permanent
                    ? 'bg-indigo-100 text-indigo-800'
                    : 'bg-gray-100 text-gray-700',
                ]"
              >
                {{
                  member.is_permanent
                    ? t('member.permanentStatus')
                    : t('member.temporaryStatus')
                }}
              </span>
            </div>

            <div class="flex flex-wrap gap-2 pt-1">
              <router-link
                :to="`/member/${member.id}`"
                class="inline-flex min-h-11 flex-1 items-center justify-center rounded-xl border border-indigo-200 px-4 text-base font-bold text-indigo-700 transition hover:bg-indigo-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
                :aria-label="t('member.viewDetailsFor', { name: member.display_name })"
              >
                {{ t('debt.details') }}
                <ChevronRight class="ml-1 h-4 w-4" />
              </router-link>
              <button
                v-if="authStore.isAdmin"
                @click="startEdit(member)"
                class="inline-flex min-h-11 items-center justify-center rounded-xl border border-gray-200 px-4 text-base font-bold text-indigo-700 transition hover:bg-indigo-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
                :aria-label="t('member.editMember', { name: member.display_name })"
              >
                <Edit class="mr-2 h-4 w-4" />
                {{ t('common.edit') }}
              </button>
              <button
                v-if="authStore.isAdmin"
                @click="deleteMember(member.id, member.display_name)"
                class="inline-flex min-h-11 items-center justify-center rounded-xl border border-red-200 px-4 text-base font-bold text-red-600 transition hover:bg-red-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
                :aria-label="t('member.deleteMember', { name: member.display_name })"
              >
                <Trash2 class="mr-2 h-4 w-4" />
                {{ t('common.delete') }}
              </button>
            </div>
          </div>
        </article>
      </div>

      <div
        v-if="members.length > 0"
        class="hidden overflow-x-auto md:block rounded-lg border border-gray-100 bg-white shadow-sm"
      >
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th
                scope="col"
                class="px-6 py-3 text-left text-sm font-bold text-gray-500 uppercase tracking-wider"
              >
                {{ t('member.name') }}
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-left text-sm font-bold text-gray-500 uppercase tracking-wider"
              >
                {{ t('member.role') }}
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-center text-sm font-bold text-gray-500 uppercase tracking-wider"
              >
                {{ t('member.active') }}
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-center text-sm font-bold text-gray-500 uppercase tracking-wider"
              >
                {{ t('member.permanent') }}
              </th>
              <th
                scope="col"
                class="px-6 py-3 text-right text-sm font-bold text-gray-500 uppercase tracking-wider"
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
                <span v-else class="font-bold">{{ member.display_name }}</span>
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
                    'px-2 py-1 text-sm font-bold rounded-full',
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
              <td class="px-6 py-4 whitespace-nowrap text-right text-base font-bold">
                <div v-if="editingMemberId === member.id" class="flex justify-end gap-2">
                  <button
                    @click="saveEdit(member.id)"
                    class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-xl text-green-600 hover:text-green-900 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
                    :title="t('common.save')"
                    :aria-label="t('common.save')"
                  >
                    <Save class="w-5 h-5" />
                  </button>
                  <button
                    @click="cancelEdit"
                    class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-xl text-red-600 hover:text-red-900 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
                    :title="t('common.cancel')"
                    :aria-label="t('common.cancel')"
                  >
                    <X class="w-5 h-5" />
                  </button>
                </div>
                <div v-else class="flex justify-end gap-3">
                  <router-link
                    :to="`/member/${member.id}`"
                    class="inline-flex items-center text-indigo-600 hover:text-indigo-900"
                    :title="t('debt.details')"
                  >
                    {{ t('debt.details') }}
                    <ChevronRight class="w-4 h-4 ml-1" />
                  </router-link>
                  <button
                    v-if="authStore.isAdmin"
                    @click="startEdit(member)"
                    class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-xl text-indigo-600 hover:text-indigo-900 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
                    :title="t('common.edit')"
                    :aria-label="t('member.editMember', { name: member.display_name })"
                  >
                    <Edit class="w-5 h-5" />
                  </button>
                  <button
                    v-if="authStore.isAdmin"
                    @click="deleteMember(member.id, member.display_name)"
                    class="inline-flex min-h-11 min-w-11 items-center justify-center rounded-xl text-gray-400 hover:text-red-600 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
                    :title="t('common.delete')"
                    :aria-label="t('member.deleteMember', { name: member.display_name })"
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

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import type { Member } from '@/types'
import { useAuthStore } from '@/stores/auth'
import { useLangStore } from '@/stores/lang'
import { Check, X, Edit, Save, Trash2, UserPlus, ChevronRight } from 'lucide-vue-next'
import { useToast } from 'vue-toastification'
import { computed } from 'vue'
import Button from '@/components/ui/Button.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import FormField from '@/components/ui/FormField.vue'
import IconButton from '@/components/ui/IconButton.vue'
import Input from '@/components/ui/Input.vue'
import MemberActiveBadge from '@/components/ui/MemberActiveBadge.vue'
import PageHeader from '@/components/ui/PageHeader.vue'
import RoleBadge from '@/components/ui/RoleBadge.vue'
import Select from '@/components/ui/Select.vue'
import Spinner from '@/components/ui/Spinner.vue'
import TableHeaderCell from '@/components/ui/TableHeaderCell.vue'

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

function isDuplicateName(name: string, excludeId?: string) {
  const normalized = name.trim().toLowerCase()
  return members.value.some(
    (m) => m.id !== excludeId && m.display_name.trim().toLowerCase() === normalized,
  )
}

async function addMember() {
  if (!authStore.isAdmin) return
  const trimmedName = newMember.value.display_name.trim()
  if (!trimmedName) {
    toast.error(t.value('member.nameRequired'))
    return
  }
  if (isDuplicateName(trimmedName)) {
    toast.error(t.value('member.duplicateName'))
    return
  }

  try {
    actionLoading.value = true
    const { data, error } = await supabase
      .from('members')
      .insert([{ ...newMember.value, display_name: trimmedName }])
      .select()

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
  const trimmedName = (editForm.value.display_name || '').trim()
  if (!trimmedName) {
    toast.error(t.value('member.nameRequired'))
    return
  }
  if (isDuplicateName(trimmedName, id)) {
    toast.error(t.value('member.duplicateName'))
    return
  }
  try {
    const updates = {
      display_name: trimmedName,
      role: editForm.value.role,
      is_active: editForm.value.is_active,
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
    <PageHeader layout="Title Action" :title="t('member.title')" class="mb-6">
      <template #actions>
        <Button
          v-if="authStore.isAdmin && !showAddForm"
          size="Default"
          variant="Primary"
          :leading-icon="UserPlus"
          @click="showAddForm = true"
        >
          {{ t('member.newName') }}
        </Button>
      </template>
    </PageHeader>

    <!-- Add Member Form -->
    <div
      v-if="showAddForm && authStore.isAdmin"
      class="mb-8 flex flex-col gap-4 rounded-xl border border-line-brand-muted bg-surface-card p-6 shadow-sm animate-in fade-in slide-in-from-top-4 duration-300"
    >
      <div class="flex justify-between items-center">
        <h2 class="text-xl font-bold text-fg-primary">
          {{ t('member.addTitle') }}
        </h2>
        <IconButton
          :icon="X"
          :label="t('common.cancel')"
          size="Default"
          shape="Square"
          variant="Ghost"
          @click="showAddForm = false"
        />
      </div>
      <form @submit.prevent="addMember" class="grid grid-cols-1 gap-4 md:grid-cols-4 items-end">
        <FormField :label="t('member.displayName')" v-slot="{ controlProps }">
          <Input
            v-model="newMember.display_name"
            v-bind="controlProps"
            size="Default"
            type="text"
            required
            :placeholder="t('member.namePlaceholder')"
          />
        </FormField>
        <FormField :label="t('member.role')" control="Select" v-slot="{ controlProps }">
          <Select v-model="newMember.role" v-bind="controlProps" size="Default">
            <option value="member">{{ t('member.memberRole') }}</option>
            <option value="admin">{{ t('member.adminRole') }}</option>
          </Select>
        </FormField>
        <div class="flex flex-wrap items-center gap-4 mb-2 md:mb-0">
          <label class="flex h-11 items-center gap-2 text-base text-fg-secondary cursor-pointer">
            <Checkbox v-model="newMember.is_active" />
            {{ t('member.active') }}
          </label>
          <label
            class="flex h-11 items-center gap-2 border-l border-line-divider pl-4 font-bold text-fg-brand cursor-pointer"
          >
            <Checkbox v-model="createAnother" />
            {{ t('member.createAnother') }}
          </label>
        </div>
        <div class="flex gap-2">
          <Button
            type="submit"
            size="Default"
            variant="Primary"
            :disabled="actionLoading"
            :loading="actionLoading"
            class="flex-1"
          >
            {{ t('member.create') }}
          </Button>
          <Button size="Default" variant="Secondary" @click="showAddForm = false">
            {{ t('common.cancel') }}
          </Button>
        </div>
      </form>
    </div>

    <div v-if="loading" class="flex justify-center py-12">
      <Spinner size="48" />
    </div>

    <div v-else class="space-y-4">
      <EmptyState v-if="members.length === 0" variant="Card" align="Center">
        {{ t('member.emptyState') }}
      </EmptyState>

      <div v-else class="space-y-3 md:hidden">
        <article
          v-for="member in members"
          :key="member.id"
          class="flex flex-col gap-3 rounded-xl border border-line-divider bg-surface-card p-4 shadow-sm"
        >
          <form
            v-if="editingMemberId === member.id"
            @submit.prevent="saveEdit(member.id)"
            class="flex flex-col gap-4 rounded-xl border border-line-brand-muted bg-surface-brand-subtle p-3"
          >
            <FormField :label="t('member.displayName')" v-slot="{ controlProps }">
              <Input
                v-model="editForm.display_name"
                v-bind="controlProps"
                size="Default"
                type="text"
              />
            </FormField>

            <FormField :label="t('member.role')" control="Select" v-slot="{ controlProps }">
              <Select v-model="editForm.role" v-bind="controlProps" size="Default">
                <option value="member">{{ t('member.memberRole') }}</option>
                <option value="admin">{{ t('member.adminRole') }}</option>
              </Select>
            </FormField>

            <div class="space-y-2">
              <label
                class="flex h-11 items-center gap-2 rounded-xl border border-line-divider bg-surface-card px-3 text-base text-fg-secondary cursor-pointer"
              >
                <Checkbox v-model="editForm.is_active" />
                {{ t('member.active') }}
              </label>
            </div>

            <div class="grid grid-cols-2 gap-2">
              <Button type="submit" size="Default" variant="Success" :leading-icon="Save">
                {{ t('common.save') }}
              </Button>
              <Button size="Default" variant="Secondary" :leading-icon="X" @click="cancelEdit">
                {{ t('common.cancel') }}
              </Button>
            </div>
          </form>

          <div v-else class="flex flex-col gap-3">
            <div class="flex items-start justify-between gap-3">
              <div class="flex flex-col gap-1">
                <h2 class="text-xl font-bold text-fg-primary">
                  {{ member.display_name }}
                </h2>
                <p class="text-sm font-bold text-fg-muted">{{ t('member.role') }}</p>
              </div>
              <RoleBadge :role="member.role === 'admin' ? 'Admin' : 'Member'" />
            </div>

            <div class="flex flex-wrap gap-2">
              <MemberActiveBadge :active="member.is_active" />
            </div>

            <div class="flex flex-col gap-2">
              <div class="flex gap-2">
                <Button
                  as="RouterLink"
                  :to="`/member/${member.id}`"
                  size="Default"
                  variant="Outline Brand"
                  :trailing-icon="ChevronRight"
                  class="flex-1"
                  :aria-label="t('member.viewDetailsFor', { name: member.display_name })"
                >
                  {{ t('debt.details') }}
                </Button>
                <Button
                  v-if="authStore.isAdmin"
                  size="Default"
                  variant="Outline Brand"
                  :leading-icon="Edit"
                  class="flex-1"
                  :aria-label="t('member.editMember', { name: member.display_name })"
                  @click="startEdit(member)"
                >
                  {{ t('common.edit') }}
                </Button>
              </div>
              <Button
                v-if="authStore.isAdmin"
                size="Default"
                variant="Outline Danger"
                :leading-icon="Trash2"
                class="w-full"
                :aria-label="t('member.deleteMember', { name: member.display_name })"
                @click="deleteMember(member.id, member.display_name)"
              >
                {{ t('common.delete') }}
              </Button>
            </div>
          </div>
        </article>
      </div>

      <div
        v-if="members.length > 0"
        class="hidden overflow-x-auto md:block rounded-lg border border-line-divider bg-surface-card shadow-sm"
      >
        <table class="min-w-full">
          <thead>
            <tr>
              <TableHeaderCell>{{ t('member.name') }}</TableHeaderCell>
              <TableHeaderCell>{{ t('member.role') }}</TableHeaderCell>
              <TableHeaderCell align="Center">{{ t('member.active') }}</TableHeaderCell>
              <TableHeaderCell align="Right">{{ t('common.actions') }}</TableHeaderCell>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="member in members"
              :key="member.id"
              class="border-b border-line-divider last:border-b-0"
              :class="editingMemberId === member.id && 'bg-surface-subtle'"
            >
              <!-- Name -->
              <td class="px-6 py-4 whitespace-nowrap text-base text-fg-primary">
                <Input
                  v-if="editingMemberId === member.id"
                  v-model="editForm.display_name"
                  size="Small"
                  type="text"
                  :aria-label="t('member.displayName')"
                />
                <span v-else class="font-bold">{{ member.display_name }}</span>
              </td>

              <!-- Role -->
              <td class="px-6 py-4 whitespace-nowrap text-base text-fg-muted">
                <Select
                  v-if="editingMemberId === member.id"
                  v-model="editForm.role"
                  size="Small"
                  :aria-label="t('member.role')"
                >
                  <option value="member">{{ t('member.memberRole') }}</option>
                  <option value="admin">{{ t('member.adminRole') }}</option>
                </Select>
                <RoleBadge v-else :role="member.role === 'admin' ? 'Admin' : 'Member'" />
              </td>

              <!-- Is Active -->
              <td class="px-6 py-4 whitespace-nowrap text-base text-center text-fg-muted">
                <div v-if="editingMemberId === member.id" class="flex justify-center">
                  <Checkbox v-model="editForm.is_active" />
                </div>
                <div v-else>
                  <Check v-if="member.is_active" class="w-5 h-5 text-fg-success-soft mx-auto" />
                  <X v-else class="w-5 h-5 text-fg-faint mx-auto" />
                </div>
              </td>

              <!-- Actions -->
              <td class="px-6 py-4 whitespace-nowrap text-base text-right">
                <div v-if="editingMemberId === member.id" class="flex justify-end gap-3">
                  <IconButton
                    :icon="Save"
                    :label="t('common.save')"
                    :title="t('common.save')"
                    size="Default"
                    shape="Square"
                    variant="Ghost Success"
                    @click="saveEdit(member.id)"
                  />
                  <IconButton
                    :icon="X"
                    :label="t('common.cancel')"
                    :title="t('common.cancel')"
                    size="Default"
                    shape="Square"
                    variant="Ghost Danger"
                    @click="cancelEdit"
                  />
                </div>
                <div v-else class="flex justify-end items-center gap-3">
                  <Button
                    as="RouterLink"
                    :to="`/member/${member.id}`"
                    size="Small"
                    variant="Ghost"
                    :trailing-icon="ChevronRight"
                    :title="t('debt.details')"
                  >
                    {{ t('debt.details') }}
                  </Button>
                  <IconButton
                    v-if="authStore.isAdmin"
                    :icon="Edit"
                    :label="t('member.editMember', { name: member.display_name })"
                    :title="t('common.edit')"
                    size="Default"
                    shape="Square"
                    variant="Ghost Brand"
                    @click="startEdit(member)"
                  />
                  <IconButton
                    v-if="authStore.isAdmin"
                    :icon="Trash2"
                    :label="t('member.deleteMember', { name: member.display_name })"
                    :title="t('common.delete')"
                    size="Default"
                    shape="Square"
                    variant="Ghost"
                    @click="deleteMember(member.id, member.display_name)"
                  />
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>

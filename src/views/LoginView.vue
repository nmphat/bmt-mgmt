<script setup lang="ts">
import { ref, computed } from 'vue'
import { supabase } from '@/lib/supabase'
import { useRoute, useRouter } from 'vue-router'
import { useLangStore } from '@/stores/lang'
import { useToast } from 'vue-toastification'
import Button from '@/components/ui/Button.vue'
import FieldMessage from '@/components/ui/FieldMessage.vue'
import Input from '@/components/ui/Input.vue'
import PageHeader from '@/components/ui/PageHeader.vue'

const router = useRouter()
const route = useRoute()
const langStore = useLangStore()
const toast = useToast()
const t = computed(() => langStore.t)
const email = ref('')
const password = ref('')
const loading = ref(false)
const errorMsg = ref('')
const redirectPath = computed(() =>
  typeof route.query.redirect === 'string' && route.query.redirect.startsWith('/')
    ? route.query.redirect
    : '/',
)
const signInTitle = computed(() => {
  if (redirectPath.value === '/create-session') return t.value('auth.signInToCreateSession')
  if (redirectPath.value === '/settings') return t.value('auth.signInToSettings')
  if (route.query.reason === 'admin') return t.value('auth.signInToAdmin')
  return t.value('auth.signInTitle')
})

async function handleLogin() {
  try {
    loading.value = true
    errorMsg.value = ''
    const { error } = await supabase.auth.signInWithPassword({
      email: email.value,
      password: password.value,
    })
    if (error) throw error
    router.push(redirectPath.value)
  } catch (error: any) {
    errorMsg.value = error.message || t.value('toast.loginError')
    toast.error(errorMsg.value)
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div
    class="min-h-screen flex items-center justify-center bg-surface-page px-4 py-12 sm:px-6 lg:px-8"
  >
    <div class="max-w-md w-full space-y-8">
      <PageHeader
        layout="Centered"
        :level="2"
        :title="signInTitle"
        :subtitle="t('auth.signInSubtitle')"
      />
      <form class="space-y-6" @submit.prevent="handleLogin">
        <div class="space-y-3">
          <div>
            <label for="email-address" class="sr-only">{{ t('auth.emailPlaceholder') }}</label>
            <Input
              v-model="email"
              size="Default"
              id="email-address"
              name="email"
              type="email"
              autocomplete="email"
              required
              :placeholder="t('auth.emailPlaceholder')"
            />
          </div>
          <div>
            <label for="password" class="sr-only">{{ t('auth.passwordPlaceholder') }}</label>
            <Input
              v-model="password"
              size="Default"
              id="password"
              name="password"
              type="password"
              autocomplete="current-password"
              required
              :placeholder="t('auth.passwordPlaceholder')"
            />
          </div>
        </div>

        <FieldMessage v-if="errorMsg" tone="Error" align="Center">
          {{ errorMsg }}
        </FieldMessage>

        <div>
          <Button type="submit" size="Default" variant="Primary" :disabled="loading" class="w-full">
            {{ loading ? t('auth.signingIn') : t('auth.signInButton') }}
          </Button>
        </div>
      </form>
    </div>
  </div>
</template>

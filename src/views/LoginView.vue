<script setup lang="ts">
import { ref, computed } from 'vue'
import { supabase } from '@/lib/supabase'
import { useRoute, useRouter } from 'vue-router'
import { useLangStore } from '@/stores/lang'
import { useToast } from 'vue-toastification'

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
  <div class="min-h-screen flex items-center justify-center bg-gray-50 px-4 py-12 sm:px-6 lg:px-8">
    <div class="max-w-md w-full space-y-8">
      <div>
        <h2 class="mt-6 text-center text-[20px] font-bold leading-[1.2] text-gray-900">
          {{ signInTitle }}
        </h2>
        <p class="mt-3 text-center text-sm text-gray-600">
          {{ t('auth.signInSubtitle') }}
        </p>
      </div>
      <form class="mt-8 space-y-6" @submit.prevent="handleLogin">
        <div class="rounded-md shadow-sm -space-y-px">
          <div>
            <label for="email-address" class="sr-only">{{ t('auth.emailPlaceholder') }}</label>
            <input
              v-model="email"
              id="email-address"
              name="email"
              type="email"
              autocomplete="email"
              required
              class="relative block min-h-11 w-full appearance-none rounded-none rounded-t-md border border-gray-300 px-3 py-2 text-base text-gray-900 placeholder-gray-500 focus:z-10 focus:border-indigo-500 focus:outline-none focus:ring-indigo-500 sm:text-sm"
              :placeholder="t('auth.emailPlaceholder')"
            />
          </div>
          <div>
            <label for="password" class="sr-only">{{ t('auth.passwordPlaceholder') }}</label>
            <input
              v-model="password"
              id="password"
              name="password"
              type="password"
              autocomplete="current-password"
              required
              class="relative block min-h-11 w-full appearance-none rounded-none rounded-b-md border border-gray-300 px-3 py-2 text-base text-gray-900 placeholder-gray-500 focus:z-10 focus:border-indigo-500 focus:outline-none focus:ring-indigo-500 sm:text-sm"
              :placeholder="t('auth.passwordPlaceholder')"
            />
          </div>
        </div>

        <div v-if="errorMsg" class="text-red-500 text-sm text-center">
          {{ errorMsg }}
        </div>

        <div>
          <button
            type="submit"
            :disabled="loading"
            class="group relative flex min-h-11 w-full justify-center rounded-md border border-transparent bg-indigo-600 px-4 py-2 text-sm font-bold text-white hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 disabled:opacity-50"
          >
            {{ loading ? t('auth.signingIn') : t('auth.signInButton') }}
          </button>
        </div>
      </form>
    </div>
  </div>
</template>

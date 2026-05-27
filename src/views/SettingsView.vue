<script setup lang="ts">
import { computed } from 'vue'
import { ChevronLeft, Landmark } from 'lucide-vue-next'
import { BANK_INFO } from '@/types'
import { useLangStore } from '@/stores/lang'

const langStore = useLangStore()
const t = computed(() => langStore.t)
</script>

<template>
  <div class="mx-auto max-w-3xl px-4 py-6 sm:px-6 lg:px-8">
    <div class="mb-6">
      <router-link
        to="/"
        class="inline-flex min-h-11 items-center text-sm font-bold text-indigo-600 transition hover:text-indigo-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 focus-visible:ring-offset-2"
      >
        <ChevronLeft class="mr-1 h-5 w-5" aria-hidden="true" />
        {{ t('common.backToHome') }}
      </router-link>
    </div>

    <section class="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm sm:p-6">
      <div class="mb-6 flex items-start gap-3">
        <div
          class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-indigo-50 text-indigo-600"
        >
          <Landmark class="h-5 w-5" aria-hidden="true" />
        </div>
        <div>
          <h1 class="text-[22px] font-bold leading-tight text-gray-900">
            {{ t('settings.title') }}
          </h1>
          <p class="mt-1 text-sm leading-6 text-gray-600">
            {{ t('settings.subtitle') }}
          </p>
        </div>
      </div>

      <div class="rounded-2xl border border-indigo-100 bg-indigo-50/70 p-4">
        <h2 class="text-base font-bold text-gray-900">
          {{ t('settings.paymentTitle') }}
        </h2>

        <dl class="mt-4 space-y-3">
          <div class="rounded-xl bg-white px-4 py-3">
            <dt class="text-xs font-bold uppercase tracking-wide text-gray-500">
              {{ t('settings.bank') }}
            </dt>
            <dd class="mt-1 text-base font-bold text-gray-900">
              {{ BANK_INFO.BANK_NAME }} ({{ BANK_INFO.BANK_ID }})
            </dd>
          </div>

          <div class="rounded-xl bg-white px-4 py-3">
            <dt class="text-xs font-bold uppercase tracking-wide text-gray-500">
              {{ t('settings.accountNumber') }}
            </dt>
            <dd class="mt-1 text-base font-bold text-gray-900">
              {{ BANK_INFO.ACCOUNT_NO }}
            </dd>
          </div>

          <div class="rounded-xl bg-white px-4 py-3">
            <dt class="text-xs font-bold uppercase tracking-wide text-gray-500">
              {{ t('settings.qrTemplate') }}
            </dt>
            <dd class="mt-1 text-base font-bold text-gray-900">
              {{ BANK_INFO.TEMPLATE }}
            </dd>
          </div>
        </dl>

        <p class="mt-4 text-sm leading-6 text-indigo-900">
          {{ t('settings.qrNote') }}
        </p>
      </div>
    </section>
  </div>
</template>

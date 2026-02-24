<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { Share2, Copy, Check, Loader2, ArrowLeft } from 'lucide-vue-next'
import { formatCurrency } from '@/utils/formatters'
import { useLangStore } from '@/stores/lang'
import { ref } from 'vue'

const route = useRoute()
const langStore = useLangStore()
const t = computed(() => langStore.t)

const code = computed(() => (route.query.code as string) || '')
const amount = computed(() => Number(route.query.amount) || 0)

// Bank Info (Should ideally be shared/centralized)
const BANK_INFO_TPB = { BANK_ID: 'TPB', ACCOUNT_NO: '10003392871', TEMPLATE: 'compact2' }
const ACTIVE_BANK = BANK_INFO_TPB

const qrUrl = computed(() => {
  const addInfo = encodeURIComponent(`${code.value}`)
  return `https://img.vietqr.io/image/${ACTIVE_BANK.BANK_ID}-${ACTIVE_BANK.ACCOUNT_NO}-${ACTIVE_BANK.TEMPLATE}.png?amount=${amount.value}&addInfo=${addInfo}`
})

const copied = ref(false)
const copyCode = async () => {
  try {
    await navigator.clipboard.writeText(code.value)
    copied.value = true
    setTimeout(() => (copied.value = false), 2000)
  } catch (err) {
    console.error('Copy failed:', err)
  }
}

const isSharing = ref(false)
const sharePayment = async () => {
  if (isSharing.value) return
  isSharing.value = true

  const shareTitle = t.value('payment.shareTitle', { code: code.value })
  const shareText = t.value('payment.shareText', {
    amount: formatCurrency(amount.value),
    code: code.value,
  })

  try {
    const response = await fetch(qrUrl.value)
    const blob = await response.blob()
    const file = new File([blob], `badminton_qr_${code.value}.png`, { type: 'image/png' })

    if (navigator.share) {
      const shareData: any = {
        title: shareTitle,
        text: shareText,
        url: window.location.href,
      }

      if (navigator.canShare && navigator.canShare({ files: [file] })) {
        shareData.files = [file]
      }

      await navigator.share(shareData)
    } else {
      await navigator.clipboard.writeText(`${shareTitle}\n${shareText}\n${window.location.href}`)
      alert(t.value('payment.copied'))
    }
  } catch (err) {
    console.error('Share failed:', err)
  } finally {
    isSharing.value = false
  }
}

onMounted(() => {
  // Set meta title for sharing
  const title = t.value('payment.shareTitle', { code: code.value })
  document.title = title

  // Try to set meta tags dynamically
  const updateMeta = (attr: 'property' | 'name', key: string, content: string) => {
    const selector = `meta[${attr}="${key}"]`
    let el = document.querySelector(selector)
    if (!el) {
      el = document.createElement('meta')
      el.setAttribute(attr, key)
      document.head.appendChild(el)
    }
    el.setAttribute('content', content)
  }

  updateMeta('property', 'og:title', String(title))
  updateMeta(
    'property',
    'og:description',
    String(
      t.value('payment.shareText', {
        amount: formatCurrency(amount.value),
        code: code.value,
      }),
    ),
  )
  updateMeta('property', 'og:image', String(qrUrl.value))
  updateMeta('property', 'og:url', window.location.href)
  updateMeta('property', 'og:type', 'website')
})
</script>

<template>
  <div class="min-h-screen bg-white dark:bg-gray-900 flex flex-col items-center p-4">
    <div
      class="w-full max-w-md bg-white dark:bg-gray-800 rounded-3xl overflow-hidden mt-4 sm:mt-10"
    >
      <!-- Header -->
      <div class="p-6 text-center border-b border-gray-100 dark:border-gray-700">
        <h1 class="text-2xl font-black text-gray-900 dark:text-white uppercase tracking-tight">
          {{ t('payment.qrTitle') }}
        </h1>
        <p
          class="text-gray-500 dark:text-gray-400 mt-1 uppercase text-xs font-bold tracking-widest"
        >
          Sân cầu lông
        </p>
      </div>

      <!-- QR Section -->
      <div class="p-8 flex flex-col items-center bg-gray-50/50 dark:bg-gray-900/20">
        <div class="relative group">
          <img
            :src="qrUrl"
            alt="VietQR"
            class="w-72 h-72 object-contain border-4 border-white dark:border-gray-700 rounded-2xl shadow-xl transition-all duration-300 transform group-hover:scale-[1.02]"
          />
          <div class="absolute -bottom-4 left-1/2 -translate-x-1/2">
            <div
              class="flex items-center gap-2 px-4 py-2 bg-white dark:bg-gray-800 border-2 border-indigo-500 rounded-full text-xs font-black text-indigo-600 shadow-lg whitespace-nowrap"
            >
              <Loader2 class="w-3.5 h-3.5 animate-spin" />
              {{ t('payment.waitingTransfer') }}
            </div>
          </div>
        </div>
      </div>

      <!-- Details -->
      <div class="p-8 flex flex-col items-center gap-8">
        <div class="text-center">
          <p
            class="text-sm font-bold text-gray-400 dark:text-gray-500 uppercase tracking-widest mb-2"
          >
            {{ t('payment.totalAmount') }}
          </p>
          <div class="text-4xl font-black text-indigo-600 dark:text-indigo-400 tracking-tighter">
            {{ formatCurrency(amount) }}
          </div>
        </div>

        <!-- Transfer Content -->
        <div class="w-full flex flex-col gap-3">
          <p
            class="text-xs font-bold text-gray-400 dark:text-gray-500 uppercase tracking-widest text-center"
          >
            {{ t('payment.transferContent') }}
          </p>
          <button
            @click="copyCode"
            class="group w-full flex items-center justify-between p-4 rounded-2xl border-2 transition-all duration-200 active:scale-[0.98]"
            :class="
              copied
                ? 'bg-emerald-50 border-emerald-500'
                : 'bg-indigo-50/30 border-indigo-100 hover:border-indigo-300 dark:bg-gray-700 dark:border-gray-600'
            "
          >
            <span
              class="text-xl font-black font-mono tracking-widest"
              :class="copied ? 'text-emerald-700' : 'text-indigo-900 dark:text-white'"
            >
              {{ code }}
            </span>
            <div class="p-2 rounded-xl bg-white dark:bg-gray-600 shadow-sm">
              <Check v-if="copied" class="w-5 h-5 text-emerald-600" />
              <Copy v-else class="w-5 h-5 text-indigo-600 dark:text-indigo-400" />
            </div>
          </button>
        </div>

        <button
          @click="sharePayment"
          :disabled="isSharing"
          class="w-full py-4 bg-indigo-600 hover:bg-indigo-700 disabled:bg-indigo-400 text-white rounded-2xl font-black text-lg shadow-xl shadow-indigo-100 dark:shadow-none transition-all active:scale-[0.98] flex items-center justify-center gap-3"
        >
          <Loader2 v-if="isSharing" class="w-6 h-6 animate-spin" />
          <Share2 v-else class="w-6 h-6" />
          {{ t('payment.share') }}
        </button>
      </div>

      <!-- Footer Instructions -->
      <div
        class="p-6 bg-gray-50 dark:bg-gray-900/50 border-t border-gray-100 dark:border-gray-700 text-center"
      >
        <p class="text-sm text-gray-500 dark:text-gray-400 italic">
          {{ t('payment.step3') }}
        </p>
      </div>
    </div>

    <!-- Back Button -->
    <router-link
      to="/"
      class="mt-8 flex items-center gap-2 text-gray-500 hover:text-indigo-600 font-bold transition-colors"
    >
      <ArrowLeft class="w-4 h-4" />
      {{ t('common.backToHome') }}
    </router-link>
  </div>
</template>

<style scoped>
.font-black {
  font-weight: 950;
}
</style>

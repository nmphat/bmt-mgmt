<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { Share2, Copy, Check, Loader2, ArrowLeft } from 'lucide-vue-next'
import { formatCurrency } from '@/utils/formatters'
import { useLangStore } from '@/stores/lang'
import { useBankConfig } from '@/composables/useBankConfig'
import { ref } from 'vue'
import { useToast } from 'vue-toastification'
import Button from '@/components/ui/Button.vue'

const route = useRoute()
const langStore = useLangStore()
const t = computed(() => langStore.t)
const toast = useToast()

const code = computed(() => (route.query.code as string) || '')
const amount = computed(() => Number(route.query.amount) || 0)

// Bank config — reads from DB, falls back to hardcoded TPBank
const { activeBank } = useBankConfig()

const qrUrl = computed(() => {
  const addInfo = encodeURIComponent(`${code.value}`)
  return `https://img.vietqr.io/image/${activeBank.value.bank_id}-${activeBank.value.account_number}-${activeBank.value.template ?? 'compact2'}.png?amount=${amount.value}&addInfo=${addInfo}`
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
      toast.success(t.value('payment.copied'))
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
  <div class="flex min-h-screen flex-col items-center bg-surface-card p-4">
    <div
      data-ds="Payment Page Card"
      data-ds-style="Default"
      class="mt-4 w-full max-w-md overflow-hidden rounded-3xl bg-surface-card sm:mt-10"
    >
      <!-- Header -->
      <div class="flex flex-col items-center gap-1 border-b border-line-divider p-6 text-center">
        <h1 class="text-2xl font-extrabold uppercase tracking-tight text-fg-primary">
          {{ t('payment.qrTitle') }}
        </h1>
        <p class="text-xs font-bold uppercase tracking-widest text-fg-muted">Sân cầu lông</p>
      </div>

      <!-- QR Section -->
      <div class="flex flex-col items-center gap-2 bg-surface-subtle p-8">
        <img
          data-ds="QR Image"
          data-ds-style="Raised"
          :src="qrUrl"
          alt="VietQR"
          class="size-72 rounded-xl border-4 border-line-inverse object-contain shadow-xl transition duration-300 hover:scale-[1.02]"
        />
        <div
          data-ds="Waiting Pill"
          data-ds-style="Default"
          class="flex items-center gap-2 whitespace-nowrap rounded-full border-2 border-line-brand-emphasis bg-surface-card px-4 py-2 text-xs font-extrabold text-fg-brand shadow-lg"
        >
          <Loader2 aria-hidden="true" class="size-3.5 animate-spin" />
          {{ t('payment.waitingTransfer') }}
        </div>
      </div>

      <!-- Details -->
      <div class="flex flex-col items-center gap-8 p-8">
        <div
          data-ds="Amount Panel"
          data-ds-tone="Hero"
          class="flex w-full flex-col items-center gap-1 p-4"
        >
          <p class="text-sm font-bold uppercase tracking-widest text-fg-disabled">
            {{ t('payment.totalAmount') }}
          </p>
          <div class="text-3xl font-bold text-fg-brand-strong">
            {{ formatCurrency(amount) }}
          </div>
        </div>

        <!-- Transfer Content -->
        <div class="flex w-full flex-col gap-3">
          <p class="text-center text-xs font-bold uppercase tracking-widest text-fg-disabled">
            {{ t('payment.transferContent') }}
          </p>
          <button
            type="button"
            data-ds="Transfer Code Card"
            data-ds-style="Page"
            :data-ds-state="copied ? 'Copied' : 'Default'"
            class="flex w-full items-center justify-between gap-3 rounded-xl border-2 p-4 transition active:scale-[0.98] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-line-focus focus-visible:ring-offset-2"
            :class="
              copied
                ? 'border-line-success bg-status-success-subtle'
                : 'border-line-brand-muted bg-surface-brand-subtle hover:border-line-brand'
            "
            @click="copyCode"
          >
            <span
              class="font-mono text-xl font-extrabold tracking-widest"
              :class="copied ? 'text-fg-success' : 'text-fg-brand-deep'"
            >
              {{ code }}
            </span>
            <div
              data-ds="Icon Tile"
              :data-ds-style="copied ? 'White Raised Done' : 'White Raised'"
              class="rounded-xl bg-surface-card p-2 shadow-sm"
            >
              <Check v-if="copied" class="size-5 text-fg-success" />
              <Copy v-else class="size-5 text-fg-brand" />
            </div>
          </button>
        </div>

        <Button
          size="Large"
          variant="Primary"
          class="w-full active:scale-[0.98]"
          :leading-icon="Share2"
          :loading="isSharing"
          :disabled="isSharing"
          @click="sharePayment"
        >
          {{ t('payment.share') }}
        </Button>
      </div>

      <!-- Footer Instructions -->
      <div class="border-t border-line-divider bg-surface-subtle p-6 text-center">
        <p class="text-sm italic text-fg-muted">
          {{ t('payment.step3') }}
        </p>
      </div>
    </div>

    <!-- Back Button -->
    <router-link
      to="/"
      class="mt-8 inline-flex items-center gap-2 rounded-control font-bold text-fg-muted transition-colors hover:text-fg-brand focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-line-focus focus-visible:ring-offset-2"
    >
      <ArrowLeft class="size-4" />
      {{ t('common.backToHome') }}
    </router-link>
  </div>
</template>

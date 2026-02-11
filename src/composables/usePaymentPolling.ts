import { ref, onUnmounted, toValue, type MaybeRefOrGetter } from 'vue'
import { supabase } from '@/lib/supabase'

export interface PaymentMemberDetail {
  name: string
  amount: number
  status: 'paid' | 'partial' | 'pending'
}

export interface PollResult {
  found: boolean
  total: number
  paid: number
  success: boolean
  details: PaymentMemberDetail[]
}

export function usePaymentPolling(codeSource: MaybeRefOrGetter<string>, intervalMs = 2_000) {
  const data = ref<PollResult>({
    found: false,
    total: 0,
    paid: 0,
    success: false,
    details: [],
  })
  const isPolling = ref(false)
  const error = ref<string | null>(null)

  let timer: ReturnType<typeof setInterval> | null = null

  const checkStatus = async () => {
    const code = toValue(codeSource)
    if (!code) return

    try {
      const { data: result, error: rpcError } = await supabase.rpc('check_qr_status', {
        p_code: code,
      })

      if (rpcError) throw rpcError

      if (result) {
        data.value = result as PollResult
      }

      if (data.value.success) {
        stopPolling()
      }
    } catch (e: any) {
      console.error('Polling error:', e)
      error.value = e.message
    }
  }

  const startPolling = () => {
    if (isPolling.value) return
    isPolling.value = true
    checkStatus() // Initial check
    timer = setInterval(checkStatus, intervalMs)
  }

  const stopPolling = () => {
    if (timer) {
      clearInterval(timer)
      timer = null
    }
    isPolling.value = false
  }

  onUnmounted(() => {
    stopPolling()
  })

  return {
    data,
    isPolling,
    error,
    startPolling,
    stopPolling,
  }
}

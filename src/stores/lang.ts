import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { messages, type Locale } from '../locales/messages'

export const useLangStore = defineStore('lang', () => {
  // Try to get from localStorage or default to 'vi'
  const currentLang = ref<Locale>((localStorage.getItem('lang') as Locale) || 'vi')

  function setLang(lang: Locale) {
    currentLang.value = lang
    localStorage.setItem('lang', lang)
  }

  const t = computed(() => {
    return (path: string, args?: Record<string, any>) => {
      const keys = path.split('.')
      let value: any = messages[currentLang.value]

      for (const key of keys) {
        if (value && typeof value === 'object' && key in value) {
          value = value[key]
        } else {
          return path
        }
      }

      if (typeof value === 'string' && args) {
        return Object.entries(args).reduce((acc, [k, v]) => acc.replace(`{${k}}`, String(v)), value)
      }

      return value || path
    }
  })

  return {
    currentLang,
    setLang,
    t,
  }
})

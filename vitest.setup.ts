import { beforeEach } from 'vitest'

// Pinia's lang store reads localStorage on init. In some Node versions, Node's
// own experimental global `localStorage` shadows happy-dom's polyfill and
// evaluates to `undefined`, which crashes any store/component that touches it.
// Stub a working in-memory implementation before every test so `useLangStore`
// behaves as it does in a real browser (empty storage -> defaults to 'vi').
beforeEach(() => {
  const store = new Map<string, string>()
  Object.defineProperty(globalThis, 'localStorage', {
    configurable: true,
    value: {
      getItem: (key: string) => store.get(key) ?? null,
      setItem: (key: string, value: string) => store.set(key, value),
      removeItem: (key: string) => store.delete(key),
      clear: () => store.clear(),
    },
  })
})

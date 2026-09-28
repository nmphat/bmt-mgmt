import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import Badge from '@/components/ui/Badge.vue'

describe('Badge', () => {
  it.each([
    ['Default', 'px-3'],
    ['Small', 'px-2'],
  ] as const)('Size %s', (size, cls) => {
    const w = mount(Badge, { props: { size }, slots: { default: 'Label' } })
    expect(w.attributes('data-ds')).toBe('Badge')
    expect(w.attributes('data-ds-size')).toBe(size)
    expect(w.classes()).toContain(cls)
    expect(w.classes()).toContain('whitespace-nowrap')
    expect(w.text()).toBe('Label')
  })

  it.each([
    ['Info', 'bg-status-info', 'text-status-info-strong'],
    ['Warning', 'bg-status-warning', 'text-status-warning-strong'],
    ['Success', 'bg-status-success', 'text-status-success-strong'],
    ['Danger', 'bg-status-danger', 'text-status-danger-strong'],
    ['Neutral', 'bg-status-neutral', 'text-status-neutral-strong'],
    ['Brand', 'bg-surface-brand-muted', 'text-fg-brand-strong'],
  ] as const)('Tone %s', (tone, bg, fg) => {
    const w = mount(Badge, { props: { tone } })
    expect(w.attributes('data-ds-tone')).toBe(tone)
    expect(w.classes()).toContain(bg)
    expect(w.classes()).toContain(fg)
  })
})

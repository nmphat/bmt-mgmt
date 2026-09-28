<script setup lang="ts">
import { computed, useId, useSlots } from 'vue'
import FieldLabel, { type FieldLabelVariant } from './FieldLabel.vue'
import FieldMessage, { type FieldMessageTone } from './FieldMessage.vue'

// Figma set "Form Field" (components/form_field.py): Field Label + control + optional Field Message, gap 4.
// The control goes in the default slot and binds the slot prop `controlProps` (id, aria-describedby,
// aria-invalid). The message is the `message` prop or the `message` slot.
export type FormFieldControl = 'Input' | 'Select'

const props = withDefaults(
  defineProps<{
    label: string
    control?: FormFieldControl
    labelStyle?: FieldLabelVariant
    // id of the control; generated when absent
    controlId?: string
    message?: string
    messageTone?: FieldMessageTone
  }>(),
  {
    control: 'Input',
    labelStyle: 'Default',
    controlId: undefined,
    message: undefined,
    messageTone: 'Help',
  },
)

const slots = useSlots()
const generatedId = useId()
const id = computed(() => props.controlId ?? generatedId)
const messageId = computed(() => `${id.value}-message`)
// Slots are not reactive: evaluate on every render, not in a computed.
const hasMessage = () => !!props.message || !!slots.message
const controlProps = () => ({
  id: id.value,
  'aria-describedby': hasMessage() ? messageId.value : undefined,
  'aria-invalid': hasMessage() && props.messageTone === 'Error' ? 'true' : undefined,
})
</script>

<template>
  <div
    data-ds="Form Field"
    :data-ds-control="control"
    :data-ds-label-style="labelStyle"
    class="flex flex-col gap-1"
  >
    <FieldLabel :for="id" :variant="labelStyle">{{ label }}</FieldLabel>
    <slot :controlProps="controlProps()" />
    <FieldMessage v-if="hasMessage()" :id="messageId" :tone="messageTone">
      <slot name="message">{{ message }}</slot>
    </FieldMessage>
  </div>
</template>

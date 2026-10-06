<script setup>
import Switch from 'dashboard/components-next/switch/Switch.vue';

defineProps({
  label: { type: String, required: true },
});

const modelValue = defineModel({ type: Boolean, default: false });
</script>

<template>
  <div
    class="flex items-center justify-between gap-3 p-3 rounded-xl border border-n-weak bg-n-solid-1 text-sm text-n-slate-12"
  >
    <span>{{ label }}</span>
    <Switch v-model="modelValue" />
  </div>
</template>

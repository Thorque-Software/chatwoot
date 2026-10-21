<script setup>
import Popover from 'dashboard/components-next/popover/Popover.vue';

defineProps({
  title: { type: String, required: true },
  text: { type: String, required: true },
});
</script>

<template>
  <Popover align="start">
    <template #default="{ isOpen }">
      <button
        type="button"
        :aria-label="title"
        :aria-expanded="isOpen"
        class="inline-flex size-7 shrink-0 items-center justify-center rounded-md text-n-slate-10 [@media(hover:hover)]:hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
      >
        <span class="i-lucide-info size-4" aria-hidden="true" />
      </button>
    </template>
    <template #content>
      <section class="max-w-sm p-4 text-body-main text-n-slate-11">
        <h3 class="mb-2 font-medium text-n-slate-12">{{ title }}</h3>
        <p class="mb-0">{{ text }}</p>
      </section>
    </template>
  </Popover>
</template>

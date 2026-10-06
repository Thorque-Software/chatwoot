<script setup>
import { useI18n } from 'vue-i18n';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

defineProps({
  title: { type: String, required: true },
  description: { type: String, default: '' },
  hideToggle: { type: Boolean, default: false },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['save']);

const enabled = defineModel('enabled', { type: Boolean, default: false });

const { t } = useI18n();
</script>

<template>
  <section
    class="flex flex-col w-full outline-1 outline outline-n-container rounded-xl bg-n-solid-2 divide-y divide-n-weak"
  >
    <div class="flex flex-col gap-2 items-start px-5 py-4">
      <div class="flex justify-between items-center w-full gap-3">
        <h3 class="text-heading-2 text-n-slate-12">{{ title }}</h3>
        <Switch v-if="!hideToggle" v-model="enabled" />
      </div>
      <p v-if="description" class="mb-0 text-body-para text-n-slate-11">
        {{ description }}
      </p>
    </div>
    <div class="grid gap-5 px-5 py-4">
      <slot />
      <div class="flex gap-2">
        <NextButton
          blue
          :is-loading="isSaving"
          :label="t('ARROYO.SETTINGS.SAVE')"
          @click="emit('save')"
        />
      </div>
    </div>
  </section>
</template>

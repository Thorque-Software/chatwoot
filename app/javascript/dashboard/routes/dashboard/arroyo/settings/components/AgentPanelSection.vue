<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import SectionCard from './SectionCard.vue';
import SwitchField from './SwitchField.vue';

const props = defineProps({
  config: { type: Object, required: true },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['save']);

const { t } = useI18n();
const form = ref(null);

watch(
  () => props.config,
  config => {
    form.value = { ...config };
  },
  { immediate: true }
);
</script>

<template>
  <SectionCard
    v-model:enabled="form.enabled"
    :title="t('ARROYO.SETTINGS.AGENT_PANEL.TITLE')"
    :description="t('ARROYO.SETTINGS.AGENT_PANEL.DESCRIPTION')"
    :is-saving="isSaving"
    @save="emit('save', { agent_panel: form })"
  >
    <SwitchField
      v-model="form.agents_see_only_own"
      :label="t('ARROYO.SETTINGS.AGENT_PANEL.AGENTS_SEE_ONLY_OWN.LABEL')"
    />
    <SwitchField
      v-model="form.hide_native_reports"
      :label="t('ARROYO.SETTINGS.AGENT_PANEL.HIDE_NATIVE_REPORTS.LABEL')"
    />
  </SectionCard>
</template>

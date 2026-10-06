<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SectionCard from './SectionCard.vue';

const props = defineProps({
  timezone: { type: String, required: true },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['save']);

const { t } = useI18n();
const timezoneInput = ref('');

watch(
  () => props.timezone,
  value => {
    timezoneInput.value = value;
  },
  { immediate: true }
);
</script>

<template>
  <SectionCard
    :title="t('ARROYO.SETTINGS.GENERAL.TITLE')"
    :description="t('ARROYO.SETTINGS.GENERAL.DESCRIPTION')"
    :is-saving="isSaving"
    hide-toggle
    @save="emit('save', { timezone: timezoneInput.trim() })"
  >
    <WithLabel
      name="timezone"
      :label="t('ARROYO.SETTINGS.GENERAL.TIMEZONE.LABEL')"
      :help-message="t('ARROYO.SETTINGS.GENERAL.TIMEZONE.HELP')"
    >
      <Input v-model="timezoneInput" class="w-full" />
    </WithLabel>
  </SectionCard>
</template>

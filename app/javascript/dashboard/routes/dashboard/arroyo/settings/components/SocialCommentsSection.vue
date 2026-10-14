<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import SectionCard from './SectionCard.vue';

const props = defineProps({
  config: { type: Object, required: true },
  isSaving: { type: Boolean, default: false },
});
const emit = defineEmits(['save']);
const { t } = useI18n();
const form = ref({ enabled: false });
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
    :title="t('ARROYO.SOCIAL_COMMENTS.FEATURE_TITLE')"
    :description="t('ARROYO.SOCIAL_COMMENTS.FEATURE_DESCRIPTION')"
    :is-saving="isSaving"
    @save="emit('save', { social_comments: form })"
  />
</template>

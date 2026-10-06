<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import SectionCard from './SectionCard.vue';
import { MAX_FOOTER_LENGTH } from '../constants';

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
    :title="t('ARROYO.SETTINGS.EMAIL_MARKETING.TITLE')"
    :description="t('ARROYO.SETTINGS.EMAIL_MARKETING.DESCRIPTION')"
    :is-saving="isSaving"
    @save="emit('save', { email_marketing: form })"
  >
    <div class="grid gap-5 sm:grid-cols-2">
      <WithLabel
        name="max_per_hour"
        :label="t('ARROYO.SETTINGS.EMAIL_MARKETING.MAX_PER_HOUR.LABEL')"
      >
        <Input
          v-model.number="form.max_per_hour"
          type="number"
          min="1"
          class="w-full"
        />
      </WithLabel>
      <WithLabel
        name="max_per_day"
        :label="t('ARROYO.SETTINGS.EMAIL_MARKETING.MAX_PER_DAY.LABEL')"
      >
        <Input
          v-model.number="form.max_per_day"
          type="number"
          min="1"
          class="w-full"
        />
      </WithLabel>
    </div>
    <WithLabel
      name="footer_html"
      :label="t('ARROYO.SETTINGS.EMAIL_MARKETING.FOOTER_HTML.LABEL')"
      :help-message="t('ARROYO.SETTINGS.EMAIL_MARKETING.FOOTER_HTML.HELP')"
    >
      <TextArea
        v-model="form.footer_html"
        :max-length="MAX_FOOTER_LENGTH"
        class="w-full"
        auto-height
      />
    </WithLabel>
  </SectionCard>
</template>

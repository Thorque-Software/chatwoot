<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SectionCard from './SectionCard.vue';

const props = defineProps({
  config: { type: Object, required: true },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['save']);

const { t } = useI18n();
const form = ref(null);
const token = ref('');

watch(
  () => props.config,
  config => {
    form.value = { enabled: config.enabled };
    token.value = '';
  },
  { immediate: true }
);

const save = () => {
  emit('save', {
    ads_attribution: { ...form.value, meta_ads_token: token.value },
  });
};
</script>

<template>
  <SectionCard
    v-model:enabled="form.enabled"
    :title="t('ARROYO.SETTINGS.ADS_ATTRIBUTION.TITLE')"
    :description="t('ARROYO.SETTINGS.ADS_ATTRIBUTION.DESCRIPTION')"
    :is-saving="isSaving"
    @save="save"
  >
    <WithLabel
      name="meta_ads_token"
      :label="t('ARROYO.SETTINGS.ADS_ATTRIBUTION.TOKEN.LABEL')"
      :help-message="
        config.token_set
          ? t('ARROYO.SETTINGS.ADS_ATTRIBUTION.TOKEN.SET')
          : t('ARROYO.SETTINGS.ADS_ATTRIBUTION.TOKEN.HELP')
      "
    >
      <Input
        v-model="token"
        type="password"
        autocomplete="off"
        :placeholder="t('ARROYO.SETTINGS.ADS_ATTRIBUTION.TOKEN.PLACEHOLDER')"
        class="w-full"
      />
    </WithLabel>
  </SectionCard>
</template>

<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  conversationAttributes: { type: Object, default: () => ({}) },
});

const { t } = useI18n();

const isAd = computed(() => props.conversationAttributes.ad_source);

const fields = computed(() => {
  const attrs = props.conversationAttributes;
  return [
    {
      key: 'CAMPAIGN',
      label: t('ARROYO.AD_SOURCE.CAMPAIGN'),
      value: attrs.ad_campaign_name,
    },
    {
      key: 'ADSET',
      label: t('ARROYO.AD_SOURCE.ADSET'),
      value: attrs.ad_adset_name,
    },
    { key: 'AD', label: t('ARROYO.AD_SOURCE.AD'), value: attrs.ad_name },
    { key: 'AD_ID', label: t('ARROYO.AD_SOURCE.AD_ID'), value: attrs.ad_id },
    {
      key: 'HEADLINE',
      label: t('ARROYO.AD_SOURCE.HEADLINE'),
      value: attrs.ad_headline,
    },
    { key: 'BODY', label: t('ARROYO.AD_SOURCE.BODY'), value: attrs.ad_body },
  ].filter(field => field.value);
});
</script>

<template>
  <div>
    <div v-if="isAd" class="flex flex-col gap-2 py-3">
      <div class="flex items-center gap-2">
        <span class="i-lucide-megaphone size-4 text-n-slate-11" />
        <h4 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('ARROYO.AD_SOURCE.TITLE') }}
        </h4>
      </div>
      <div
        v-for="field in fields"
        :key="field.key"
        class="flex flex-col gap-0.5"
      >
        <span class="text-xs text-n-slate-11">{{ field.label }}</span>
        <span class="text-sm break-words text-n-slate-12">
          {{ field.value }}
        </span>
      </div>
      <a
        v-if="conversationAttributes.ad_source_url"
        :href="conversationAttributes.ad_source_url"
        target="_blank"
        rel="noopener noreferrer"
        class="text-sm break-all text-n-brand hover:underline"
      >
        {{ t('ARROYO.AD_SOURCE.OPEN_AD') }}
      </a>
    </div>
  </div>
</template>

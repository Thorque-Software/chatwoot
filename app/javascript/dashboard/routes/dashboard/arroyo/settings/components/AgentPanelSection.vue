<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import MultiSelect from 'dashboard/components-next/filter/inputs/MultiSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SectionCard from './SectionCard.vue';
import SwitchField from './SwitchField.vue';

const props = defineProps({
  config: { type: Object, required: true },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['save']);

const { t } = useI18n();
const agents = useMapGetter('agents/getAgents');
const form = ref(null);
const agentOptions = computed(() =>
  agents.value.map(({ id, name }) => ({ id, name }))
);
const sellers = computed({
  get: () =>
    agentOptions.value.filter(agent =>
      form.value.seller_ids.includes(agent.id)
    ),
  set: value => {
    form.value.seller_ids = value.map(agent => agent.id);
  },
});

watch(
  () => props.config,
  config => {
    form.value = {
      funnel_enabled: false,
      balanced_assignment_enabled: false,
      seller_ids: [],
      response_hours: 4,
      lookback_days: 7,
      ...config,
    };
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
    <SwitchField
      v-model="form.funnel_enabled"
      :label="t('ARROYO.SETTINGS.AGENT_PANEL.FUNNEL_ENABLED.LABEL')"
    />
    <SwitchField
      v-model="form.balanced_assignment_enabled"
      :label="
        t('ARROYO.SETTINGS.AGENT_PANEL.BALANCED_ASSIGNMENT_ENABLED.LABEL')
      "
    />
    <div class="flex flex-col gap-2 text-body-main text-n-slate-11">
      <span>{{ t('ARROYO.SETTINGS.AGENT_PANEL.SELLER_IDS.LABEL') }}</span>
      <MultiSelect v-model="sellers" :options="agentOptions" />
    </div>
    <div class="grid gap-4 md:grid-cols-2">
      <Input
        v-model="form.response_hours"
        type="number"
        min="1"
        :label="t('ARROYO.SETTINGS.AGENT_PANEL.RESPONSE_HOURS.LABEL')"
      />
      <Input
        v-model="form.lookback_days"
        type="number"
        min="1"
        :label="t('ARROYO.SETTINGS.AGENT_PANEL.LOOKBACK_DAYS.LABEL')"
      />
    </div>
    <p class="mb-0 text-label-small text-n-slate-11">
      {{ t('ARROYO.SETTINGS.AGENT_PANEL.COMMERCIAL_HELP') }}
    </p>
  </SectionCard>
</template>

<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import MultiSelect from 'dashboard/components-next/filter/inputs/MultiSelect.vue';
import SectionCard from './SectionCard.vue';
import SwitchField from './SwitchField.vue';
import {
  POST_SALE_STAGES,
  LIQUID_VARIABLE_EXAMPLE,
  MAX_MESSAGE_LENGTH,
} from '../constants';

const props = defineProps({
  config: { type: Object, required: true },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['save']);

const { t } = useI18n();
const agents = useMapGetter('agents/getAgents');
const form = ref(null);

const agentOptions = computed(() =>
  agents.value.map(agent => ({ id: agent.id, name: agent.name }))
);

watch(
  [() => props.config, agentOptions],
  ([config]) => {
    const stages = JSON.parse(JSON.stringify(config.stages));
    POST_SALE_STAGES.forEach(stage => {
      stages[stage].template = stages[stage].template || '';
    });
    form.value = {
      ...JSON.parse(JSON.stringify(config)),
      stages,
      alert_user_ids: agentOptions.value.filter(option =>
        config.alert_user_ids.includes(option.id)
      ),
    };
  },
  { immediate: true }
);

const save = () => {
  const stages = {};
  POST_SALE_STAGES.forEach(stage => {
    const { template, ...rest } = form.value.stages[stage];
    stages[stage] = { ...rest, template: template.trim() || null };
  });
  emit('save', {
    post_sale: {
      ...form.value,
      stages,
      alert_user_ids: form.value.alert_user_ids.map(option => option.id),
    },
  });
};
</script>

<template>
  <SectionCard
    v-model:enabled="form.enabled"
    :title="t('ARROYO.SETTINGS.POST_SALE.TITLE')"
    :description="t('ARROYO.SETTINGS.POST_SALE.DESCRIPTION')"
    :is-saving="isSaving"
    @save="save"
  >
    <WithLabel
      name="trigger_label"
      :label="t('ARROYO.SETTINGS.POST_SALE.TRIGGER_LABEL.LABEL')"
      :help-message="t('ARROYO.SETTINGS.POST_SALE.TRIGGER_LABEL.HELP')"
    >
      <Input v-model="form.trigger_label" class="w-full" />
    </WithLabel>
    <WithLabel
      name="send_hour_local"
      :label="t('ARROYO.SETTINGS.POST_SALE.SEND_HOUR_LOCAL.LABEL')"
      :help-message="t('ARROYO.SETTINGS.POST_SALE.SEND_HOUR_LOCAL.HELP')"
    >
      <Input
        v-model.number="form.send_hour_local"
        type="number"
        min="0"
        max="23"
        class="w-full"
      />
    </WithLabel>
    <SwitchField
      v-model="form.skip_sundays"
      :label="t('ARROYO.SETTINGS.POST_SALE.SKIP_SUNDAYS.LABEL')"
    />
    <div
      v-for="stage in POST_SALE_STAGES"
      :key="stage"
      class="grid gap-4 p-4 rounded-xl border border-n-weak"
    >
      <h4 class="text-heading-3 text-n-slate-12">
        {{ t('ARROYO.SETTINGS.POST_SALE.STAGE.TITLE', { stage }) }}
      </h4>
      <WithLabel
        :name="`${stage}_days`"
        :label="t('ARROYO.SETTINGS.POST_SALE.STAGE.DAYS.LABEL')"
      >
        <Input
          v-model.number="form.stages[stage].days"
          type="number"
          min="1"
          max="365"
          class="w-full"
        />
      </WithLabel>
      <WithLabel
        :name="`${stage}_free_text`"
        :label="t('ARROYO.SETTINGS.POST_SALE.STAGE.FREE_TEXT.LABEL')"
        :help-message="
          t('ARROYO.SETTINGS.POST_SALE.STAGE.FREE_TEXT.HELP', {
            variable: LIQUID_VARIABLE_EXAMPLE,
          })
        "
      >
        <TextArea
          v-model="form.stages[stage].free_text"
          :max-length="MAX_MESSAGE_LENGTH"
          class="w-full"
          auto-height
        />
      </WithLabel>
      <WithLabel
        :name="`${stage}_template`"
        :label="t('ARROYO.SETTINGS.POST_SALE.STAGE.TEMPLATE.LABEL')"
        :help-message="t('ARROYO.SETTINGS.POST_SALE.STAGE.TEMPLATE.HELP')"
      >
        <Input v-model="form.stages[stage].template" class="w-full" />
      </WithLabel>
    </div>
    <WithLabel
      name="delivery_timeout_hours"
      :label="t('ARROYO.SETTINGS.POST_SALE.DELIVERY_TIMEOUT_HOURS.LABEL')"
      :help-message="t('ARROYO.SETTINGS.POST_SALE.DELIVERY_TIMEOUT_HOURS.HELP')"
    >
      <Input
        v-model.number="form.delivery_timeout_hours"
        type="number"
        min="1"
        max="72"
        class="w-full"
      />
    </WithLabel>
    <WithLabel
      name="alert_user_ids"
      :label="t('ARROYO.SETTINGS.POST_SALE.ALERT_USERS.LABEL')"
      :help-message="t('ARROYO.SETTINGS.POST_SALE.ALERT_USERS.HELP')"
    >
      <MultiSelect v-model="form.alert_user_ids" :options="agentOptions" />
    </WithLabel>
  </SectionCard>
</template>

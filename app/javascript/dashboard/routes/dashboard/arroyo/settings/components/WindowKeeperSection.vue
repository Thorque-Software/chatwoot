<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import TagInput from 'dashboard/components-next/taginput/TagInput.vue';
import MultiSelect from 'dashboard/components-next/filter/inputs/MultiSelect.vue';
import SectionCard from './SectionCard.vue';
import SwitchField from './SwitchField.vue';
import {
  NUDGE_STATUSES,
  LIQUID_VARIABLE_EXAMPLE,
  MAX_MESSAGE_LENGTH,
} from '../constants';

const props = defineProps({
  config: { type: Object, required: true },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['save']);

const { t } = useI18n();
const form = ref(null);
// TagInput solo lee su valor al montarse: se remonta cuando llega config nueva
const formKey = ref(0);

const statusOptions = computed(() => {
  const statusLabels = {
    open: t('ARROYO.SETTINGS.STATUSES.OPEN'),
    snoozed: t('ARROYO.SETTINGS.STATUSES.SNOOZED'),
  };
  return NUDGE_STATUSES.map(status => ({
    id: status,
    name: statusLabels[status],
  }));
});

watch(
  () => props.config,
  config => {
    form.value = {
      ...JSON.parse(JSON.stringify(config)),
      only_statuses: statusOptions.value.filter(option =>
        config.only_statuses.includes(option.id)
      ),
      reengagement_template: config.reengagement_template || '',
    };
    formKey.value += 1;
  },
  { immediate: true }
);

const save = () => {
  emit('save', {
    window_keeper: {
      ...form.value,
      only_statuses: form.value.only_statuses.map(option => option.id),
      reengagement_template: form.value.reengagement_template.trim() || null,
    },
  });
};
</script>

<template>
  <SectionCard
    v-model:enabled="form.enabled"
    :title="t('ARROYO.SETTINGS.WINDOW_KEEPER.TITLE')"
    :description="t('ARROYO.SETTINGS.WINDOW_KEEPER.DESCRIPTION')"
    :is-saving="isSaving"
    @save="save"
  >
    <WithLabel
      name="nudge_after_hours"
      :label="t('ARROYO.SETTINGS.WINDOW_KEEPER.NUDGE_AFTER_HOURS.LABEL')"
      :help-message="t('ARROYO.SETTINGS.WINDOW_KEEPER.NUDGE_AFTER_HOURS.HELP')"
    >
      <Input
        v-model.number="form.nudge_after_hours"
        type="number"
        min="1"
        max="23.5"
        class="w-full"
      />
    </WithLabel>
    <WithLabel
      name="only_statuses"
      :label="t('ARROYO.SETTINGS.WINDOW_KEEPER.ONLY_STATUSES.LABEL')"
    >
      <MultiSelect v-model="form.only_statuses" :options="statusOptions" />
    </WithLabel>
    <SwitchField
      v-model="form.only_assigned"
      :label="t('ARROYO.SETTINGS.WINDOW_KEEPER.ONLY_ASSIGNED.LABEL')"
    />
    <WithLabel
      name="nudge_text"
      :label="t('ARROYO.SETTINGS.WINDOW_KEEPER.NUDGE_TEXT.LABEL')"
      :help-message="
        t('ARROYO.SETTINGS.WINDOW_KEEPER.NUDGE_TEXT.HELP', {
          variable: LIQUID_VARIABLE_EXAMPLE,
        })
      "
    >
      <TextArea
        v-model="form.nudge_text"
        :max-length="MAX_MESSAGE_LENGTH"
        class="w-full"
        auto-height
      />
    </WithLabel>
    <WithLabel
      name="nudge_buttons"
      :label="t('ARROYO.SETTINGS.WINDOW_KEEPER.NUDGE_BUTTONS.LABEL')"
      :help-message="t('ARROYO.SETTINGS.WINDOW_KEEPER.NUDGE_BUTTONS.HELP')"
    >
      <TagInput
        :key="`buttons-${formKey}`"
        v-model="form.nudge_buttons"
        :placeholder="
          t('ARROYO.SETTINGS.WINDOW_KEEPER.NUDGE_BUTTONS.PLACEHOLDER')
        "
        :auto-open-dropdown="false"
        class="w-full"
      />
    </WithLabel>
    <WithLabel
      name="skip_labels"
      :label="t('ARROYO.SETTINGS.WINDOW_KEEPER.SKIP_LABELS.LABEL')"
      :help-message="t('ARROYO.SETTINGS.WINDOW_KEEPER.SKIP_LABELS.HELP')"
    >
      <TagInput
        :key="`labels-${formKey}`"
        v-model="form.skip_labels"
        :placeholder="
          t('ARROYO.SETTINGS.WINDOW_KEEPER.SKIP_LABELS.PLACEHOLDER')
        "
        :auto-open-dropdown="false"
        class="w-full"
      />
    </WithLabel>
    <WithLabel
      name="reengagement_template"
      :label="t('ARROYO.SETTINGS.WINDOW_KEEPER.REENGAGEMENT_TEMPLATE.LABEL')"
      :help-message="
        t('ARROYO.SETTINGS.WINDOW_KEEPER.REENGAGEMENT_TEMPLATE.HELP')
      "
    >
      <Input v-model="form.reengagement_template" class="w-full" />
    </WithLabel>
  </SectionCard>
</template>

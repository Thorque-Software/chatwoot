<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import MultiSelect from 'dashboard/components-next/filter/inputs/MultiSelect.vue';
import { DATE_PRESETS, GROUP_BY_OPTIONS } from '../constants';

const props = defineProps({
  filters: { type: Object, required: true },
  agentOptions: { type: Array, default: () => [] },
  inboxOptions: { type: Array, default: () => [] },
  showAgentFilter: { type: Boolean, default: true },
  showDateFilters: { type: Boolean, default: true },
  showGroupBy: { type: Boolean, default: true },
});

const emit = defineEmits(['change']);

const { t } = useI18n();

const presetLabels = computed(() => ({
  today: t('ARROYO.PANEL.FILTERS.PRESETS.TODAY'),
  yesterday: t('ARROYO.PANEL.FILTERS.PRESETS.YESTERDAY'),
  last_7_days: t('ARROYO.PANEL.FILTERS.PRESETS.LAST_7_DAYS'),
  this_month: t('ARROYO.PANEL.FILTERS.PRESETS.THIS_MONTH'),
  last_month: t('ARROYO.PANEL.FILTERS.PRESETS.LAST_MONTH'),
  custom: t('ARROYO.PANEL.FILTERS.PRESETS.CUSTOM'),
}));

const groupByLabels = computed(() => ({
  day: t('ARROYO.PANEL.FILTERS.GROUP_BY.DAY'),
  week: t('ARROYO.PANEL.FILTERS.GROUP_BY.WEEK'),
}));

const presetOptions = computed(() =>
  DATE_PRESETS.map(preset => ({
    value: preset,
    label: presetLabels.value[preset],
  }))
);

const groupByOptions = computed(() =>
  GROUP_BY_OPTIONS.map(option => ({
    value: option,
    label: groupByLabels.value[option],
  }))
);

const selectedOptions = (options, ids) =>
  options.filter(option => ids.includes(option.id));

const selectedAgents = computed({
  get: () => selectedOptions(props.agentOptions, props.filters.userIds),
  set: value => emit('change', { userIds: value.map(option => option.id) }),
});

const selectedInboxes = computed({
  get: () => selectedOptions(props.inboxOptions, props.filters.inboxIds),
  set: value => emit('change', { inboxIds: value.map(option => option.id) }),
});

const onPresetChange = preset => {
  // Al pasar a personalizado se arranca del rango que se estaba viendo
  emit('change', {
    preset,
    since: props.filters.since,
    until: props.filters.until,
  });
};
</script>

<template>
  <div class="flex flex-wrap items-end gap-3">
    <template v-if="showDateFilters">
      <label class="flex flex-col gap-1 text-label-small text-n-slate-11">
        {{ t('ARROYO.PANEL.FILTERS.PERIOD') }}
        <Select
          :model-value="filters.preset"
          :options="presetOptions"
          @update:model-value="onPresetChange"
        />
      </label>
      <template v-if="filters.preset === 'custom'">
        <label class="flex flex-col gap-1 text-label-small text-n-slate-11">
          {{ t('ARROYO.PANEL.FILTERS.SINCE') }}
          <Input
            type="date"
            :model-value="filters.since"
            :max="filters.until"
            @update:model-value="since => emit('change', { since })"
          />
        </label>
        <label class="flex flex-col gap-1 text-label-small text-n-slate-11">
          {{ t('ARROYO.PANEL.FILTERS.UNTIL') }}
          <Input
            type="date"
            :model-value="filters.until"
            :min="filters.since"
            @update:model-value="until => emit('change', { until })"
          />
        </label>
      </template>
      <label
        v-if="showGroupBy"
        class="flex flex-col gap-1 text-label-small text-n-slate-11"
      >
        {{ t('ARROYO.PANEL.FILTERS.GROUP_BY.LABEL') }}
        <Select
          :model-value="filters.groupBy"
          :options="groupByOptions"
          @update:model-value="groupBy => emit('change', { groupBy })"
        />
      </label>
    </template>
    <div
      v-if="showAgentFilter"
      class="flex flex-col gap-1 text-label-small text-n-slate-11"
    >
      {{ t('ARROYO.PANEL.FILTERS.AGENTS') }}
      <MultiSelect v-model="selectedAgents" :options="agentOptions" />
    </div>
    <div class="flex flex-col gap-1 text-label-small text-n-slate-11">
      {{ t('ARROYO.PANEL.FILTERS.INBOXES') }}
      <MultiSelect v-model="selectedInboxes" :options="inboxOptions" />
    </div>
  </div>
</template>

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
  showAllDates: { type: Boolean, default: false },
  showDateFilters: { type: Boolean, default: true },
  showGroupBy: { type: Boolean, default: true },
});

const emit = defineEmits(['change', 'clear']);

const { t } = useI18n();
const periodLabel = computed(() =>
  props.showAllDates
    ? t('ARROYO.PANEL.FILTERS.PURCHASE_PERIOD')
    : t('ARROYO.PANEL.FILTERS.PERIOD')
);

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
  [...(props.showAllDates ? ['all'] : []), ...DATE_PRESETS].map(preset => ({
    value: preset,
    label:
      preset === 'all'
        ? t('ARROYO.PANEL.FILTERS.ALL_PURCHASES')
        : presetLabels.value[preset],
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

const purchaseDateScope = computed(() =>
  props.filters.preset === 'all'
    ? ''
    : t('ARROYO.PANEL.FILTERS.SCOPE.DATE_RANGE', {
        since: props.filters.since,
        until: props.filters.until,
      })
);
const namesFor = (options, ids) =>
  ids
    .map(
      id =>
        options.find(option => option.id === id)?.name ||
        t('ARROYO.PANEL.FILTERS.SCOPE.OPTION_ID', { id })
    )
    .join(', ');
const hasPurchaseFilters = computed(
  () =>
    props.filters.preset !== 'all' ||
    props.filters.userIds.length > 0 ||
    props.filters.inboxIds.length > 0
);
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
  <section class="flex flex-col gap-3">
    <div class="flex flex-wrap items-start gap-4">
      <template v-if="showDateFilters">
        <label class="flex flex-col gap-1 text-label-small text-n-slate-11">
          {{ periodLabel }}
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
        {{
          showAllDates
            ? t('ARROYO.PANEL.FILTERS.PURCHASE_SELLER')
            : t('ARROYO.PANEL.FILTERS.AGENTS')
        }}
        <MultiSelect v-model="selectedAgents" :options="agentOptions" />
      </div>
      <div class="flex flex-col gap-1 text-label-small text-n-slate-11">
        {{
          showAllDates
            ? t('ARROYO.PANEL.FILTERS.PURCHASE_INBOX')
            : t('ARROYO.PANEL.FILTERS.INBOXES')
        }}
        <MultiSelect v-model="selectedInboxes" :options="inboxOptions" />
      </div>
    </div>
    <div v-if="showAllDates" class="flex flex-wrap items-center gap-2 text-sm">
      <div
        v-if="hasPurchaseFilters"
        class="flex flex-wrap gap-2"
        data-testid="purchase-filter-context"
        :aria-label="t('ARROYO.PANEL.FILTERS.SCOPE.TITLE')"
      >
        <span
          v-if="filters.preset !== 'all'"
          class="rounded bg-n-alpha-2 px-2 py-1 text-n-slate-12"
        >
          {{ purchaseDateScope }}
        </span>
        <span
          v-if="filters.userIds.length"
          class="rounded bg-n-alpha-2 px-2 py-1 text-n-slate-12"
        >
          {{ namesFor(agentOptions, filters.userIds) }}
        </span>
        <span
          v-if="filters.inboxIds.length"
          class="rounded bg-n-alpha-2 px-2 py-1 text-n-slate-12"
        >
          {{ namesFor(inboxOptions, filters.inboxIds) }}
        </span>
      </div>
      <button
        type="button"
        class="rounded text-sm text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
        data-testid="clear-purchase-filters"
        @click="emit('clear')"
      >
        {{ t('ARROYO.PANEL.FILTERS.SCOPE.CLEAR') }}
      </button>
    </div>
  </section>
</template>

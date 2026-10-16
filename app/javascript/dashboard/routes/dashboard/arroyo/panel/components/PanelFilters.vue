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
    ? t('ARROYO.PANEL.FILTERS.SCOPE.ALL_DATES')
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
const sellerScope = computed(() => {
  if (props.filters.userIds.length)
    return namesFor(props.agentOptions, props.filters.userIds);
  return props.showAgentFilter
    ? t('ARROYO.PANEL.FILTERS.SCOPE.ALL_SELLERS')
    : t('ARROYO.PANEL.FILTERS.SCOPE.OWN_ACCESS');
});
const inboxScope = computed(() =>
  props.filters.inboxIds.length
    ? namesFor(props.inboxOptions, props.filters.inboxIds)
    : t('ARROYO.PANEL.FILTERS.SCOPE.ALL_INBOXES')
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
    <div v-if="showAllDates" class="flex flex-col gap-1">
      <h2 class="mb-0 text-heading-3 text-n-slate-12">
        {{ t('ARROYO.PANEL.FILTERS.PURCHASE_TITLE') }}
      </h2>
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t('ARROYO.PANEL.FILTERS.PURCHASE_HELP') }}
      </p>
    </div>
    <div class="flex flex-wrap items-start gap-4">
      <template v-if="showDateFilters">
        <label class="flex flex-col gap-1 text-label-small text-n-slate-11">
          {{ periodLabel }}
          <Select
            :model-value="filters.preset"
            :options="presetOptions"
            @update:model-value="onPresetChange"
          />
          <span
            v-if="showAllDates"
            class="max-w-64 text-xs font-normal text-n-slate-11"
          >
            {{ t('ARROYO.PANEL.FILTERS.DATE_HELP') }}
          </span>
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
        <span
          v-if="showAllDates"
          class="max-w-64 text-xs font-normal text-n-slate-11"
        >
          {{ t('ARROYO.PANEL.FILTERS.SELLER_HELP') }}
        </span>
      </div>
      <div class="flex flex-col gap-1 text-label-small text-n-slate-11">
        {{
          showAllDates
            ? t('ARROYO.PANEL.FILTERS.PURCHASE_INBOX')
            : t('ARROYO.PANEL.FILTERS.INBOXES')
        }}
        <MultiSelect v-model="selectedInboxes" :options="inboxOptions" />
        <span
          v-if="showAllDates"
          class="max-w-64 text-xs font-normal text-n-slate-11"
        >
          {{ t('ARROYO.PANEL.FILTERS.INBOX_HELP') }}
        </span>
      </div>
    </div>
    <div
      v-if="showAllDates"
      class="flex flex-col gap-3 rounded-lg bg-n-solid-2 p-4"
      data-testid="purchase-filter-context"
    >
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h3 class="mb-0 text-sm font-semibold text-n-slate-12">
          {{ t('ARROYO.PANEL.FILTERS.SCOPE.TITLE') }}
        </h3>
        <button
          type="button"
          class="rounded text-sm font-medium text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          data-testid="clear-purchase-filters"
          @click="emit('clear')"
        >
          {{ t('ARROYO.PANEL.FILTERS.SCOPE.CLEAR') }}
        </button>
      </div>
      <dl class="m-0 grid gap-3 text-sm md:grid-cols-3">
        <div>
          <dt class="text-n-slate-11">
            {{ t('ARROYO.PANEL.FILTERS.PURCHASE_PERIOD') }}
          </dt>
          <dd class="m-0 text-n-slate-12">{{ purchaseDateScope }}</dd>
        </div>
        <div>
          <dt class="text-n-slate-11">
            {{ t('ARROYO.PANEL.FILTERS.PURCHASE_SELLER') }}
          </dt>
          <dd class="m-0 text-n-slate-12">{{ sellerScope }}</dd>
        </div>
        <div>
          <dt class="text-n-slate-11">
            {{ t('ARROYO.PANEL.FILTERS.PURCHASE_INBOX') }}
          </dt>
          <dd class="m-0 text-n-slate-12">{{ inboxScope }}</dd>
        </div>
      </dl>
      <p class="mb-0 text-xs text-n-slate-11">
        {{ t('ARROYO.PANEL.FILTERS.SCOPE.HELP') }}
      </p>
    </div>
  </section>
</template>

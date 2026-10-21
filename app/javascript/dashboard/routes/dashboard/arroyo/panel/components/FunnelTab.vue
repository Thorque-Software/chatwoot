<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import CommercialAPI from '../../api/commercial';
import OpportunitiesDrawer from './OpportunitiesDrawer.vue';
import CohortFlow from './CohortFlow.vue';
import FunnelHelp from './FunnelHelp.vue';
import { periodRange } from '../helpers';
import { CHART_COLOR } from '../constants';
import { useCommercialLabels } from '../useCommercialLabels';
import {
  COHORT_STATES,
  SUMMARY_METRICS,
  ACTIVITY_METRICS,
  RELATED_METRICS,
  sellerPresentation,
} from '../commercialConstants';

const props = defineProps({
  params: { type: Object, required: true },
  showPostSale: { type: Boolean, default: false },
  showExport: { type: Boolean, default: true },
  sellerIds: { type: Array, default: () => [] },
});
const emit = defineEmits(['groupChanged']);
const { t, locale } = useI18n();
const route = useRoute();
const report = ref(null);
const loading = ref(false);
const stale = ref(true);
const ready = computed(
  () => Boolean(report.value) && !stale.value && !loading.value
);
const error = ref('');
const exportError = ref('');
const exporting = ref(false);
const activityMetric = ref('attended');
const selection = ref(null);
const showDailyTable = ref(false);
let reportRequest = 0;
const metricLabels = useCommercialLabels();
const label = metric => metricLabels.value[metric];
const activityOptions = computed(() =>
  ACTIVITY_METRICS.map(value => ({ value, label: label(value) }))
);
const activityDescriptions = computed(() => ({
  received: t('ARROYO.PANEL.FUNNEL.ACTIVITY_METRIC_HELP.RECEIVED'),
  assigned: t('ARROYO.PANEL.FUNNEL.ACTIVITY_METRIC_HELP.ASSIGNED'),
  attended: t('ARROYO.PANEL.FUNNEL.ACTIVITY_METRIC_HELP.ATTENDED'),
  won: t('ARROYO.PANEL.FUNNEL.ACTIVITY_METRIC_HELP.WON'),
}));
const activityHelp = computed(
  () =>
    `${activityDescriptions.value[activityMetric.value]} ${t('ARROYO.PANEL.FUNNEL.ACTIVITY_HELP')}`
);
const periods = computed(() => report.value.series.map(point => point.date));
const sellerIds = computed(() =>
  props.sellerIds.length
    ? props.sellerIds
    : report.value.agents.map(agent => agent.id)
);
const groupOptions = computed(() => [
  { value: 'day', label: t('ARROYO.PANEL.FILTERS.GROUP_BY.DAY') },
  { value: 'week', label: t('ARROYO.PANEL.FILTERS.GROUP_BY.WEEK') },
]);
const metricIcons = {
  received: 'i-lucide-messages-square',
  pending: 'i-lucide-clock-3',
  bot: 'i-lucide-bot',
  won: 'i-lucide-badge-check',
  repeat_sales: 'i-lucide-repeat-2',
  post_sale_replies: 'i-lucide-message-circle',
  post_sale_issues: 'i-lucide-triangle-alert',
};
const metricColor = metric =>
  ({
    won: 'text-n-teal-11',
    repeat_sales: 'text-n-teal-11',
    pending: 'text-n-amber-11',
    post_sale_issues: 'text-n-amber-11',
    bot: 'text-n-violet-11',
  })[metric] || 'text-n-blue-11';
const asOf = computed(() =>
  new Intl.DateTimeFormat(locale.value, {
    timeZone: report.value.timezone,
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(report.value.as_of))
);
const chartCollection = computed(() => ({
  labels: periods.value,
  datasets: report.value.agents.length
    ? report.value.agents.map(agent => ({
        label: agent.name,
        sellerId: agent.id,
        backgroundColor: sellerPresentation(agent.id, sellerIds.value).color,
        borderRadius: 3,
        maxBarThickness: 18,
        data: periods.value.map(
          period => agent.periods[period]?.[activityMetric.value] ?? 0
        ),
      }))
    : [
        {
          label: t('ARROYO.PANEL.FUNNEL.TOTAL_SERIES'),
          sellerId: null,
          backgroundColor: CHART_COLOR,
          data: report.value.series.map(point => point[activityMetric.value]),
        },
      ],
}));
const periodLabel = period =>
  props.params.group_by === 'week'
    ? t('ARROYO.PANEL.WEEK_OF', { date: period })
    : new Intl.DateTimeFormat(locale.value, {
        month: 'short',
        day: 'numeric',
      }).format(new Date(`${period}T12:00:00Z`));

const fetchReport = async () => {
  reportRequest += 1;
  const request = reportRequest;
  loading.value = true;
  error.value = '';
  try {
    const { data } = await CommercialAPI.getReport(props.params);
    if (request === reportRequest) {
      report.value = data;
      stale.value = false;
    }
  } catch {
    if (request === reportRequest) {
      error.value = t('ARROYO.PANEL.FUNNEL.LOAD_ERROR');
    }
  } finally {
    if (request === reportRequest) loading.value = false;
  }
};

const openDetails = (metric, scope, userId, period) => {
  if (!ready.value) return;
  const range = period
    ? periodRange(period, props.params.group_by, props.params)
    : {};
  selection.value = {
    title: label(metric),
    params: {
      ...props.params,
      ...range,
      user_ids: userId ? [userId] : props.params.user_ids,
      metric,
      scope: scope || 'cohort',
    },
  };
};
const exportCsv = async () => {
  if (!ready.value) return;
  exporting.value = true;
  exportError.value = '';
  try {
    const { data } = await CommercialAPI.exportReport({
      ...props.params,
      metric: 'received',
      scope: 'cohort',
    });
    downloadCsvFile(
      `consultas_${props.params.since}_${props.params.until}.csv`,
      data
    );
  } catch {
    exportError.value = t('ARROYO.PANEL.FUNNEL.EXPORT_ERROR');
  } finally {
    exporting.value = false;
  }
};
const onActivityClick = (_event, elements) => {
  if (elements.length) {
    const element = elements[0];
    openDetails(
      activityMetric.value,
      'activity',
      chartCollection.value.datasets[element.datasetIndex ?? 0]?.sellerId,
      periods.value[element.index]
    );
  }
};
watch(
  () => props.params,
  () => {
    selection.value = null;
    stale.value = true;
    fetchReport();
  },
  { immediate: true, deep: true }
);
defineExpose({ exportCsv, exporting, loading, ready });
</script>

<template>
  <div class="flex min-w-0 flex-col gap-5" :aria-busy="loading">
    <div
      v-if="error"
      role="alert"
      class="flex flex-wrap items-center gap-3 text-n-ruby-11"
    >
      {{ error }}
      <Button
        :label="t('ARROYO.PANEL.FUNNEL.RETRY')"
        slate
        sm
        data-testid="funnel-retry"
        @click="fetchReport"
      />
    </div>
    <div v-if="loading && !report" class="flex justify-center py-10">
      <Spinner />
    </div>
    <div
      v-if="report"
      role="status"
      aria-live="polite"
      class="flex min-h-5 items-center gap-2 text-label-small text-n-slate-11"
      data-testid="funnel-refresh-status"
    >
      <span
        v-if="loading"
        class="i-lucide-refresh-cw size-3.5 shrink-0 motion-safe:animate-spin"
        aria-hidden="true"
      />
      <span v-if="loading">{{ t('ARROYO.PANEL.FUNNEL.UPDATING') }}</span>
      <span v-else-if="stale">{{
        t('ARROYO.PANEL.FUNNEL.PREVIOUS_RESULTS')
      }}</span>
    </div>
    <div
      v-if="report"
      class="flex min-w-0 flex-col gap-5"
      :class="{ 'opacity-60': !ready }"
      :inert="!ready"
    >
      <div v-if="showExport" class="flex justify-end">
        <Button
          icon="i-lucide-download"
          slate
          faded
          sm
          :disabled="exporting || !ready"
          :label="t('ARROYO.PANEL.EXPORT')"
          data-testid="funnel-export"
          @click="exportCsv"
        />
      </div>
      <p v-if="exportError" class="mb-0 text-n-ruby-11" role="alert">
        {{ exportError }}
      </p>
      <p
        v-if="!report.totals.received"
        class="mb-0 rounded-xl bg-n-solid-2 p-5 text-body-main text-n-slate-11"
      >
        {{ t('ARROYO.PANEL.FUNNEL.EMPTY') }}
      </p>
      <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <button
          v-for="metric in SUMMARY_METRICS"
          :key="metric"
          type="button"
          class="flex min-w-0 flex-col gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-4 text-start [@media(hover:hover)]:hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          :data-testid="`metric-${metric}`"
          @click="openDetails(metric)"
        >
          <span class="flex w-full items-start justify-between gap-2">
            <span class="min-w-0 break-words text-label-small text-n-slate-11">
              {{ label(metric) }}
            </span>
            <span
              class="hidden size-4 shrink-0 sm:block"
              :class="[metricIcons[metric], metricColor(metric)]"
              aria-hidden="true"
            />
          </span>
          <span
            class="text-3xl font-semibold tabular-nums"
            :class="metric === 'won' ? 'text-n-teal-11' : 'text-n-slate-12'"
          >
            {{ report.totals[metric] }}
          </span>
        </button>
      </div>
      <button
        v-if="report.totals.overdue"
        type="button"
        class="flex items-center gap-3 rounded-lg bg-n-amber-3 px-4 py-3 text-start [@media(hover:hover)]:hover:bg-n-amber-4 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
        data-testid="metric-overdue"
        @click="openDetails('overdue')"
      >
        <span
          class="i-lucide-clock-alert size-5 shrink-0 text-n-amber-11"
          aria-hidden="true"
        />
        <span class="min-w-0 flex-1 break-words text-body-main text-n-slate-12">
          {{
            t('ARROYO.PANEL.FUNNEL.OVERDUE_ALERT', {
              count: report.totals.overdue,
            })
          }}
        </span>
        <span class="hidden shrink-0 text-label-small text-n-amber-11 sm:block">
          {{ t('ARROYO.PANEL.FUNNEL.REVIEW') }}
        </span>
        <span
          class="i-lucide-arrow-right size-4 shrink-0 text-n-amber-11 rtl:rotate-180"
          aria-hidden="true"
        />
      </button>
      <section
        class="flex min-w-0 flex-col gap-5 rounded-xl border border-n-weak bg-n-solid-2 p-4 lg:p-5"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div class="flex min-w-0 items-center gap-1">
            <h2 class="text-heading-3 text-n-slate-12">
              {{ t('ARROYO.PANEL.FUNNEL.COHORT_TITLE') }}
            </h2>
            <FunnelHelp
              :title="t('ARROYO.PANEL.FUNNEL.COHORT_HELP_TITLE')"
              :text="t('ARROYO.PANEL.FUNNEL.COHORT_HELP')"
            />
          </div>
          <span class="text-label-small text-n-slate-10">
            {{ t('ARROYO.PANEL.FUNNEL.FLOW.PERIOD') }}
          </span>
        </div>
        <CohortFlow
          :report="report"
          :seller-ids="sellerIds"
          @drill-down="
            ({ metric, userId }) => openDetails(metric, 'cohort', userId)
          "
        />
        <details
          class="border-t border-n-weak pt-3 text-label-small text-n-slate-11"
        >
          <summary
            class="w-fit cursor-pointer rounded text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          >
            {{ t('ARROYO.PANEL.FUNNEL.ALL_STATES') }}
          </summary>
          <ul
            class="m-0 mt-3 grid list-none grid-cols-2 gap-2 p-0 md:grid-cols-4"
            data-testid="cohort-states"
          >
            <li v-for="metric in COHORT_STATES" :key="metric">
              <button
                type="button"
                class="flex w-full items-start justify-between gap-2 rounded-lg p-2 text-start [@media(hover:hover)]:hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
                :data-testid="`state-${metric}`"
                @click="openDetails(metric)"
              >
                <span class="min-w-0 break-words"> {{ label(metric) }} </span>
                <span class="font-medium tabular-nums text-n-slate-12">
                  {{ report.totals[metric] }}
                </span>
              </button>
            </li>
          </ul>
        </details>
      </section>
      <div
        class="grid min-w-0 items-start gap-5 xl:grid-cols-[minmax(0,2.3fr)_minmax(16rem,1fr)]"
      >
        <section
          class="flex min-w-0 flex-col gap-4 rounded-xl border border-n-weak bg-n-solid-2 p-4 lg:p-5"
        >
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="flex items-center gap-1">
              <h2 class="text-heading-3 text-n-slate-12">
                {{ t('ARROYO.PANEL.FUNNEL.ACTIVITY_TITLE') }}
              </h2>
              <FunnelHelp
                :title="t('ARROYO.PANEL.FUNNEL.ACTIVITY_HELP_TITLE')"
                :text="activityHelp"
              />
            </div>
            <div class="flex flex-wrap items-center gap-2">
              <label class="flex items-center text-label-small text-n-slate-11">
                <span class="sr-only">
                  {{ t('ARROYO.PANEL.FUNNEL.METRIC') }}
                </span>
                <Select
                  v-model="activityMetric"
                  :options="activityOptions"
                  data-testid="activity-metric"
                />
              </label>
              <label class="flex items-center text-label-small text-n-slate-11">
                <span class="sr-only">
                  {{ t('ARROYO.PANEL.FILTERS.GROUP_BY.LABEL') }}
                </span>
                <Select
                  :model-value="params.group_by"
                  :options="groupOptions"
                  data-testid="activity-group"
                  @update:model-value="emit('groupChanged', $event)"
                />
              </label>
            </div>
          </div>
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div
              class="flex min-w-0 flex-wrap gap-x-4 gap-y-1 text-label-small text-n-slate-11"
            >
              <span
                v-for="agent in report.agents"
                :key="agent.id"
                class="flex min-w-0 items-center gap-1.5"
              >
                <span
                  class="size-2 shrink-0 rounded-full"
                  :class="sellerPresentation(agent.id, sellerIds).dot"
                  aria-hidden="true"
                />
                <span class="break-words">
                  {{ agent.name }}
                </span>
              </span>
            </div>
            <button
              type="button"
              class="rounded text-start text-label-small text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
              data-testid="activity-total"
              @click="openDetails(activityMetric, 'activity')"
            >
              {{
                t('ARROYO.PANEL.FUNNEL.PERIOD_TOTAL', {
                  metric: label(activityMetric),
                  count: report.activity_totals[activityMetric],
                })
              }}
            </button>
          </div>
          <div class="h-48 min-w-0 sm:h-56" aria-hidden="true">
            <BarChart
              :collection="chartCollection"
              :chart-options="{
                onClick: onActivityClick,
                plugins: { legend: { display: false } },
              }"
            />
          </div>
          <button
            type="button"
            class="flex items-center justify-between gap-3 rounded border-t border-n-weak pt-3 text-start text-body-main text-n-blue-11 md:hidden focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
            data-testid="activity-table-toggle"
            aria-controls="arroyo-commercial-activity-table"
            :aria-expanded="showDailyTable"
            @click="showDailyTable = !showDailyTable"
          >
            {{
              showDailyTable
                ? t('ARROYO.PANEL.FUNNEL.HIDE_DAILY')
                : t('ARROYO.PANEL.FUNNEL.SHOW_DAILY')
            }}<span
              class="size-4 shrink-0"
              :class="
                showDailyTable ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
              "
              aria-hidden="true"
            />
          </button>
          <div
            id="arroyo-commercial-activity-table"
            class="min-w-0 overflow-x-auto overscroll-contain border-t border-n-weak pt-2"
            :class="showDailyTable ? 'block' : 'hidden md:block'"
          >
            <table class="w-full text-label-small">
              <caption class="sr-only">
                {{
                  label(activityMetric)
                }}
              </caption>
              <thead>
                <tr class="border-b border-n-weak text-n-slate-10">
                  <th scope="col" class="py-2 pe-3 text-start font-medium">
                    {{ t('ARROYO.PANEL.AGENT') }}
                  </th>
                  <th
                    v-for="period in periods"
                    :key="period"
                    scope="col"
                    class="whitespace-nowrap px-2 py-2 text-end font-medium"
                  >
                    {{ periodLabel(period) }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="agent in report.agents"
                  :key="agent.id"
                  class="border-b border-n-weak last:border-0"
                >
                  <th
                    scope="row"
                    class="max-w-40 break-words py-2 pe-3 text-start font-medium text-n-slate-11"
                  >
                    {{ agent.name }}
                  </th>
                  <td
                    v-for="period in periods"
                    :key="period"
                    class="p-1 text-end"
                  >
                    <button
                      type="button"
                      class="w-full rounded-md px-2 py-1.5 text-end font-medium tabular-nums text-n-blue-11 [@media(hover:hover)]:hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
                      :aria-label="`${agent.name}: ${label(activityMetric)}, ${periodLabel(period)}`"
                      :data-testid="`activity-${agent.id}-${period}`"
                      @click="
                        openDetails(
                          activityMetric,
                          'activity',
                          agent.id,
                          period
                        )
                      "
                    >
                      {{ agent.periods[period]?.[activityMetric] ?? 0 }}
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
        <div class="flex min-w-0 flex-col gap-3">
          <section
            class="flex min-w-0 flex-col gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-4 lg:p-5"
          >
            <h2 class="text-heading-3 text-n-slate-12">
              {{ t('ARROYO.PANEL.FUNNEL.REPURCHASE_TITLE') }}
            </h2>
            <div class="flex flex-col divide-y divide-n-weak">
              <button
                v-for="metric in RELATED_METRICS"
                :key="metric"
                type="button"
                class="flex min-w-0 items-center gap-3 py-4 text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
                :data-testid="`related-${metric}`"
                @click="openDetails(metric)"
              >
                <span
                  class="size-4 shrink-0"
                  :class="[metricIcons[metric], metricColor(metric)]"
                  aria-hidden="true"
                />
                <span
                  class="min-w-0 flex-1 break-words text-label-small text-n-slate-11"
                >
                  {{ label(metric) }}
                </span>
                <span
                  class="text-xl font-medium tabular-nums"
                  :class="
                    report.totals[metric]
                      ? metricColor(metric)
                      : 'text-n-slate-10'
                  "
                >
                  {{ report.totals[metric] }}
                </span>
              </button>
            </div>
            <router-link
              v-if="showPostSale"
              :to="{
                name: 'arroyo_post_sale',
                params: route.params,
                query: { ...route.query, tab: undefined },
              }"
              class="flex items-center justify-between gap-2 rounded border-t border-n-weak pt-3 text-body-main text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
            >
              {{ t('ARROYO.PANEL.FUNNEL.OPEN_POST_SALE')
              }}<span
                class="i-lucide-arrow-up-right size-4"
                aria-hidden="true"
              />
            </router-link>
          </section>
          <div
            class="flex flex-wrap items-center gap-x-2 gap-y-1 px-1 text-label-small text-n-slate-10"
          >
            <span
              class="i-lucide-shield-check size-4 shrink-0"
              aria-hidden="true"
            />
            <span data-testid="coverage">
              {{ t('ARROYO.PANEL.FUNNEL.COVERAGE', report.coverage) }}
            </span>
            <FunnelHelp
              :title="t('ARROYO.PANEL.FUNNEL.COHORT_HELP_TITLE')"
              :text="t('ARROYO.PANEL.FUNNEL.COHORT_HELP')"
            />
            <span class="basis-full" aria-live="polite">
              {{ t('ARROYO.PANEL.FUNNEL.AS_OF', { date: asOf }) }}
            </span>
          </div>
        </div>
      </div>
    </div>
    <OpportunitiesDrawer
      v-if="selection"
      :selection="selection"
      @close="selection = null"
      @updated="fetchReport"
    />
  </div>
</template>

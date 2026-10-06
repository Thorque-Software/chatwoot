<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BarChart from 'shared/components/charts/BarChart.vue';
import { formatDuration } from 'shared/helpers/timeHelper';
import { METRICS, TIME_METRICS, MAIN_METRIC, CHART_COLOR } from '../constants';
import { useMetricLabels } from '../useMetricLabels';

const props = defineProps({
  report: { type: Object, required: true },
});

const emit = defineEmits(['drillDown']);

const { t } = useI18n();

const metricLabels = useMetricLabels();

const formatValue = (metric, value) => {
  if (value === null || value === undefined) return t('ARROYO.PANEL.NO_DATA');
  return TIME_METRICS.includes(metric) ? formatDuration(value) : value;
};

const chartCollection = computed(() => ({
  labels: props.report.agents.map(agent => agent.name),
  datasets: [
    {
      label: metricLabels.value[MAIN_METRIC],
      backgroundColor: CHART_COLOR,
      data: props.report.agents.map(agent => agent.totals[MAIN_METRIC]),
    },
  ],
}));

const periodLabel = period =>
  props.report.group_by === 'week'
    ? t('ARROYO.PANEL.WEEK_OF', { date: period })
    : period;
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
      <button
        v-for="metric in METRICS"
        :key="metric"
        type="button"
        class="flex flex-col gap-2 p-4 text-start rounded-xl bg-n-solid-2 outline outline-1 outline-n-container hover:bg-n-alpha-2"
        @click="emit('drillDown', { metric })"
      >
        <span class="text-label-small text-n-slate-11">
          {{ metricLabels[metric] }}
        </span>
        <span class="text-heading-1 text-n-slate-12">
          {{ formatValue(metric, report.totals[metric]) }}
        </span>
      </button>
    </div>

    <section
      class="flex flex-col gap-3 p-4 rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
    >
      <h3 class="text-heading-3 text-n-slate-12">
        {{ t('ARROYO.PANEL.CHART_TITLE') }}
      </h3>
      <div class="h-64">
        <BarChart :collection="chartCollection" />
      </div>
    </section>

    <section
      class="flex flex-col gap-3 p-4 rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
    >
      <h3 class="text-heading-3 text-n-slate-12">
        {{ t('ARROYO.PANEL.SUMMARY_TITLE') }}
      </h3>
      <div class="overflow-x-auto">
        <table class="w-full text-body-main">
          <thead>
            <tr class="text-label-small text-n-slate-11 border-b border-n-weak">
              <th class="py-2 pe-4 text-start font-medium">
                {{ t('ARROYO.PANEL.AGENT') }}
              </th>
              <th
                v-for="metric in METRICS"
                :key="metric"
                class="py-2 px-2 text-end font-medium"
              >
                {{ metricLabels[metric] }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="agent in report.agents"
              :key="agent.id"
              class="border-b border-n-weak last:border-b-0"
            >
              <td class="py-2 pe-4 text-n-slate-12 whitespace-nowrap">
                {{ agent.name }}
              </td>
              <td
                v-for="metric in METRICS"
                :key="metric"
                class="py-1 px-1 text-end"
              >
                <button
                  type="button"
                  class="w-full px-1 py-1 text-end rounded-md text-n-slate-12 hover:bg-n-alpha-2"
                  @click="emit('drillDown', { metric, userId: agent.id })"
                >
                  {{ formatValue(metric, agent.totals[metric]) }}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <section
      class="flex flex-col gap-3 p-4 rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
    >
      <h3 class="text-heading-3 text-n-slate-12">
        {{ t('ARROYO.PANEL.DAILY_TITLE') }}
      </h3>
      <div class="overflow-x-auto">
        <table class="w-full text-body-main">
          <thead>
            <tr class="text-label-small text-n-slate-11 border-b border-n-weak">
              <th class="py-2 pe-4 text-start font-medium">
                {{ t('ARROYO.PANEL.AGENT') }}
              </th>
              <th
                v-for="period in report.periods"
                :key="period"
                class="py-2 px-2 text-end font-medium whitespace-nowrap"
              >
                {{ periodLabel(period) }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="agent in report.agents"
              :key="agent.id"
              class="border-b border-n-weak last:border-b-0"
            >
              <td class="py-2 pe-4 text-n-slate-12 whitespace-nowrap">
                {{ agent.name }}
              </td>
              <td
                v-for="period in report.periods"
                :key="period"
                class="py-1 px-1 text-end"
              >
                <button
                  type="button"
                  class="w-full px-1 py-1 text-end rounded-md text-n-slate-12 hover:bg-n-alpha-2"
                  :data-testid="`cell-${agent.id}-${period}`"
                  @click="
                    emit('drillDown', {
                      metric: MAIN_METRIC,
                      userId: agent.id,
                      period,
                    })
                  "
                >
                  {{ agent.periods[period][MAIN_METRIC] }}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>

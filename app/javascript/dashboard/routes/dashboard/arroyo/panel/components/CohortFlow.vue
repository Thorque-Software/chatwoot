<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useResizeObserver } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useCommercialLabels } from '../useCommercialLabels';
import { sellerPresentation } from '../commercialConstants';

const props = defineProps({
  report: { type: Object, required: true },
  sellerIds: { type: Array, default: () => [] },
});
const emit = defineEmits(['drillDown']);
const { t } = useI18n();
const labels = useCommercialLabels();
const flowRoot = ref(null);
const receivedNode = ref(null);
const stageNodes = ref([]);
const sellerNodes = ref([]);
const intakePath = ref('');
const sellerPath = ref('');

const connectorPath = (source, targets, origin) => {
  if (!source || !targets.length) return '';
  const start = source.getBoundingClientRect();
  const ends = targets
    .map(node => node.getBoundingClientRect())
    .filter(end => end.left > start.right);
  if (!ends.length) return '';
  const x = start.right - origin.left;
  const y = start.top + start.height / 2 - origin.top;
  const branch =
    (start.right + Math.min(...ends.map(end => end.left))) / 2 - origin.left;
  const centers = ends.map(end => end.top + end.height / 2 - origin.top);
  const segments = [
    `M ${x} ${y} H ${branch}`,
    `M ${branch} ${Math.min(y, ...centers)} V ${Math.max(y, ...centers)}`,
  ];
  ends.forEach((end, index) => {
    const targetX = end.left - origin.left;
    const targetY = centers[index];
    segments.push(
      `M ${branch} ${targetY} H ${targetX}`,
      `M ${targetX - 4} ${targetY - 4} L ${targetX} ${targetY} L ${targetX - 4} ${targetY + 4}`
    );
  });
  return segments.join(' ');
};

const updateConnectors = () => {
  if (!flowRoot.value) return;
  const origin = flowRoot.value.getBoundingClientRect();
  intakePath.value = connectorPath(
    receivedNode.value,
    stageNodes.value,
    origin
  );
  const assigned = stageNodes.value.find(
    node => node.dataset.flowStage === 'assigned'
  );
  sellerPath.value = connectorPath(assigned, sellerNodes.value, origin);
};
onMounted(updateConnectors);
watch(() => props.report, updateConnectors, { deep: true, flush: 'post' });
useResizeObserver(
  () => [
    flowRoot.value,
    receivedNode.value,
    ...stageNodes.value,
    ...sellerNodes.value,
  ],
  updateConnectors
);
const ids = computed(() =>
  props.sellerIds.length
    ? props.sellerIds
    : props.report.agents.map(agent => agent.id)
);
const stages = [
  { metric: 'bot', icon: 'i-lucide-bot', color: 'text-n-violet-11' },
  {
    metric: 'unassigned',
    icon: 'i-lucide-user-round-x',
    color: 'text-n-slate-11',
  },
  { metric: 'assigned', icon: 'i-lucide-users-round', color: 'text-n-blue-11' },
];
const states = computed(() => [
  {
    metric: 'won',
    label: t('ARROYO.PANEL.FUNNEL.FLOW.WON'),
    color: 'text-n-teal-11',
  },
  {
    metric: 'pending',
    label: t('ARROYO.PANEL.FUNNEL.FLOW.PENDING'),
    color: 'text-n-amber-11',
  },
  {
    metric: 'lost',
    label: t('ARROYO.PANEL.FUNNEL.FLOW.LOST'),
    color: 'text-n-ruby-11',
  },
  {
    metric: 'in_progress',
    label: t('ARROYO.PANEL.FUNNEL.FLOW.IN_PROGRESS'),
    color: 'text-n-blue-11',
  },
  {
    metric: 'inactive',
    label: t('ARROYO.PANEL.FUNNEL.FLOW.INACTIVE'),
    color: 'text-n-slate-11',
  },
  {
    metric: 'unknown',
    label: t('ARROYO.PANEL.FUNNEL.METRICS.UNKNOWN'),
    color: 'text-n-slate-11',
  },
]);
const initials = name =>
  name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map(part => part[0])
    .join('');
</script>

<template>
  <div
    ref="flowRoot"
    class="relative grid min-w-0 gap-5 lg:grid-cols-[minmax(0,0.8fr)_minmax(0,0.8fr)_minmax(0,2.2fr)]"
    data-testid="cohort-flow"
  >
    <svg
      class="pointer-events-none absolute inset-0 hidden size-full overflow-hidden fill-none stroke-current stroke-1 lg:block"
      aria-hidden="true"
      focusable="false"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <path
        v-if="intakePath"
        :d="intakePath"
        class="text-n-slate-8"
        data-testid="flow-intake-connectors"
      />
      <path
        v-if="sellerPath"
        :d="sellerPath"
        class="text-n-blue-8"
        data-testid="flow-seller-connectors"
      />
    </svg>
    <div class="relative flex min-w-0 flex-col gap-4">
      <span
        class="hidden text-label-small font-medium uppercase tracking-wide text-n-slate-10 lg:block"
      >
        {{ t('ARROYO.PANEL.FUNNEL.FLOW.INGRESS') }}
      </span>
      <div class="flex flex-1 items-center">
        <button
          ref="receivedNode"
          type="button"
          data-testid="flow-received"
          class="flex w-full items-center gap-4 rounded-lg border border-n-blue-7 bg-n-blue-3 p-4 text-start lg:min-h-24 lg:flex-col lg:items-start lg:gap-1 [@media(hover:hover)]:hover:bg-n-blue-4 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          @click="emit('drillDown', { metric: 'received' })"
        >
          <span class="text-3xl font-semibold tabular-nums text-n-slate-12">
            {{ report.totals.received }}
          </span>
          <span class="text-label-small text-n-blue-11">
            {{ labels.received }}
          </span>
        </button>
      </div>
    </div>
    <div class="relative flex min-w-0 flex-col gap-4">
      <span
        class="hidden text-label-small font-medium uppercase tracking-wide text-n-slate-10 lg:block"
      >
        {{ t('ARROYO.PANEL.FUNNEL.FLOW.HANDOFF') }}
      </span>
      <div
        class="relative grid flex-1 grid-cols-2 items-center gap-3 lg:grid-cols-1 lg:ps-4"
      >
        <button
          v-for="stage in stages"
          :key="stage.metric"
          ref="stageNodes"
          type="button"
          :data-flow-stage="stage.metric"
          :data-testid="`flow-${stage.metric}`"
          class="relative flex min-h-12 min-w-0 items-center gap-2 rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-start [@media(hover:hover)]:hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          :class="{
            'col-span-2 lg:col-span-1': stage.metric === 'assigned',
          }"
          @click="emit('drillDown', { metric: stage.metric })"
        >
          <span
            class="size-4 shrink-0"
            :class="[stage.icon, stage.color]"
            aria-hidden="true"
          />
          <span
            class="min-w-0 flex-1 break-words text-label-small text-n-slate-11"
          >
            {{ labels[stage.metric] }}
          </span>
          <span class="text-lg font-semibold tabular-nums text-n-slate-12">
            {{ report.totals[stage.metric] }}
          </span>
        </button>
      </div>
    </div>
    <div class="flex min-w-0 flex-col gap-4">
      <span
        class="hidden text-label-small font-medium uppercase tracking-wide text-n-slate-10 lg:block"
      >
        {{ t('ARROYO.PANEL.FUNNEL.FLOW.TEAM_RESULTS') }}
      </span>
      <div class="flex flex-1 flex-col gap-3 lg:ps-5">
        <article
          v-for="agent in report.agents"
          :key="agent.id"
          ref="sellerNodes"
          data-testid="flow-seller"
          class="relative min-w-0 rounded-lg border border-n-weak bg-n-surface-1 px-4 py-3"
        >
          <div class="flex min-w-0 items-start gap-3">
            <span
              class="flex size-8 shrink-0 items-center justify-center rounded-full text-label-small font-medium"
              :class="sellerPresentation(agent.id, ids).avatar"
              aria-hidden="true"
            >
              {{ initials(agent.name) }}
            </span>
            <div class="min-w-0 flex-1">
              <h3
                class="break-words text-body-main font-semibold text-n-slate-12"
              >
                {{ agent.name }}
              </h3>
              <div
                class="flex flex-wrap gap-x-3 gap-y-1 text-label-small text-n-slate-11"
              >
                <button
                  v-for="metric in ['assigned', 'attended']"
                  :key="metric"
                  type="button"
                  :data-testid="`flow-${agent.id}-${metric}`"
                  class="rounded text-start [@media(hover:hover)]:hover:text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
                  @click="emit('drillDown', { metric, userId: agent.id })"
                >
                  {{
                    t('ARROYO.PANEL.FUNNEL.MILESTONE_COUNT', {
                      metric: labels[metric],
                      count: agent.totals[metric] ?? 0,
                    })
                  }}
                </button>
              </div>
            </div>
          </div>
          <div
            class="mt-3 flex flex-wrap gap-x-4 gap-y-2 border-t border-n-weak pt-2"
          >
            <template v-for="state in states" :key="state.metric">
              <button
                v-if="agent.totals[state.metric]"
                type="button"
                :data-testid="`flow-${agent.id}-${state.metric}`"
                :aria-label="`${agent.name}: ${labels[state.metric]}`"
                class="flex min-w-0 items-baseline gap-1.5 rounded text-start [@media(hover:hover)]:hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
                @click="
                  emit('drillDown', { metric: state.metric, userId: agent.id })
                "
              >
                <span class="font-semibold tabular-nums" :class="state.color">
                  {{ agent.totals[state.metric] }}
                </span>
                <span class="break-words text-label-small text-n-slate-11">
                  {{ state.label }}
                </span>
              </button>
            </template>
          </div>
        </article>
        <p
          v-if="!report.agents.length"
          class="mb-0 p-3 text-label-small text-n-slate-11"
        >
          {{ t('ARROYO.PANEL.FUNNEL.FLOW.NO_SELLERS') }}
        </p>
      </div>
    </div>
  </div>
</template>

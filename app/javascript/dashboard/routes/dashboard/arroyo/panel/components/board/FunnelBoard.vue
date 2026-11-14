<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BoardAPI from '../../../api/board';
import OpportunitiesDrawer from '../OpportunitiesDrawer.vue';
import FunnelHelp from '../FunnelHelp.vue';
import FlowChart from './FlowChart.vue';
import SellerTables from './SellerTables.vue';
import OriginsTable from './OriginsTable.vue';
import BoardExtras from './BoardExtras.vue';
import { STAGE_COLORS } from './boardColors';
import { useBoardLabels } from './useBoardLabels';

// Embudo unificado del panel de vendedores (funnel_board): una sola pestaña con el recorrido de las
// consultas, el detalle por vendedor y por día, las ventas por anuncio, recompras y postventa.
const props = defineProps({
  params: { type: Object, required: true },
  sellerIds: { type: Array, default: () => [] },
});
const { t, locale } = useI18n();
const { stages, nodeLabel } = useBoardLabels();

const data = ref(null);
const loading = ref(false);
const error = ref('');
const exporting = ref(false);
const originLevel = ref('campaign');
const selection = ref(null);
let request = 0;

const requestParams = computed(() => ({
  since: props.params.since,
  until: props.params.until,
  user_ids: props.params.user_ids,
  inbox_ids: props.params.inbox_ids,
  origin_level: originLevel.value,
}));

const fetchBoard = async () => {
  request += 1;
  const current = request;
  loading.value = true;
  error.value = '';
  try {
    const response = await BoardAPI.get(requestParams.value);
    if (current === request) data.value = response.data;
  } catch {
    if (current === request) error.value = t('ARROYO.PANEL.BOARD.LOAD_ERROR');
  } finally {
    if (current === request) loading.value = false;
  }
};

const percent = (part, total) => (total ? Math.round((part / total) * 100) : 0);
const totals = computed(() => data.value?.totals || {});
const stuck = computed(
  () => (totals.value.pending || 0) + (totals.value.abandoned || 0)
);
const kpis = computed(() => [
  {
    key: 'received',
    label: t('ARROYO.PANEL.BOARD.KPI.RECEIVED'),
    value: totals.value.received,
    note: t('ARROYO.PANEL.BOARD.KPI.FROM_ADS', {
      ads: totals.value.from_ads,
      organic: totals.value.organic,
    }),
    filter: {},
  },
  {
    key: 'waiting',
    label: t('ARROYO.PANEL.BOARD.KPI.WAITING'),
    value: (totals.value.bot || 0) + (totals.value.unassigned || 0),
    note: t('ARROYO.PANEL.BOARD.KPI.WAITING_NOTE', {
      bot: totals.value.bot,
      unassigned: totals.value.unassigned,
    }),
    filter: { bucket: 'waiting' },
    color: STAGE_COLORS.bot,
  },
  {
    key: 'pending',
    label: t('ARROYO.PANEL.BOARD.KPI.PENDING'),
    value: totals.value.pending,
    note: t('ARROYO.PANEL.BOARD.KPI.PENDING_NOTE'),
    filter: { stage: 'pending' },
    color: STAGE_COLORS.pending,
  },
  {
    key: 'attended',
    label: t('ARROYO.PANEL.BOARD.KPI.ATTENDED'),
    value: totals.value.attended,
    note: t('ARROYO.PANEL.BOARD.KPI.ATTENDED_RATE', {
      rate: percent(totals.value.attended, totals.value.assigned),
    }),
    filter: { attended: 'true' },
    color: STAGE_COLORS.in_progress,
  },
  {
    key: 'won',
    label: t('ARROYO.PANEL.BOARD.KPI.WON'),
    value: totals.value.won,
    note: t('ARROYO.PANEL.BOARD.KPI.WON_RATE', {
      rate: percent(totals.value.won, totals.value.received),
    }),
    filter: { stage: 'won' },
    color: STAGE_COLORS.won,
  },
  {
    key: 'lost',
    label: t('ARROYO.PANEL.BOARD.KPI.LOST'),
    value: totals.value.lost,
    note: t('ARROYO.PANEL.BOARD.KPI.LOST_NOTE'),
    filter: { stage: 'lost' },
    color: STAGE_COLORS.lost,
  },
  {
    key: 'abandoned',
    label: t('ARROYO.PANEL.BOARD.KPI.ABANDONED'),
    value: totals.value.abandoned,
    note: t('ARROYO.PANEL.BOARD.KPI.NUDGED', { count: totals.value.nudged }),
    filter: { stage: 'abandoned' },
    color: STAGE_COLORS.abandoned,
  },
]);

const levelLabels = computed(() => ({
  campaign: t('ARROYO.PANEL.BOARD.FLOW.LEVEL_CAMPAIGN'),
  ad: t('ARROYO.PANEL.BOARD.FLOW.LEVEL_AD'),
}));

const asOf = computed(() =>
  new Intl.DateTimeFormat(locale.value, {
    timeZone: data.value.timezone,
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(data.value.as_of))
);

const openDetails = (title, filter = {}) => {
  selection.value = {
    source: 'board',
    title,
    params: { ...requestParams.value, ...filter },
  };
};

const NODE_FILTERS = {
  origin: node => ({ origin: node.key }),
  seller: node => ({ bucket: node.key }),
  bot: () => ({ bucket: 'bot' }),
  unassigned: () => ({ bucket: 'unassigned' }),
  stage: node => ({ stage: node.key }),
};
const onNode = node =>
  openDetails(nodeLabel(node), NODE_FILTERS[node.kind]?.(node) || {});

const exportCsv = async () => {
  exporting.value = true;
  try {
    const response = await BoardAPI.exportCsv(requestParams.value);
    downloadCsvFile(
      `embudo_${props.params.since}_${props.params.until}.csv`,
      response.data
    );
  } catch {
    error.value = t('ARROYO.PANEL.BOARD.EXPORT_ERROR');
  } finally {
    exporting.value = false;
  }
};

watch(
  requestParams,
  () => {
    selection.value = null;
    fetchBoard();
  },
  { immediate: true, deep: true }
);
defineExpose({ exportCsv, exporting, ready: computed(() => !!data.value) });
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
        :label="t('ARROYO.PANEL.BOARD.RETRY')"
        slate
        sm
        @click="fetchBoard"
      />
    </div>
    <div v-if="loading && !data" class="flex justify-center py-10">
      <Spinner />
    </div>

    <template v-if="data">
      <div
        class="flex flex-col gap-5 transition-opacity"
        :class="{ 'opacity-60': loading }"
      >
        <div
          class="grid grid-cols-2 gap-3 sm:grid-cols-4 xl:grid-cols-7"
          data-testid="board-kpis"
        >
          <button
            v-for="kpi in kpis"
            :key="kpi.key"
            type="button"
            class="flex min-w-0 flex-col gap-1 rounded-xl border border-n-weak bg-n-solid-2 p-4 text-start [@media(hover:hover)]:hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
            :data-testid="`board-kpi-${kpi.key}`"
            @click="openDetails(kpi.label, kpi.filter)"
          >
            <span
              class="flex items-center gap-2 text-label-small text-n-slate-11"
            >
              <span
                v-if="kpi.color"
                class="size-2 shrink-0 rounded-full"
                :style="{ background: kpi.color }"
                aria-hidden="true"
              />
              {{ kpi.label }}
            </span>
            <span class="text-3xl font-semibold tabular-nums text-n-slate-12">
              {{ kpi.value ?? 0 }}
            </span>
            <span class="text-label-small text-n-slate-10">{{ kpi.note }}</span>
          </button>
        </div>

        <button
          v-if="stuck"
          type="button"
          class="flex items-center gap-3 rounded-lg bg-n-amber-3 px-4 py-3 text-start [@media(hover:hover)]:hover:bg-n-amber-4 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          data-testid="board-stuck"
          @click="openDetails(stages.pending, { stage: 'pending' })"
        >
          <span
            class="i-lucide-octagon-alert size-5 shrink-0 text-n-amber-11"
            aria-hidden="true"
          />
          <span class="min-w-0 flex-1 text-body-main text-n-slate-12">
            {{
              t('ARROYO.PANEL.BOARD.STUCK_ALERT', {
                total: stuck,
                pending: totals.pending,
                abandoned: totals.abandoned,
              })
            }}
          </span>
          <span
            class="i-lucide-arrow-right size-4 shrink-0 text-n-amber-11 rtl:rotate-180"
            aria-hidden="true"
          />
        </button>

        <section
          class="flex min-w-0 flex-col gap-4 rounded-xl border border-n-weak bg-n-solid-2 p-4 lg:p-5"
        >
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="flex items-center gap-1">
              <h2 class="text-heading-3 text-n-slate-12">
                {{ t('ARROYO.PANEL.BOARD.FLOW.TITLE') }}
              </h2>
              <FunnelHelp
                :title="t('ARROYO.PANEL.BOARD.FLOW.TITLE')"
                :text="t('ARROYO.PANEL.BOARD.FLOW.HELP')"
              />
            </div>
            <div
              class="flex rounded-lg border border-n-weak p-0.5 text-label-small"
              role="radiogroup"
              :aria-label="t('ARROYO.PANEL.BOARD.FLOW.LEVEL')"
            >
              <button
                v-for="level in ['campaign', 'ad']"
                :key="level"
                type="button"
                role="radio"
                :aria-checked="originLevel === level"
                class="rounded-md px-3 py-1"
                :class="
                  originLevel === level
                    ? 'bg-n-alpha-2 text-n-slate-12'
                    : 'text-n-slate-11'
                "
                :data-testid="`board-level-${level}`"
                @click="originLevel = level"
              >
                {{ levelLabels[level] }}
              </button>
            </div>
          </div>
          <div
            class="grid grid-cols-3 px-1 text-label-small font-medium uppercase tracking-wide text-n-slate-10"
            aria-hidden="true"
          >
            <span>{{ t('ARROYO.PANEL.BOARD.FLOW.COLUMNS.ORIGIN') }}</span>
            <span class="text-center">{{
              t('ARROYO.PANEL.BOARD.FLOW.COLUMNS.OWNER')
            }}</span>
            <span class="text-end">{{
              t('ARROYO.PANEL.BOARD.FLOW.COLUMNS.STAGE')
            }}</span>
          </div>
          <p
            v-if="!data.flow.nodes.length"
            class="mb-0 rounded-lg bg-n-alpha-1 p-5 text-body-main text-n-slate-11"
          >
            {{ t('ARROYO.PANEL.BOARD.EMPTY') }}
          </p>
          <FlowChart
            v-else
            :flow="data.flow"
            :seller-ids="sellerIds"
            :node-label="nodeLabel"
            @select="onNode"
          />
          <div
            v-if="data.info_labels.length"
            class="flex flex-wrap items-center gap-2 border-t border-n-weak pt-3"
            data-testid="board-info-labels"
          >
            <span class="text-label-small text-n-slate-10">
              {{ t('ARROYO.PANEL.BOARD.INFO_LABELS') }}
            </span>
            <button
              v-for="item in data.info_labels"
              :key="item.label"
              type="button"
              class="flex items-center gap-1.5 rounded-full border border-dashed border-n-weak px-3 py-1 text-label-small text-n-slate-11 [@media(hover:hover)]:hover:bg-n-alpha-2"
              @click="openDetails(item.label, { label: item.label })"
            >
              <span class="i-lucide-tag size-3.5" aria-hidden="true" />
              {{ item.label }}
              <span class="font-semibold tabular-nums text-n-slate-12">
                {{ item.count }}
              </span>
            </button>
          </div>
        </section>

        <SellerTables
          :data="data"
          :seller-ids="sellerIds"
          @select="({ title, filter }) => openDetails(title, filter)"
        />
        <OriginsTable
          :origins="data.origins"
          @select="({ title, filter }) => openDetails(title, filter)"
        />
        <BoardExtras
          :data="data"
          @select="({ title, filter }) => openDetails(title, filter)"
        />

        <div
          class="flex flex-wrap items-center gap-x-4 gap-y-1 px-1 text-label-small text-n-slate-10"
        >
          <span>{{ t('ARROYO.PANEL.BOARD.AS_OF', { date: asOf }) }}</span>
          <span>{{ t('ARROYO.PANEL.BOARD.REASSIGN_NOTE') }}</span>
          <span>{{ t('ARROYO.PANEL.BOARD.HISTORY_NOTE') }}</span>
        </div>
      </div>
    </template>

    <OpportunitiesDrawer
      v-if="selection"
      :selection="selection"
      @close="selection = null"
      @updated="fetchBoard"
    />
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ArroyoAgentPanelAPI from '../api/agentPanel';
import { useArroyoFeatures } from '../composables/useArroyoFeatures';
import PanelFilters from './components/PanelFilters.vue';
import ActivityTab from './components/ActivityTab.vue';
import WindowsTab from './components/WindowsTab.vue';
import ConversationsDrawer from './components/ConversationsDrawer.vue';
import {
  DATE_PRESETS,
  DEFAULT_PRESET,
  GROUP_BY_OPTIONS,
  TABS,
} from './constants';
import { todayIn, presetRange, periodRange, parseIds } from './helpers';
import { useMetricLabels } from './useMetricLabels';

const { t } = useI18n();
const metricLabels = useMetricLabels();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { features, timezone, fetchFeatures } = useArroyoFeatures();

const agents = useMapGetter('agents/getAgents');
const inboxes = useMapGetter('inboxes/getInboxes');
const currentRole = useMapGetter('getCurrentRole');

const report = ref(null);
const windows = ref(null);
const isLoading = ref(false);
const drawer = ref({
  open: false,
  title: '',
  subtitle: '',
  conversations: [],
  count: 0,
  isLoading: false,
});

const agentOptions = computed(() =>
  agents.value.map(agent => ({ id: agent.id, name: agent.name }))
);
const inboxOptions = computed(() =>
  inboxes.value.map(inbox => ({ id: inbox.id, name: inbox.name }))
);

const showAgentFilter = computed(
  () =>
    currentRole.value === 'administrator' ||
    !features.value?.agent_panel?.agents_see_only_own
);

// Los filtros viven en la URL para poder compartir el link
const filters = computed(() => {
  const { query } = route;
  const preset = DATE_PRESETS.includes(query.preset)
    ? query.preset
    : DEFAULT_PRESET;
  const range =
    preset === 'custom' && query.since && query.until
      ? { since: query.since, until: query.until }
      : presetRange(preset, todayIn(timezone.value));
  return {
    preset,
    ...range,
    groupBy: GROUP_BY_OPTIONS.includes(query.group_by) ? query.group_by : 'day',
    userIds: parseIds(query.user_ids),
    inboxIds: parseIds(query.inbox_ids),
  };
});

const activeTab = computed(() =>
  TABS.includes(route.query.tab) ? route.query.tab : 'activity'
);

const tabs = computed(() => [
  { key: 'activity', label: t('ARROYO.PANEL.TABS.ACTIVITY') },
  { key: 'windows', label: t('ARROYO.PANEL.TABS.WINDOWS') },
]);

const apiParams = computed(() => ({
  since: filters.value.since,
  until: filters.value.until,
  group_by: filters.value.groupBy,
  user_ids: filters.value.userIds.length ? filters.value.userIds : undefined,
  inbox_ids: filters.value.inboxIds.length ? filters.value.inboxIds : undefined,
}));

const updateQuery = changes => {
  router.replace({ query: { ...route.query, ...changes } });
};

const onFiltersChange = changes => {
  const next = { ...filters.value, ...changes };
  updateQuery({
    preset: next.preset,
    since: next.preset === 'custom' ? next.since : undefined,
    until: next.preset === 'custom' ? next.until : undefined,
    group_by: next.groupBy,
    user_ids: next.userIds.join(',') || undefined,
    inbox_ids: next.inboxIds.join(',') || undefined,
  });
};

const alertError = error => {
  const errors = error?.response?.data?.errors;
  useAlert(errors?.length ? errors.join(', ') : t('ARROYO.PANEL.API.ERROR'));
};

const fetchActiveTab = async () => {
  isLoading.value = true;
  try {
    if (activeTab.value === 'windows') {
      const { data } = await ArroyoAgentPanelAPI.getWindows({
        user_ids: apiParams.value.user_ids,
        inbox_ids: apiParams.value.inbox_ids,
      });
      windows.value = data;
    } else {
      const { data } = await ArroyoAgentPanelAPI.getReport(apiParams.value);
      report.value = data;
    }
  } catch (error) {
    alertError(error);
  } finally {
    isLoading.value = false;
  }
};

const openDrillDown = async ({ metric, userId, period }) => {
  const range = period
    ? periodRange(period, filters.value.groupBy, filters.value)
    : { since: filters.value.since, until: filters.value.until };
  const agent = report.value.agents.find(item => item.id === userId);
  drawer.value = {
    open: true,
    title: metricLabels.value[metric],
    subtitle: t('ARROYO.PANEL.DRAWER.SUBTITLE', {
      agent: agent ? agent.name : t('ARROYO.PANEL.DRAWER.ALL_AGENTS'),
      since: range.since,
      until: range.until,
    }),
    conversations: [],
    count: 0,
    isLoading: true,
  };
  try {
    const { data } = await ArroyoAgentPanelAPI.getConversations({
      ...apiParams.value,
      ...range,
      metric,
      user_ids: userId ? [userId] : apiParams.value.user_ids,
    });
    drawer.value = { ...drawer.value, ...data };
  } catch (error) {
    alertError(error);
  } finally {
    drawer.value.isLoading = false;
  }
};

const exportCsv = async () => {
  try {
    const { data } = await ArroyoAgentPanelAPI.exportReport(apiParams.value);
    downloadCsvFile(
      `panel_vendedores_${filters.value.since}_${filters.value.until}.csv`,
      data
    );
  } catch (error) {
    alertError(error);
  }
};

watch([apiParams, activeTab], () => {
  if (timezone.value) fetchActiveTab();
});

onMounted(async () => {
  store.dispatch('agents/get');
  if (!features.value) await fetchFeatures();
  if (timezone.value) fetchActiveTab();
});
</script>

<template>
  <div class="w-full px-6 overflow-auto bg-n-surface-1">
    <div class="flex flex-col gap-5 pb-12 mx-auto max-w-6xl">
      <header class="flex flex-wrap items-start justify-between gap-4 pt-6">
        <div class="flex flex-col gap-2">
          <h1 class="text-heading-1 text-n-slate-12">
            {{ t('ARROYO.PANEL.TITLE') }}
          </h1>
          <p class="mb-0 text-body-main text-n-slate-11">
            {{ t('ARROYO.PANEL.DESCRIPTION') }}
          </p>
        </div>
        <Button
          v-if="activeTab === 'activity'"
          icon="i-lucide-download"
          slate
          faded
          sm
          :label="t('ARROYO.PANEL.EXPORT')"
          @click="exportCsv"
        />
      </header>

      <TabBar
        :tabs="tabs"
        :initial-active-tab="TABS.indexOf(activeTab)"
        @tab-changed="tab => updateQuery({ tab: tab.key })"
      />

      <PanelFilters
        :filters="filters"
        :agent-options="agentOptions"
        :inbox-options="inboxOptions"
        :show-agent-filter="showAgentFilter"
        :show-date-filters="activeTab === 'activity'"
        @change="onFiltersChange"
      />

      <template v-if="activeTab === 'activity'">
        <div v-if="!report" class="flex justify-center py-10">
          <Spinner />
        </div>
        <ActivityTab
          v-else
          :report="report"
          :class="{ 'opacity-60': isLoading }"
          @drill-down="openDrillDown"
        />
      </template>
      <WindowsTab v-else :windows="windows" :is-loading="isLoading" />
    </div>

    <ConversationsDrawer
      v-model:open="drawer.open"
      :title="drawer.title"
      :subtitle="drawer.subtitle"
      :conversations="drawer.conversations"
      :count="drawer.count"
      :is-loading="drawer.isLoading"
    />
  </div>
</template>

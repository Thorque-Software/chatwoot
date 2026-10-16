<script setup>
import { ref, computed, watch } from 'vue';
import { vOnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { formatInTimeZone, zonedTimeToUtc } from 'date-fns-tz';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import PostSaleAPI from '../../api/postSale';
import { POST_SALE_STATUSES } from '../constants';

const props = defineProps({
  params: { type: Object, required: true },
  filterResetKey: { type: Number, default: 0 },
  timezone: { type: String, required: true },
  agents: { type: Array, default: () => [] },
});

const { t, locale } = useI18n();
const route = useRoute();
const status = ref('');
const stage = ref('');
const showAdvanced = ref(false);
const advancedTrigger = ref(null);
const showHelp = ref(false);
const summaryFilter = ref('');
const manualOnly = ref(false);
const page = ref(1);
const data = ref(null);
const isLoading = ref(false);
const loadError = ref('');
const selected = ref(null);
const purchaseFollowUps = ref([]);
const detailLoading = ref(false);
const detailError = ref('');
const mutationError = ref('');
const isSaving = ref(false);
const purchasedAt = ref('');
const method = ref('call');
const note = ref('');
let requestId = 0;
let detailRequestId = 0;

const labels = computed(() => ({
  status: {
    awaiting_plan: t('ARROYO.PANEL.POST_SALE.STATUSES.AWAITING_PLAN'),
    scheduled: t('ARROYO.PANEL.POST_SALE.STATUSES.SCHEDULED'),
    queued: t('ARROYO.PANEL.POST_SALE.STATUSES.QUEUED'),
    sent: t('ARROYO.PANEL.POST_SALE.STATUSES.SENT'),
    delivered: t('ARROYO.PANEL.POST_SALE.STATUSES.DELIVERED'),
    read: t('ARROYO.PANEL.POST_SALE.STATUSES.READ'),
    failed: t('ARROYO.PANEL.POST_SALE.STATUSES.FAILED'),
    unconfirmed: t('ARROYO.PANEL.POST_SALE.STATUSES.UNCONFIRMED'),
    not_executed: t('ARROYO.PANEL.POST_SALE.STATUSES.NOT_EXECUTED'),
    cancelled: t('ARROYO.PANEL.POST_SALE.STATUSES.CANCELLED'),
  },
  manual: {
    pending: t('ARROYO.PANEL.POST_SALE.MANUAL_STATUSES.PENDING'),
    resolved: t('ARROYO.PANEL.POST_SALE.MANUAL_STATUSES.RESOLVED'),
    closed_automatically: t(
      'ARROYO.PANEL.POST_SALE.MANUAL_STATUSES.CLOSED_AUTOMATICALLY'
    ),
  },
  methods: {
    call: t('ARROYO.PANEL.POST_SALE.METHODS.CALL'),
    personal_whatsapp: t('ARROYO.PANEL.POST_SALE.METHODS.PERSONAL_WHATSAPP'),
    other: t('ARROYO.PANEL.POST_SALE.METHODS.OTHER'),
  },
  stages: {
    d1: t('ARROYO.PANEL.POST_SALE.STAGES.D1'),
    d7: t('ARROYO.PANEL.POST_SALE.STAGES.D7'),
    d30: t('ARROYO.PANEL.POST_SALE.STAGES.D30'),
  },
}));
const dateLabels = computed(() => ({
  scheduled_at: t('ARROYO.PANEL.POST_SALE.DATES.SCHEDULED_AT'),
  attempted_at: t('ARROYO.PANEL.POST_SALE.DATES.ATTEMPTED_AT'),
  delivered_at: t('ARROYO.PANEL.POST_SALE.DATES.DELIVERED_AT'),
  read_at: t('ARROYO.PANEL.POST_SALE.DATES.READ_AT'),
  resolved_at: t('ARROYO.PANEL.POST_SALE.DATES.RESOLVED_AT'),
}));
const statusLabel = value => labels.value.status[value];
const manualLabel = value =>
  value ? labels.value.manual[value] : t('ARROYO.PANEL.NO_DATA');
const statusOptions = computed(() => [
  { value: '', label: t('ARROYO.PANEL.POST_SALE.ALL_STATUSES') },
  ...POST_SALE_STATUSES.map(value => ({ value, label: statusLabel(value) })),
]);
const stageOptions = computed(() => [
  { value: '', label: t('ARROYO.PANEL.POST_SALE.ALL_STAGES') },
  ...Object.entries(labels.value.stages).map(([value, label]) => ({
    value,
    label,
  })),
]);
const methodOptions = computed(() =>
  ['call', 'personal_whatsapp', 'other'].map(value => ({
    value,
    label: labels.value.methods[value],
  }))
);
const summaries = computed(() => {
  const totals = data.value?.totals || {};
  return [
    {
      key: 'scheduled',
      label: t('ARROYO.PANEL.POST_SALE.SUMMARY.SCHEDULED'),
      count: (totals.awaiting_plan || 0) + (totals.scheduled || 0),
    },
    {
      key: 'processing',
      label: t('ARROYO.PANEL.POST_SALE.SUMMARY.PROCESSING'),
      count: (totals.queued || 0) + (totals.sent || 0),
    },
    {
      key: 'delivered',
      label: t('ARROYO.PANEL.POST_SALE.SUMMARY.DELIVERED'),
      count: (totals.delivered || 0) + (totals.read || 0),
    },
    {
      key: 'failed',
      label: t('ARROYO.PANEL.POST_SALE.SUMMARY.FAILED'),
      count:
        (totals.failed || 0) +
        (totals.not_executed || 0) +
        (totals.unconfirmed || 0),
    },
  ];
});
const summaryHelp = computed(() => ({
  scheduled: t('ARROYO.PANEL.POST_SALE.SUMMARY_HELP.SCHEDULED'),
  processing: t('ARROYO.PANEL.POST_SALE.SUMMARY_HELP.PROCESSING'),
  delivered: t('ARROYO.PANEL.POST_SALE.SUMMARY_HELP.DELIVERED'),
  failed: t('ARROYO.PANEL.POST_SALE.SUMMARY_HELP.FAILED'),
  manual_pending: t('ARROYO.PANEL.POST_SALE.SUMMARY_HELP.MANUAL_PENDING'),
}));
const stateHelp = computed(() => ({
  awaiting_plan: t('ARROYO.PANEL.POST_SALE.STATE_HELP.AWAITING_PLAN'),
  scheduled: t('ARROYO.PANEL.POST_SALE.STATE_HELP.SCHEDULED'),
  queued: t('ARROYO.PANEL.POST_SALE.STATE_HELP.QUEUED'),
  sent: t('ARROYO.PANEL.POST_SALE.STATE_HELP.SENT'),
  delivered: t('ARROYO.PANEL.POST_SALE.STATE_HELP.DELIVERED'),
  read: t('ARROYO.PANEL.POST_SALE.STATE_HELP.READ'),
  failed: t('ARROYO.PANEL.POST_SALE.STATE_HELP.FAILED'),
  unconfirmed: t('ARROYO.PANEL.POST_SALE.STATE_HELP.UNCONFIRMED'),
  not_executed: t('ARROYO.PANEL.POST_SALE.STATE_HELP.NOT_EXECUTED'),
  cancelled: t('ARROYO.PANEL.POST_SALE.STATE_HELP.CANCELLED'),
}));
const filterExplanation = computed(
  () =>
    summaryHelp.value[summaryFilter.value] ||
    stateHelp.value[status.value] ||
    t('ARROYO.PANEL.POST_SALE.SUMMARY_HELP.ALL')
);
const nextAction = item => {
  if (item.manual_status === 'pending')
    return t('ARROYO.PANEL.POST_SALE.NEXT_ACTION.PENDING');
  if (item.manual_status === 'resolved')
    return t('ARROYO.PANEL.POST_SALE.NEXT_ACTION.RESOLVED');
  return stateHelp.value[item.status];
};
watch(
  () => props.filterResetKey,
  () => {
    status.value = '';
    stage.value = '';
    showAdvanced.value = false;
    summaryFilter.value = '';
    manualOnly.value = false;
    page.value = 1;
  }
);
const summaryStatuses = {
  scheduled: ['awaiting_plan', 'scheduled'],
  processing: ['queued', 'sent'],
  delivered: ['delivered', 'read'],
  failed: ['failed', 'not_executed', 'unconfirmed'],
};
const manualCount = computed(() => data.value?.totals?.manual_pending || 0);
const visibleStatus = value => {
  const group = Object.entries(summaryStatuses).find(([, values]) =>
    values.includes(value)
  );
  return (
    summaries.value.find(summary => summary.key === group?.[0])?.label ||
    statusLabel(value)
  );
};
const selectSummary = key => {
  status.value = '';
  summaryFilter.value = summaryFilter.value === key ? '' : key;
};
const closeAdvanced = () => {
  showAdvanced.value = false;
  advancedTrigger.value?.focus();
};
const selectStatus = value => {
  summaryFilter.value = '';
  status.value = value;
  closeAdvanced();
};
const statusClass = value => {
  if (['failed', 'not_executed'].includes(value))
    return 'text-n-ruby-11 bg-n-ruby-3';
  if (['delivered', 'read'].includes(value))
    return 'text-n-teal-11 bg-n-teal-3';
  if (value === 'unconfirmed') return 'text-n-amber-11 bg-n-amber-3';
  return 'text-n-slate-12 bg-n-alpha-2';
};
const formatDate = value =>
  value
    ? new Intl.DateTimeFormat(locale.value, {
        timeZone: props.timezone,
        dateStyle: 'short',
        timeStyle: 'short',
      }).format(new Date(value))
    : t('ARROYO.PANEL.NO_DATA');
const assigneeName = id =>
  props.agents.find(agent => agent.id === id)?.name ||
  t('ARROYO.PANEL.UNASSIGNED');
const conversationUrl = (item, message = false) => ({
  path: `/app/accounts/${route.params.accountId}/conversations/${item.purchase.conversation_id}`,
  query: message ? { messageId: item.message.id } : {},
});
const errorText = (error, fallback) =>
  error?.response?.data?.errors?.join(', ') ||
  error?.response?.data?.error ||
  fallback;
const closeDetail = () => {
  detailRequestId += 1;
  selected.value = null;
};
const localPurchaseDate = purchase =>
  formatInTimeZone(
    new Date(purchase.purchased_at),
    props.timezone,
    "yyyy-MM-dd'T'HH:mm"
  );
const fetchFollowUps = async () => {
  requestId += 1;
  const currentRequest = requestId;
  isLoading.value = true;
  loadError.value = '';
  try {
    const response = await PostSaleAPI.getFollowUps({
      ...props.params,
      stage: stage.value || undefined,
      status: status.value || summaryStatuses[summaryFilter.value],
      manual_status: manualOnly.value ? 'pending' : undefined,
      ...(page.value > 1 ? { page: page.value } : {}),
    });
    if (currentRequest === requestId) data.value = response.data;
  } catch (error) {
    if (currentRequest === requestId)
      loadError.value = errorText(
        error,
        t('ARROYO.PANEL.POST_SALE.LOAD_ERROR')
      );
  } finally {
    if (currentRequest === requestId) isLoading.value = false;
  }
};
const openDetail = async item => {
  detailRequestId += 1;
  const currentRequest = detailRequestId;
  selected.value = item;
  purchasedAt.value = localPurchaseDate(item.purchase);
  method.value = 'call';
  note.value = '';
  mutationError.value = '';
  detailError.value = '';
  purchaseFollowUps.value = [];
  detailLoading.value = true;
  try {
    const response = await PostSaleAPI.getFollowUps({
      purchase_reference: item.purchase.reference,
    });
    if (currentRequest === detailRequestId) {
      purchaseFollowUps.value = response.data.follow_ups;
      selected.value =
        response.data.follow_ups.find(followUp => followUp.id === item.id) ||
        item;
      purchasedAt.value = localPurchaseDate(selected.value.purchase);
    }
  } catch (error) {
    if (currentRequest === detailRequestId)
      detailError.value = errorText(
        error,
        t('ARROYO.PANEL.POST_SALE.LOAD_ERROR')
      );
  } finally {
    if (currentRequest === detailRequestId) detailLoading.value = false;
  }
};
const save = async action => {
  isSaving.value = true;
  mutationError.value = '';
  const item = selected.value;
  try {
    await action(item);
    await fetchFollowUps();
    await openDetail(item);
  } catch (error) {
    mutationError.value = errorText(
      error,
      t('ARROYO.PANEL.POST_SALE.SAVE_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};
const resolve = () =>
  save(item =>
    PostSaleAPI.resolve(item.id, {
      method: method.value,
      note: note.value.trim(),
    })
  );
const updatePurchase = () =>
  save(item =>
    PostSaleAPI.updatePurchase(item.purchase.reference, {
      purchased_at: zonedTimeToUtc(
        purchasedAt.value,
        props.timezone
      ).toISOString(),
    })
  );

watch(
  [() => props.params, status, summaryFilter, manualOnly, stage, page],
  (values, previous) => {
    if (
      page.value !== 1 &&
      (values[0] !== previous[0] ||
        values[1] !== previous[1] ||
        values[2] !== previous[2] ||
        values[3] !== previous[3] ||
        values[4] !== previous[4])
    ) {
      page.value = 1;
      return;
    }
    closeDetail();
    fetchFollowUps();
  },
  { immediate: true }
);
</script>

<template>
  <section class="flex flex-col gap-4" :aria-busy="isLoading">
    <div
      v-if="loadError"
      role="alert"
      class="flex items-center gap-3 text-n-ruby-11"
    >
      <span>{{ loadError }}</span>
      <Button
        :label="t('ARROYO.PANEL.POST_SALE.RETRY')"
        data-testid="retry"
        @click="fetchFollowUps"
      />
    </div>
    <div v-if="isLoading" class="flex justify-center py-10"><Spinner /></div>
    <template v-if="data && !loadError">
      <div class="flex items-start justify-between gap-4">
        <div
          class="flex flex-wrap items-center gap-2"
          :aria-label="t('ARROYO.PANEL.POST_SALE.QUICK_FILTERS')"
        >
          <button
            type="button"
            class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
            :class="{ 'bg-n-alpha-2': !summaryFilter && !status }"
            :aria-pressed="!summaryFilter && !status"
            @click="
              summaryFilter = '';
              status = '';
            "
          >
            {{ t('ARROYO.PANEL.POST_SALE.ALL_STATUSES') }}
          </button>
          <button
            v-for="summary in summaries"
            :key="summary.key"
            type="button"
            class="flex items-center gap-2 rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
            :class="{
              'bg-n-alpha-2 outline outline-1 outline-n-blue-9':
                summaryFilter === summary.key,
            }"
            :aria-pressed="summaryFilter === summary.key"
            :data-testid="`summary-${summary.key}`"
            @click="selectSummary(summary.key)"
          >
            <span>{{ summary.label }}</span>
            <span class="font-semibold tabular-nums">{{ summary.count }}</span>
          </button>
        </div>
        <div
          v-on-click-outside="() => (showAdvanced = false)"
          class="relative ml-auto shrink-0"
          @keydown.esc.stop.prevent="closeAdvanced"
        >
          <button
            ref="advancedTrigger"
            type="button"
            class="flex min-h-10 items-center gap-2 rounded text-sm text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
            :aria-expanded="showAdvanced"
            aria-controls="post-sale-advanced-filters"
            data-testid="advanced-status-filter"
            @click="showAdvanced = !showAdvanced"
          >
            <Icon
              :icon="
                showAdvanced
                  ? 'i-lucide-chevron-down'
                  : 'i-lucide-chevron-right'
              "
              class="size-4"
            />
            {{ t('ARROYO.PANEL.POST_SALE.ADVANCED_FILTERS') }}
          </button>
          <div
            v-show="showAdvanced"
            id="post-sale-advanced-filters"
            class="absolute right-0 top-full z-20 mt-2 w-max max-w-72 rounded-lg border border-n-weak bg-n-solid-2 p-3"
          >
            <label class="flex flex-col gap-2 text-sm text-n-slate-11">
              {{ t('ARROYO.PANEL.POST_SALE.STATUS_FILTER') }}
              <Select
                :model-value="status"
                :options="statusOptions"
                data-testid="status-filter"
                @update:model-value="selectStatus"
              />
            </label>
          </div>
        </div>
      </div>
      <div class="flex flex-wrap items-end gap-x-5 gap-y-3">
        <label class="flex flex-col gap-2 text-sm text-n-slate-11">
          {{ t('ARROYO.PANEL.POST_SALE.STAGE_FILTER') }}
          <Select
            v-model="stage"
            :options="stageOptions"
            data-testid="stage-filter"
          />
        </label>
        <button
          type="button"
          class="flex min-h-10 items-center gap-2 rounded text-sm text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          :aria-pressed="manualOnly"
          data-testid="summary-manual_pending"
          @click="manualOnly = !manualOnly"
        >
          <span
            aria-hidden="true"
            class="size-4 rounded border border-n-strong"
            :class="manualOnly ? 'bg-n-blue-9' : 'bg-n-surface-1'"
          />
          <span>{{ t('ARROYO.PANEL.POST_SALE.SUMMARY.MANUAL_PENDING') }}</span>
          <span class="font-semibold tabular-nums">{{ manualCount }}</span>
        </button>

        <button
          type="button"
          class="flex min-h-10 items-center gap-2 rounded text-sm text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          :aria-expanded="showHelp"
          aria-controls="post-sale-view-help"
          data-testid="view-help-toggle"
          @click="showHelp = !showHelp"
        >
          <Icon
            :icon="
              showHelp ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right'
            "
            class="size-4"
          />
          {{ t('ARROYO.PANEL.POST_SALE.VIEW_HELP') }}
        </button>
      </div>
      <div
        v-show="showHelp"
        id="post-sale-view-help"
        role="region"
        aria-labelledby="post-sale-guide-title"
        class="border-t border-n-weak pt-4"
      >
        <div
          class="flex max-w-2xl flex-col gap-2 text-sm text-n-slate-11"
          data-testid="status-explanation"
        >
          <h2
            id="post-sale-guide-title"
            class="m-0 text-sm font-medium text-n-slate-12"
          >
            {{ t('ARROYO.PANEL.POST_SALE.VIEW_HELP_TITLE') }}
          </h2>
          <p class="m-0">{{ filterExplanation }}</p>
          <p v-if="manualOnly" class="m-0">{{ summaryHelp.manual_pending }}</p>
          <p class="m-0">{{ t('ARROYO.PANEL.POST_SALE.COUNTS_HELP') }}</p>
        </div>
      </div>
      <p v-if="status" class="m-0 text-sm text-n-slate-11" role="status">
        {{
          t('ARROYO.PANEL.POST_SALE.SPECIFIC_STATUS', {
            status: statusLabel(status),
          })
        }}
      </p>
      <p
        v-if="!data.follow_ups.length"
        class="py-10 text-center text-n-slate-11"
      >
        {{ t('ARROYO.PANEL.POST_SALE.EMPTY') }}
        <span class="mt-2 block text-sm">{{
          t('ARROYO.PANEL.POST_SALE.EMPTY_HELP')
        }}</span>
      </p>
      <ul
        v-else
        class="m-0 list-none divide-y divide-n-weak rounded-xl border border-n-weak p-0"
      >
        <li
          v-for="item in data.follow_ups"
          :key="item.id"
          class="flex flex-col gap-4 p-4 lg:flex-row lg:items-start lg:justify-between"
        >
          <div class="flex min-w-0 flex-1 flex-col gap-2">
            <div class="flex flex-wrap items-center gap-2">
              <button
                :data-testid="`follow-up-${item.id}`"
                class="break-words text-left font-semibold text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
                @click="openDetail(item)"
              >
                {{
                  item.purchase.contact.name ||
                  item.purchase.contact.phone_number
                }}
              </button>
              <span class="text-label-small text-n-slate-11">{{
                labels.stages[item.stage]
              }}</span>
              <span
                class="rounded px-2 py-1 text-label-small font-medium"
                :class="statusClass(item.status)"
              >
                {{ visibleStatus(item.status) }}
              </span>
              <span
                v-if="item.manual_status"
                class="text-label-small"
                :class="
                  item.manual_status === 'pending'
                    ? 'text-n-amber-11'
                    : 'text-n-slate-11'
                "
              >
                {{ manualLabel(item.manual_status) }}
              </span>
            </div>
            <p class="m-0 break-words text-sm text-n-slate-12">
              {{ item.purchase.product || t('ARROYO.PANEL.NO_DATA') }}
            </p>
            <div
              class="flex flex-wrap gap-x-5 gap-y-1 text-label-small text-n-slate-11"
            >
              <span>{{
                t('ARROYO.PANEL.POST_SALE.FIELD_VALUE', {
                  label: t('ARROYO.PANEL.POST_SALE.COLUMNS.SELLER'),
                  value:
                    item.purchase.seller?.name || t('ARROYO.PANEL.UNASSIGNED'),
                })
              }}</span>
              <span>{{
                t('ARROYO.PANEL.POST_SALE.FIELD_VALUE', {
                  label: t('ARROYO.PANEL.POST_SALE.COLUMNS.SCHEDULED_AT'),
                  value: formatDate(item.scheduled_at),
                })
              }}</span>
              <span v-if="item.manual_status === 'pending'">{{
                t('ARROYO.PANEL.POST_SALE.FIELD_VALUE', {
                  label: t('ARROYO.PANEL.POST_SALE.COLUMNS.ASSIGNEE'),
                  value: assigneeName(item.alert_assignee_id),
                })
              }}</span>
            </div>
            <p
              v-if="item.error_message || item.error_code"
              class="m-0 break-words text-sm text-n-ruby-11"
            >
              {{ item.error_message || item.error_code }}
            </p>
            <p
              v-if="item.message?.content"
              class="m-0 line-clamp-2 break-words text-sm text-n-slate-11"
            >
              {{ item.message.content }}
            </p>
          </div>
          <div class="flex shrink-0 flex-wrap items-center gap-3">
            <Button
              slate
              faded
              sm
              :label="
                item.can_resolve && item.manual_status === 'pending'
                  ? t('ARROYO.PANEL.POST_SALE.RESOLVE')
                  : t('ARROYO.PANEL.POST_SALE.VIEW_DETAIL')
              "
              @click="openDetail(item)"
            />
            <router-link
              :to="conversationUrl(item)"
              :data-testid="`conversation-${item.id}`"
              class="rounded px-1 py-2 text-sm text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
            >
              {{ t('ARROYO.PANEL.POST_SALE.OPEN_CONVERSATION') }}
            </router-link>
          </div>
        </li>
      </ul>
      <p class="mb-0 text-label-small text-n-slate-11">
        {{
          t('ARROYO.PANEL.POST_SALE.LIMIT', {
            shown: data.follow_ups.length,
            total: data.meta?.total ?? data.follow_ups.length,
          })
        }}
      </p>
      <div
        v-if="page > 1 || data.meta?.next_page"
        class="flex justify-end gap-2"
      >
        <Button
          :label="t('ARROYO.PANEL.POST_SALE.PREVIOUS_PAGE')"
          :disabled="page === 1"
          slate
          faded
          @click="page -= 1"
        />
        <Button
          v-if="data.meta?.next_page"
          :label="t('ARROYO.PANEL.POST_SALE.NEXT_PAGE')"
          slate
          faded
          data-testid="next-page"
          @click="page = data.meta.next_page"
        />
      </div>
    </template>

    <aside
      v-if="selected"
      class="fixed inset-y-0 right-0 z-50 flex flex-col w-full max-w-xl shadow-lg bg-n-surface-2 border-l border-n-weak"
      :aria-label="t('ARROYO.PANEL.POST_SALE.DETAIL')"
    >
      <header
        class="flex items-start justify-between gap-3 p-5 border-b border-n-weak"
      >
        <div class="min-w-0">
          <h3 class="text-heading-2 text-n-slate-12">
            {{
              selected.purchase.contact.name ||
              selected.purchase.contact.phone_number
            }}
          </h3>
          <p class="mb-0 text-n-slate-11">{{ selected.purchase.product }}</p>
        </div>
        <Button
          icon="i-lucide-x"
          slate
          ghost
          sm
          :aria-label="t('ARROYO.PANEL.DRAWER.CLOSE')"
          :disabled="isSaving"
          @click="closeDetail"
        />
      </header>
      <div class="flex flex-col gap-5 overflow-y-auto p-5">
        <router-link
          :to="conversationUrl(selected)"
          class="text-n-blue-11 hover:underline"
        >
          {{ t('ARROYO.PANEL.POST_SALE.OPEN_CONVERSATION') }}
        </router-link>
        <dl class="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
          <dt class="text-n-slate-11">
            {{ t('ARROYO.PANEL.POST_SALE.COLUMNS.SELLER') }}
          </dt>
          <dd>
            {{ selected.purchase.seller?.name || t('ARROYO.PANEL.UNASSIGNED') }}
          </dd>
          <dt class="text-n-slate-11">
            {{ t('ARROYO.PANEL.POST_SALE.COLUMNS.STATUS') }}
          </dt>
          <dd>
            {{ statusLabel(selected.status) }}
            <p
              class="mb-0 mt-1 text-xs text-n-slate-11"
              :data-testid="`follow-up-advice-${selected.id}`"
            >
              {{ nextAction(selected) }}
            </p>
          </dd>
          <dt class="text-n-slate-11">
            {{ t('ARROYO.PANEL.POST_SALE.COLUMNS.MANUAL') }}
          </dt>
          <dd>{{ manualLabel(selected.manual_status) }}</dd>
          <dt class="text-n-slate-11">
            {{ t('ARROYO.PANEL.POST_SALE.COLUMNS.ASSIGNEE') }}
          </dt>
          <dd>{{ assigneeName(selected.alert_assignee_id) }}</dd>
          <template v-for="(label, field) in dateLabels" :key="field">
            <dt class="text-n-slate-11">
              {{ label }}
            </dt>
            <dd>{{ formatDate(selected[field]) }}</dd>
          </template>
        </dl>
        <p
          v-if="selected.error_message || selected.error_code"
          class="mb-0 text-sm text-n-ruby-11"
        >
          <span>{{ selected.error_code }}</span>
          <span>{{ selected.error_message }}</span>
        </p>
        <form
          v-if="selected.can_resolve && selected.manual_status === 'pending'"
          class="flex flex-col gap-3 border-t border-n-weak pt-4"
          @submit.prevent="resolve"
        >
          <h4 class="text-heading-3 text-n-slate-12">
            {{ t('ARROYO.PANEL.POST_SALE.RESOLVE') }}
          </h4>
          <p class="mb-0 text-label-small text-n-slate-11">
            {{ t('ARROYO.PANEL.POST_SALE.RESOLVE_HELP') }}
          </p>
          <label class="flex flex-col gap-1 text-sm text-n-slate-11">
            {{ t('ARROYO.PANEL.POST_SALE.METHOD') }}
            <Select
              v-model="method"
              :options="methodOptions"
              :disabled="isSaving"
            />
          </label>
          <TextArea
            id="post-sale-resolution-note"
            v-model="note"
            :label="t('ARROYO.PANEL.POST_SALE.NOTE')"
            :max-length="2000"
            show-character-count
            :disabled="isSaving"
            data-testid="resolution-note"
          />
          <Button
            type="submit"
            :label="t('ARROYO.PANEL.POST_SALE.RESOLVE')"
            :is-loading="isSaving"
            :disabled="!note.trim() || isSaving"
            data-testid="resolve-submit"
          />
        </form>
        <div
          v-else-if="selected.resolution_method || selected.resolution_note"
          class="flex flex-col gap-2"
        >
          <h4 class="text-heading-3 text-n-slate-12">
            {{ t('ARROYO.PANEL.POST_SALE.RESOLUTION') }}
          </h4>
          <span v-if="selected.resolution_method">{{
            labels.methods[selected.resolution_method]
          }}</span>
          <p class="mb-0 whitespace-pre-wrap text-sm text-n-slate-11">
            {{ selected.resolution_note }}
          </p>
        </div>
        <div class="flex flex-col gap-2">
          <h4 class="text-heading-3 text-n-slate-12">
            {{ t('ARROYO.PANEL.POST_SALE.PURCHASE_DATE') }}
          </h4>
          <template v-if="selected.purchase.can_edit_purchase">
            <Input
              v-model="purchasedAt"
              type="datetime-local"
              :label="t('ARROYO.PANEL.POST_SALE.PURCHASE_DATE')"
              :disabled="isSaving || detailLoading"
              data-testid="purchase-date"
            />
            <p class="mb-0 text-label-small text-n-slate-11">
              {{ t('ARROYO.PANEL.POST_SALE.DATE_HELP', { timezone }) }}
            </p>
            <Button
              :label="t('ARROYO.PANEL.POST_SALE.SAVE_DATE')"
              :disabled="!purchasedAt || isSaving || detailLoading"
              data-testid="purchase-date-save"
              @click="updatePurchase"
            />
          </template>
          <p v-else class="mb-0 text-sm text-n-slate-11">
            {{ formatDate(selected.purchase.purchased_at) }}
          </p>
        </div>
        <div class="flex flex-col gap-2">
          <h4 class="text-heading-3 text-n-slate-12">
            {{ t('ARROYO.PANEL.POST_SALE.PURCHASE_STAGES') }}
          </h4>
          <Spinner v-if="detailLoading" />
          <p v-else-if="detailError" role="alert" class="text-n-ruby-11">
            {{ detailError }}
          </p>
          <button
            v-for="item in purchaseFollowUps"
            :key="item.id"
            :disabled="isSaving"
            class="flex flex-wrap items-center justify-between gap-2 p-3 rounded-lg border border-n-weak text-left hover:bg-n-alpha-2"
            :class="{ 'bg-n-alpha-2': selected.id === item.id }"
            @click="openDetail(item)"
          >
            <span>{{ labels.stages[item.stage] }}</span>
            <span>{{ statusLabel(item.status) }}</span>
            <span class="text-label-small text-n-slate-11">{{
              formatDate(item.scheduled_at)
            }}</span>
          </button>
        </div>
        <div class="flex flex-col gap-2">
          <h4 class="text-heading-3 text-n-slate-12">
            {{ t('ARROYO.PANEL.POST_SALE.MESSAGE') }}
          </h4>
          <p
            v-if="
              selected.template_name || selected.message?.template_params?.name
            "
            class="mb-0 text-label-small text-n-slate-11"
          >
            <span>{{ t('ARROYO.PANEL.POST_SALE.TEMPLATE') }}</span>
            <span>{{
              selected.template_name || selected.message.template_params.name
            }}</span>
          </p>
          <template v-if="selected.message">
            <p
              class="mb-0 whitespace-pre-wrap break-words text-sm text-n-slate-12"
            >
              {{ selected.message.content }}
            </p>
            <p class="mb-0 break-all text-label-small text-n-slate-11">
              {{
                t('ARROYO.PANEL.POST_SALE.PROVIDER_ID', {
                  id: selected.message.source_id || t('ARROYO.PANEL.NO_DATA'),
                })
              }}
            </p>
            <router-link
              :to="conversationUrl(selected, true)"
              class="text-n-blue-11 hover:underline"
              data-testid="message-link"
            >
              {{ t('ARROYO.PANEL.POST_SALE.OPEN_MESSAGE') }}
            </router-link>
          </template>
          <p v-else class="mb-0 text-sm text-n-slate-11">
            {{ t('ARROYO.PANEL.POST_SALE.NO_MESSAGE') }}
          </p>
        </div>
        <p v-if="mutationError" role="alert" class="text-n-ruby-11">
          {{ mutationError }}
        </p>
      </div>
    </aside>
  </section>
</template>

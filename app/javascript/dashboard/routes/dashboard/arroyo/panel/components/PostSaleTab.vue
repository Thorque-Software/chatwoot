<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { formatInTimeZone, zonedTimeToUtc } from 'date-fns-tz';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import PostSaleAPI from '../../api/postSale';
import { POST_SALE_STATUSES } from '../constants';

const props = defineProps({
  params: { type: Object, required: true },
  timezone: { type: String, required: true },
  agents: { type: Array, default: () => [] },
});

const { t, locale } = useI18n();
const route = useRoute();
const status = ref('');
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
const columnLabels = computed(() => [
  t('ARROYO.PANEL.POST_SALE.COLUMNS.CUSTOMER'),
  t('ARROYO.PANEL.POST_SALE.COLUMNS.PRODUCT'),
  t('ARROYO.PANEL.POST_SALE.COLUMNS.SELLER'),
  t('ARROYO.PANEL.POST_SALE.COLUMNS.STAGE'),
  t('ARROYO.PANEL.POST_SALE.COLUMNS.SCHEDULED_AT'),
  t('ARROYO.PANEL.POST_SALE.COLUMNS.ATTEMPTED_AT'),
  t('ARROYO.PANEL.POST_SALE.COLUMNS.STATUS'),
  t('ARROYO.PANEL.POST_SALE.COLUMNS.REASON'),
  t('ARROYO.PANEL.POST_SALE.COLUMNS.ASSIGNEE'),
  t('ARROYO.PANEL.POST_SALE.COLUMNS.MANUAL'),
]);
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
      count: (totals.failed || 0) + (totals.not_executed || 0),
    },
    {
      key: 'unconfirmed',
      label: t('ARROYO.PANEL.POST_SALE.SUMMARY.UNCONFIRMED'),
      count: totals.unconfirmed || 0,
    },
    {
      key: 'manual_pending',
      label: t('ARROYO.PANEL.POST_SALE.SUMMARY.MANUAL_PENDING'),
      count: totals.manual_pending || 0,
    },
  ];
});
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
      status: status.value || undefined,
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
  [() => props.params, status, page],
  (values, previous) => {
    if (
      page.value !== 1 &&
      (values[0] !== previous[0] || values[1] !== previous[1])
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
  <section class="flex flex-col gap-4">
    <p class="mb-0 text-body-main text-n-slate-11">
      {{ t('ARROYO.PANEL.POST_SALE.DESCRIPTION') }}
    </p>
    <label class="flex flex-col gap-1 text-label-small text-n-slate-11">
      {{ t('ARROYO.PANEL.POST_SALE.STATUS_FILTER') }}
      <Select
        v-model="status"
        :options="statusOptions"
        data-testid="status-filter"
      />
    </label>
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
    <template v-else-if="data && !loadError">
      <div class="grid grid-cols-2 gap-3 lg:grid-cols-6">
        <div
          v-for="summary in summaries"
          :key="summary.key"
          class="flex flex-col gap-1 p-4 rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
        >
          <span class="text-label-small text-n-slate-11">{{
            summary.label
          }}</span>
          <span class="text-heading-1 text-n-slate-12">{{
            summary.count
          }}</span>
        </div>
      </div>
      <p
        v-if="!data.follow_ups.length"
        class="py-10 text-center text-n-slate-11"
      >
        {{ t('ARROYO.PANEL.POST_SALE.EMPTY') }}
      </p>
      <div v-else class="overflow-x-auto rounded-xl border border-n-weak">
        <table class="w-full text-left text-sm">
          <thead class="bg-n-solid-2 text-n-slate-11">
            <tr>
              <th
                v-for="column in columnLabels"
                :key="column"
                class="p-3 whitespace-nowrap"
              >
                {{ column }}
              </th>
            </tr>
          </thead>
          <tbody class="text-n-slate-12">
            <tr
              v-for="item in data.follow_ups"
              :key="item.id"
              class="border-t border-n-weak"
            >
              <td class="p-3">
                <button
                  :data-testid="`follow-up-${item.id}`"
                  class="text-left font-medium text-n-blue-11 hover:underline"
                  @click="openDetail(item)"
                >
                  {{
                    item.purchase.contact.name ||
                    item.purchase.contact.phone_number
                  }}
                </button>
              </td>
              <td class="p-3">
                {{ item.purchase.product || t('ARROYO.PANEL.NO_DATA') }}
              </td>
              <td class="p-3 whitespace-nowrap">
                {{ item.purchase.seller?.name || t('ARROYO.PANEL.UNASSIGNED') }}
              </td>
              <td class="p-3 whitespace-nowrap">
                {{ labels.stages[item.stage] }}
              </td>
              <td class="p-3 whitespace-nowrap">
                {{ formatDate(item.scheduled_at) }}
              </td>
              <td class="p-3 whitespace-nowrap">
                {{ formatDate(item.attempted_at) }}
              </td>
              <td class="p-3 whitespace-nowrap">
                {{ statusLabel(item.status) }}
              </td>
              <td class="p-3">
                <span class="block min-w-40">{{
                  item.error_message ||
                  item.error_code ||
                  t('ARROYO.PANEL.NO_DATA')
                }}</span>
              </td>
              <td class="p-3 whitespace-nowrap">
                {{ assigneeName(item.alert_assignee_id) }}
              </td>
              <td class="p-3 whitespace-nowrap">
                {{ manualLabel(item.manual_status) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
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
          <dd>{{ statusLabel(selected.status) }}</dd>
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
        <p v-if="mutationError" role="alert" class="text-n-ruby-11">
          {{ mutationError }}
        </p>
      </div>
    </aside>
  </section>
</template>

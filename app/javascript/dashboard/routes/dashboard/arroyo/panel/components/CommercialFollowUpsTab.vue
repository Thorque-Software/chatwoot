<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { addDays, format, parseISO } from 'date-fns';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CommercialFollowUpsAPI from '../../api/commercialFollowUps';
import { FOLLOW_UP_STATUSES } from '../constants';
import { todayIn } from '../helpers';

const props = defineProps({
  timezone: { type: String, required: true },
});

const { t, locale } = useI18n();
const route = useRoute();
const data = ref(null);
const isLoading = ref(false);
const isBusy = ref(false);
const loadError = ref('');
const statusFilter = ref('');
const selectedIds = ref([]);
const action = ref(null);
const bulkConfirm = ref(false);
const rescheduleDate = ref('');

const statusLabels = computed(() => ({
  scheduled: t('ARROYO.PANEL.FOLLOW_UPS.STATUSES.SCHEDULED'),
  awaiting_finish: t('ARROYO.PANEL.FOLLOW_UPS.STATUSES.AWAITING_FINISH'),
  finished: t('ARROYO.PANEL.FOLLOW_UPS.STATUSES.FINISHED'),
  paused: t('ARROYO.PANEL.FOLLOW_UPS.STATUSES.PAUSED'),
  unenrolled: t('ARROYO.PANEL.FOLLOW_UPS.STATUSES.UNENROLLED'),
}));
const statusHelp = computed(() => ({
  all: t('ARROYO.PANEL.FOLLOW_UPS.STATUS_HELP.ALL'),
  scheduled: t('ARROYO.PANEL.FOLLOW_UPS.STATUS_HELP.SCHEDULED'),
  awaiting_finish: t('ARROYO.PANEL.FOLLOW_UPS.STATUS_HELP.AWAITING_FINISH'),
  finished: t('ARROYO.PANEL.FOLLOW_UPS.STATUS_HELP.FINISHED'),
  paused: t('ARROYO.PANEL.FOLLOW_UPS.STATUS_HELP.PAUSED'),
  unenrolled: t('ARROYO.PANEL.FOLLOW_UPS.STATUS_HELP.UNENROLLED'),
}));
const stepStatusLabels = computed(() => ({
  pending: t('ARROYO.PANEL.FOLLOW_UPS.STEP_STATUSES.PENDING'),
  scheduled: t('ARROYO.PANEL.FOLLOW_UPS.STEP_STATUSES.SCHEDULED'),
  sent: t('ARROYO.PANEL.FOLLOW_UPS.STEP_STATUSES.SENT'),
  delivered: t('ARROYO.PANEL.FOLLOW_UPS.STEP_STATUSES.DELIVERED'),
  read: t('ARROYO.PANEL.FOLLOW_UPS.STEP_STATUSES.READ'),
  failed: t('ARROYO.PANEL.FOLLOW_UPS.STEP_STATUSES.FAILED'),
}));
const blockedLabels = computed(() => ({
  no_seller: t('ARROYO.PANEL.FOLLOW_UPS.BLOCKED.NO_SELLER'),
  channel: t('ARROYO.PANEL.FOLLOW_UPS.BLOCKED.CHANNEL'),
  contact_blocked: t('ARROYO.PANEL.FOLLOW_UPS.BLOCKED.CONTACT_BLOCKED'),
  excluded_label: t('ARROYO.PANEL.FOLLOW_UPS.BLOCKED.EXCLUDED_LABEL'),
  terminal: t('ARROYO.PANEL.FOLLOW_UPS.BLOCKED.TERMINAL'),
  not_enrolled: t('ARROYO.PANEL.FOLLOW_UPS.BLOCKED.NOT_ENROLLED'),
}));

const today = computed(() => todayIn(props.timezone));
const minDate = computed(() =>
  format(addDays(parseISO(today.value), 1), 'yyyy-MM-dd')
);
const totals = computed(() => data.value?.totals || {});
const agenda = computed(() => data.value?.agenda || []);
const rows = computed(() =>
  (data.value?.follow_ups || []).filter(
    item => !statusFilter.value || item.status === statusFilter.value
  )
);
const enrollableRows = computed(() =>
  rows.value.filter(item => item.can_enroll)
);
const allSelected = computed(
  () =>
    enrollableRows.value.length > 0 &&
    enrollableRows.value.every(item =>
      selectedIds.value.includes(item.conversation_id)
    )
);
const filterExplanation = computed(
  () => statusHelp.value[statusFilter.value || 'all']
);

const formatDateTime = value =>
  value
    ? new Intl.DateTimeFormat(locale.value, {
        timeZone: props.timezone,
        dateStyle: 'short',
        timeStyle: 'short',
      }).format(new Date(value))
    : t('ARROYO.PANEL.NO_DATA');
const formatAgendaDate = value =>
  new Intl.DateTimeFormat(locale.value, {
    timeZone: 'UTC',
    weekday: 'short',
    day: 'numeric',
    month: 'short',
  }).format(new Date(`${value}T12:00:00Z`));
const contactName = item => item.contact_name || item.contact_phone;
const conversationUrl = item =>
  `/app/accounts/${route.params.accountId}/conversations/${item.conversation_id}`;
const statusClass = value => {
  if (value === 'failed') return 'text-n-ruby-11 bg-n-ruby-3';
  if (['delivered', 'read'].includes(value))
    return 'text-n-teal-11 bg-n-teal-3';
  if (['scheduled', 'awaiting_finish'].includes(value))
    return 'text-n-blue-11 bg-n-blue-3';
  if (value === 'unenrolled') return 'text-n-amber-11 bg-n-amber-3';
  return 'text-n-slate-12 bg-n-alpha-2';
};
const errorText = (error, fallback) =>
  error?.response?.data?.errors?.join(', ') ||
  error?.response?.data?.error ||
  fallback;

const fetchFollowUps = async () => {
  isLoading.value = true;
  loadError.value = '';
  try {
    const response = await CommercialFollowUpsAPI.getAll();
    data.value = response.data;
    const enrollable = response.data.follow_ups
      .filter(item => item.can_enroll)
      .map(item => item.conversation_id);
    selectedIds.value = selectedIds.value.filter(id => enrollable.includes(id));
  } catch (error) {
    loadError.value = errorText(error, t('ARROYO.PANEL.FOLLOW_UPS.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const perform = async (request, message) => {
  isBusy.value = true;
  try {
    const response = await request();
    useAlert(message(response.data));
    action.value = null;
    bulkConfirm.value = false;
    await fetchFollowUps();
  } catch (error) {
    useAlert(errorText(error, t('ARROYO.PANEL.FOLLOW_UPS.ACTION_ERROR')));
  } finally {
    isBusy.value = false;
  }
};

const identity = item => ({
  conversation_id: item.conversation_id,
  opportunity_reference: item.opportunity_reference,
});
const openAction = (type, item) => {
  bulkConfirm.value = false;
  rescheduleDate.value = '';
  action.value = { type, id: item.conversation_id };
};
const sendNow = item =>
  perform(
    () => CommercialFollowUpsAPI.sendNow(identity(item)),
    () => t('ARROYO.PANEL.FOLLOW_UPS.SEND_SUCCESS')
  );
const reschedule = item =>
  perform(
    () =>
      CommercialFollowUpsAPI.reschedule({
        ...identity(item),
        date: rescheduleDate.value,
      }),
    () => t('ARROYO.PANEL.FOLLOW_UPS.RESCHEDULE_SUCCESS')
  );
const enroll = conversationIds =>
  perform(
    () => CommercialFollowUpsAPI.enroll({ conversation_ids: conversationIds }),
    result => {
      selectedIds.value = [];
      return t('ARROYO.PANEL.FOLLOW_UPS.ENROLL_RESULT', {
        enrolled: result.enrolled.length,
        skipped: result.skipped.length,
      });
    }
  );

const toggleRow = id => {
  selectedIds.value = selectedIds.value.includes(id)
    ? selectedIds.value.filter(selected => selected !== id)
    : [...selectedIds.value, id];
};
const toggleAll = () => {
  const ids = enrollableRows.value.map(item => item.conversation_id);
  selectedIds.value = allSelected.value
    ? selectedIds.value.filter(id => !ids.includes(id))
    : [...new Set([...selectedIds.value, ...ids])];
};
const openBulkConfirm = () => {
  action.value = null;
  bulkConfirm.value = true;
};
const selectStatus = value => {
  statusFilter.value = statusFilter.value === value ? '' : value;
};

onMounted(fetchFollowUps);
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
        :label="t('ARROYO.PANEL.FOLLOW_UPS.RETRY')"
        data-testid="retry"
        @click="fetchFollowUps"
      />
    </div>
    <div v-if="isLoading && !data" class="flex justify-center py-10">
      <Spinner />
    </div>
    <template v-if="data && !loadError">
      <div
        class="flex flex-wrap items-center gap-2"
        :aria-label="t('ARROYO.PANEL.FOLLOW_UPS.QUICK_FILTERS')"
      >
        <button
          type="button"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          :class="{ 'bg-n-alpha-2': !statusFilter }"
          :aria-pressed="!statusFilter"
          data-testid="filter-all"
          @click="statusFilter = ''"
        >
          {{ t('ARROYO.PANEL.FOLLOW_UPS.ALL_STATUSES') }}
        </button>
        <button
          v-for="status in FOLLOW_UP_STATUSES"
          :key="status"
          type="button"
          class="flex items-center gap-2 rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          :class="{
            'bg-n-alpha-2 outline outline-1 outline-n-blue-9':
              statusFilter === status,
          }"
          :aria-pressed="statusFilter === status"
          :data-testid="`filter-${status}`"
          @click="selectStatus(status)"
        >
          <span>{{ statusLabels[status] }}</span>
          <span class="font-semibold tabular-nums">{{
            totals[status] || 0
          }}</span>
        </button>
      </div>
      <p class="m-0 text-sm text-n-slate-11" role="status">
        {{ filterExplanation }}
      </p>

      <section
        class="flex flex-col gap-2 rounded-xl bg-n-solid-2 p-4 outline outline-1 outline-n-container"
        data-testid="agenda"
      >
        <h3 class="text-heading-3 text-n-slate-12">
          {{ t('ARROYO.PANEL.FOLLOW_UPS.AGENDA.TITLE') }}
        </h3>
        <p class="mb-0 text-body-main text-n-slate-11">
          {{ t('ARROYO.PANEL.FOLLOW_UPS.AGENDA.HELP') }}
        </p>
        <p v-if="!agenda.length" class="mb-0 text-sm text-n-slate-11">
          {{ t('ARROYO.PANEL.FOLLOW_UPS.AGENDA.EMPTY') }}
        </p>
        <ul v-else class="m-0 flex list-none flex-wrap gap-2 p-0">
          <li
            v-for="day in agenda"
            :key="day.date"
            class="flex flex-col rounded-lg border px-3 py-2 text-sm"
            :class="
              day.date === today
                ? 'border-n-blue-9 bg-n-blue-3 text-n-blue-11'
                : 'border-n-weak text-n-slate-12'
            "
            :data-testid="`agenda-${day.date}`"
          >
            <span class="text-label-small">
              {{ formatAgendaDate(day.date) }}
              <template v-if="day.date === today">
                · {{ t('ARROYO.PANEL.FOLLOW_UPS.AGENDA.TODAY') }}
              </template>
            </span>
            <span class="font-semibold tabular-nums">
              {{
                t('ARROYO.PANEL.FOLLOW_UPS.AGENDA.COUNT', { count: day.count })
              }}
            </span>
          </li>
        </ul>
      </section>

      <div
        v-if="enrollableRows.length"
        class="flex flex-wrap items-center gap-3"
      >
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <input
            type="checkbox"
            class="size-4"
            :checked="allSelected"
            data-testid="select-all"
            @change="toggleAll"
          />
          {{ t('ARROYO.PANEL.FOLLOW_UPS.SELECT_ALL') }}
        </label>
        <Button
          v-if="selectedIds.length"
          :label="
            t('ARROYO.PANEL.FOLLOW_UPS.ACTIONS.ENROLL_SELECTED', {
              count: selectedIds.length,
            })
          "
          sm
          :disabled="isBusy"
          data-testid="enroll-selected"
          @click="openBulkConfirm"
        />
      </div>
      <div
        v-if="bulkConfirm"
        class="flex flex-col gap-3 rounded-xl border border-n-weak p-4"
        data-testid="bulk-confirm"
      >
        <p class="mb-0 text-body-main text-n-slate-11">
          {{
            t('ARROYO.PANEL.FOLLOW_UPS.CONFIRM_ENROLL_SELECTED', {
              count: selectedIds.length,
            })
          }}
        </p>
        <div class="flex flex-wrap gap-2">
          <Button
            :label="t('ARROYO.PANEL.FOLLOW_UPS.ACTIONS.CONFIRM')"
            sm
            :disabled="isBusy"
            data-testid="confirm-enroll-selected"
            @click="enroll(selectedIds)"
          />
          <Button
            :label="t('ARROYO.PANEL.FOLLOW_UPS.ACTIONS.CANCEL')"
            slate
            ghost
            sm
            :disabled="isBusy"
            @click="bulkConfirm = false"
          />
        </div>
      </div>

      <p v-if="!rows.length" class="py-10 text-center text-n-slate-11">
        {{
          statusFilter
            ? t('ARROYO.PANEL.FOLLOW_UPS.EMPTY_FILTER')
            : t('ARROYO.PANEL.FOLLOW_UPS.EMPTY')
        }}
      </p>
      <ul
        v-else
        class="m-0 list-none divide-y divide-n-weak rounded-xl border border-n-weak p-0"
      >
        <li
          v-for="item in rows"
          :key="item.conversation_id"
          class="flex flex-col gap-3 p-4"
          :data-testid="`row-${item.conversation_id}`"
        >
          <div
            class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between"
          >
            <div class="flex min-w-0 flex-1 gap-3">
              <input
                v-if="item.can_enroll"
                type="checkbox"
                class="mt-1 size-4 shrink-0"
                :checked="selectedIds.includes(item.conversation_id)"
                :aria-label="
                  t('ARROYO.PANEL.FOLLOW_UPS.SELECT_ROW', {
                    name: contactName(item),
                  })
                "
                :data-testid="`select-${item.conversation_id}`"
                @change="toggleRow(item.conversation_id)"
              />
              <div class="flex min-w-0 flex-1 flex-col gap-2">
                <div class="flex flex-wrap items-center gap-2">
                  <router-link
                    :to="conversationUrl(item)"
                    :data-testid="`conversation-${item.conversation_id}`"
                    class="break-words font-semibold text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
                  >
                    {{ contactName(item) }}
                  </router-link>
                  <span class="text-label-small text-n-slate-11">
                    {{
                      t('ARROYO.PANEL.CONVERSATION_ID', {
                        id: item.conversation_id,
                      })
                    }}
                  </span>
                  <span
                    class="rounded px-2 py-1 text-label-small font-medium"
                    :class="statusClass(item.status)"
                    :data-testid="`status-${item.conversation_id}`"
                  >
                    {{ statusLabels[item.status] }}
                  </span>
                  <span
                    v-if="item.due_today"
                    class="rounded px-2 py-1 text-label-small font-medium text-n-blue-11 bg-n-blue-3"
                  >
                    {{ t('ARROYO.PANEL.FOLLOW_UPS.DUE_TODAY') }}
                  </span>
                </div>
                <div
                  class="flex flex-wrap gap-x-5 gap-y-1 text-label-small text-n-slate-11"
                >
                  <span v-if="item.contact_name && item.contact_phone">
                    {{ item.contact_phone }}
                  </span>
                  <span>
                    {{
                      t('ARROYO.PANEL.FOLLOW_UPS.FIELD_VALUE', {
                        label: t('ARROYO.PANEL.FOLLOW_UPS.FIELDS.SELLER'),
                        value:
                          item.assignee?.name || t('ARROYO.PANEL.UNASSIGNED'),
                      })
                    }}
                  </span>
                  <span v-if="item.advisor_alias">
                    {{
                      t('ARROYO.PANEL.FOLLOW_UPS.FIELD_VALUE', {
                        label: t('ARROYO.PANEL.FOLLOW_UPS.FIELDS.SIGNS_AS'),
                        value: item.advisor_alias,
                      })
                    }}
                  </span>
                  <span v-if="item.next_at">
                    {{
                      t('ARROYO.PANEL.FOLLOW_UPS.NEXT_SEND', {
                        step: item.next_step,
                        date: formatDateTime(item.next_at),
                      })
                    }}
                  </span>
                  <span v-if="item.enrolled_at">
                    {{
                      t('ARROYO.PANEL.FOLLOW_UPS.FIELD_VALUE', {
                        label: t('ARROYO.PANEL.FOLLOW_UPS.FIELDS.ENROLLED_AT'),
                        value: formatDateTime(item.enrolled_at),
                      })
                    }}
                  </span>
                  <span v-if="item.finished_at">
                    {{
                      t('ARROYO.PANEL.FOLLOW_UPS.FIELD_VALUE', {
                        label: t('ARROYO.PANEL.FOLLOW_UPS.FIELDS.FINISHED_AT'),
                        value: formatDateTime(item.finished_at),
                      })
                    }}
                  </span>
                </div>
                <p
                  v-if="item.blocked_reason"
                  class="m-0 text-sm text-n-amber-11"
                  :data-testid="`blocked-${item.conversation_id}`"
                >
                  {{ blockedLabels[item.blocked_reason] }}
                </p>
                <ol
                  class="m-0 grid list-none gap-2 p-0 sm:grid-cols-3"
                  :data-testid="`steps-${item.conversation_id}`"
                >
                  <li
                    v-for="step in item.steps"
                    :key="step.step"
                    class="flex flex-col gap-1 rounded-lg border border-n-weak p-2 text-sm"
                    :data-testid="`step-${item.conversation_id}-${step.step}`"
                  >
                    <span class="text-label-small text-n-slate-11">
                      {{
                        t('ARROYO.PANEL.FOLLOW_UPS.STEP', { step: step.step })
                      }}
                    </span>
                    <span
                      class="w-fit rounded px-2 py-0.5 text-label-small font-medium"
                      :class="statusClass(step.status)"
                    >
                      {{ stepStatusLabels[step.status] }}
                    </span>
                    <span
                      v-if="step.sent_at || step.scheduled_for"
                      class="text-label-small text-n-slate-11"
                    >
                      {{ formatDateTime(step.sent_at || step.scheduled_for) }}
                    </span>
                  </li>
                </ol>
              </div>
            </div>
            <div class="flex shrink-0 flex-wrap items-center gap-3">
              <Button
                v-if="item.can_send_now"
                :label="t('ARROYO.PANEL.FOLLOW_UPS.ACTIONS.SEND_NOW')"
                slate
                faded
                sm
                :disabled="isBusy"
                :data-testid="`send-now-${item.conversation_id}`"
                @click="openAction('send', item)"
              />
              <Button
                v-if="item.can_reschedule"
                :label="t('ARROYO.PANEL.FOLLOW_UPS.ACTIONS.RESCHEDULE')"
                slate
                faded
                sm
                :disabled="isBusy"
                :data-testid="`reschedule-${item.conversation_id}`"
                @click="openAction('reschedule', item)"
              />
              <Button
                v-if="item.can_enroll"
                :label="t('ARROYO.PANEL.FOLLOW_UPS.ACTIONS.ENROLL')"
                slate
                faded
                sm
                :disabled="isBusy"
                :data-testid="`enroll-${item.conversation_id}`"
                @click="openAction('enroll', item)"
              />
            </div>
          </div>

          <div
            v-if="action?.id === item.conversation_id"
            class="flex flex-col gap-3 rounded-lg bg-n-solid-2 p-3"
            :data-testid="`action-${item.conversation_id}`"
          >
            <template v-if="action.type === 'send'">
              <p class="mb-0 text-body-main text-n-slate-11">
                {{
                  t('ARROYO.PANEL.FOLLOW_UPS.CONFIRM_SEND', {
                    name: contactName(item),
                    step: item.next_step,
                  })
                }}
              </p>
              <div class="flex flex-wrap gap-2">
                <Button
                  :label="t('ARROYO.PANEL.FOLLOW_UPS.ACTIONS.CONFIRM')"
                  sm
                  :disabled="isBusy"
                  :data-testid="`confirm-send-${item.conversation_id}`"
                  @click="sendNow(item)"
                />
                <Button
                  :label="t('ARROYO.PANEL.FOLLOW_UPS.ACTIONS.CANCEL')"
                  slate
                  ghost
                  sm
                  :disabled="isBusy"
                  @click="action = null"
                />
              </div>
            </template>
            <template v-else-if="action.type === 'reschedule'">
              <Input
                v-model="rescheduleDate"
                type="date"
                :min="minDate"
                :label="t('ARROYO.PANEL.FOLLOW_UPS.NEW_DATE')"
                :disabled="isBusy"
                :data-testid="`reschedule-date-${item.conversation_id}`"
              />
              <p class="mb-0 text-label-small text-n-slate-11">
                {{
                  t('ARROYO.PANEL.FOLLOW_UPS.RESCHEDULE_HELP', {
                    timezone: props.timezone,
                  })
                }}
              </p>
              <div class="flex flex-wrap gap-2">
                <Button
                  :label="t('ARROYO.PANEL.FOLLOW_UPS.ACTIONS.SAVE_DATE')"
                  sm
                  :disabled="
                    isBusy || !rescheduleDate || rescheduleDate < minDate
                  "
                  :data-testid="`confirm-reschedule-${item.conversation_id}`"
                  @click="reschedule(item)"
                />
                <Button
                  :label="t('ARROYO.PANEL.FOLLOW_UPS.ACTIONS.CANCEL')"
                  slate
                  ghost
                  sm
                  :disabled="isBusy"
                  @click="action = null"
                />
              </div>
            </template>
            <template v-else>
              <p class="mb-0 text-body-main text-n-slate-11">
                {{
                  t('ARROYO.PANEL.FOLLOW_UPS.CONFIRM_ENROLL', {
                    name: contactName(item),
                  })
                }}
              </p>
              <div class="flex flex-wrap gap-2">
                <Button
                  :label="t('ARROYO.PANEL.FOLLOW_UPS.ACTIONS.CONFIRM')"
                  sm
                  :disabled="isBusy"
                  :data-testid="`confirm-enroll-${item.conversation_id}`"
                  @click="enroll([item.conversation_id])"
                />
                <Button
                  :label="t('ARROYO.PANEL.FOLLOW_UPS.ACTIONS.CANCEL')"
                  slate
                  ghost
                  sm
                  :disabled="isBusy"
                  @click="action = null"
                />
              </div>
            </template>
          </div>
        </li>
      </ul>
    </template>
  </section>
</template>

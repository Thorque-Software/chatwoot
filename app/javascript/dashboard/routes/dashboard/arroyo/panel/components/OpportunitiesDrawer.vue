<script setup>
import { ref, watch, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CommercialAPI from '../../api/commercial';
import ConversationListItem from './ConversationListItem.vue';
import { useCommercialLabels } from '../useCommercialLabels';

const props = defineProps({ selection: { type: Object, required: true } });
const emit = defineEmits(['close', 'updated']);
const { t } = useI18n();
const panel = ref(null);
const opportunities = ref([]);
const meta = ref({ total: 0, next_page: null });
const page = ref(1);
const loading = ref(false);
const error = ref('');
const actionError = ref('');
const busy = ref(false);
const exporting = ref(false);
const confirming = ref(null);
const products = ref({});
const requestKeys = new Map();
let requestSequence = 0;
let previousFocus;
const metricLabels = useCommercialLabels();
const label = state => metricLabels.value[state];

const fetchPage = async nextPage => {
  requestSequence += 1;
  const request = requestSequence;
  loading.value = true;
  error.value = '';
  confirming.value = null;
  try {
    const { data } = await CommercialAPI.getOpportunities({
      ...props.selection.params,
      page: nextPage,
    });
    if (request !== requestSequence) return;
    opportunities.value = data.opportunities;
    meta.value = data.meta;
    page.value = nextPage;
  } catch {
    if (request === requestSequence)
      error.value = t('ARROYO.PANEL.FUNNEL.LIST_ERROR');
  } finally {
    if (request === requestSequence) loading.value = false;
  }
};
const updateOpportunity = async (item, outcome) => {
  busy.value = true;
  actionError.value = '';
  try {
    await CommercialAPI.updateOpportunity(item.id, {
      outcome,
      ...(products.value[item.id] ? { product: products.value[item.id] } : {}),
    });
    emit('updated');
    await fetchPage(page.value);
  } catch (failure) {
    actionError.value =
      failure?.response?.data?.errors?.join(', ') ||
      t('ARROYO.PANEL.FUNNEL.ACTION_ERROR');
  } finally {
    busy.value = false;
  }
};
const createOpportunity = async item => {
  busy.value = true;
  actionError.value = '';
  if (!requestKeys.has(item.id)) requestKeys.set(item.id, crypto.randomUUID());
  try {
    await CommercialAPI.createOpportunity({
      conversation_id: item.conversation.display_id,
      request_key: requestKeys.get(item.id),
      ...(products.value[item.id] ? { product: products.value[item.id] } : {}),
    });
    confirming.value = null;
    emit('updated');
    await fetchPage(page.value);
  } catch (failure) {
    actionError.value =
      failure?.response?.data?.errors?.join(', ') ||
      t('ARROYO.PANEL.FUNNEL.ACTION_ERROR');
  } finally {
    busy.value = false;
  }
};
const exportCsv = async () => {
  exporting.value = true;
  actionError.value = '';
  try {
    const { data } = await CommercialAPI.exportReport(props.selection.params);
    downloadCsvFile(`consultas_${props.selection.params.metric}.csv`, data);
  } catch {
    actionError.value = t('ARROYO.PANEL.FUNNEL.EXPORT_ERROR');
  } finally {
    exporting.value = false;
  }
};
useKeyboardEvents({ Escape: { action: () => emit('close') } });
watch(
  () => props.selection,
  () => fetchPage(1),
  { immediate: true }
);
onMounted(() => {
  previousFocus = document.activeElement;
  panel.value.focus();
});
onBeforeUnmount(() => previousFocus?.focus());
</script>

<template>
  <aside
    ref="panel"
    tabindex="-1"
    :aria-label="selection.title"
    :aria-busy="loading"
    class="fixed inset-y-0 z-50 flex w-full max-w-xl flex-col border-n-weak bg-n-surface-2 shadow-lg outline-none ltr:right-0 ltr:border-l rtl:left-0 rtl:border-r"
  >
    <header
      class="flex items-start justify-between gap-3 border-b border-n-weak px-5 py-4"
    >
      <div class="flex min-w-0 flex-col gap-1">
        <h2 class="text-heading-2 text-n-slate-12">{{ selection.title }}</h2>
        <p class="mb-0 text-label-small text-n-slate-11">
          {{
            t('ARROYO.PANEL.FUNNEL.DATE_RANGE', {
              since: selection.params.since,
              until: selection.params.until,
            })
          }}
        </p>
        <p class="mb-0 text-label-small text-n-slate-11">
          {{
            selection.params.scope === 'activity'
              ? t('ARROYO.PANEL.FUNNEL.ACTIVITY_TITLE')
              : t('ARROYO.PANEL.FUNNEL.COHORT_TITLE')
          }}
        </p>
      </div>
      <Button
        icon="i-lucide-x"
        slate
        ghost
        sm
        :aria-label="t('ARROYO.PANEL.DRAWER.CLOSE')"
        @click="emit('close')"
      />
    </header>
    <div
      class="flex items-center justify-between gap-3 border-b border-n-weak px-5 py-3"
    >
      <span
        class="text-body-main tabular-nums text-n-slate-11"
        aria-live="polite"
      >
        {{ t('ARROYO.PANEL.FUNNEL.LIST_COUNT', { count: meta.total }) }}
      </span>
      <Button
        icon="i-lucide-download"
        slate
        ghost
        sm
        :label="t('ARROYO.PANEL.EXPORT')"
        data-testid="opportunities-export"
        :disabled="exporting || loading"
        @click="exportCsv"
      />
    </div>
    <div class="flex-1 overflow-y-auto p-3">
      <div v-if="loading" class="flex justify-center py-10"><Spinner /></div>
      <div
        v-else-if="error"
        role="alert"
        class="flex flex-col items-start gap-3 p-3 text-n-ruby-11"
      >
        {{ error
        }}<Button
          :label="t('ARROYO.PANEL.FUNNEL.RETRY')"
          slate
          sm
          @click="fetchPage(page)"
        />
      </div>
      <p
        v-else-if="!opportunities.length"
        class="p-5 text-center text-body-main text-n-slate-11"
      >
        {{ t('ARROYO.PANEL.DRAWER.EMPTY') }}
      </p>
      <ul v-else class="flex flex-col divide-y divide-n-weak">
        <li v-for="item in opportunities" :key="item.id" class="py-3">
          <ConversationListItem :conversation="item.conversation" />
          <div
            class="flex flex-wrap items-center gap-2 px-3 py-2 text-label-small text-n-slate-11"
          >
            <span class="rounded bg-n-alpha-2 px-2 py-1 text-n-slate-12">{{
              label(item.state)
            }}</span>
            <span
              v-if="item.overdue"
              class="rounded bg-n-amber-3 px-2 py-1 text-n-amber-11"
            >
              {{ label('overdue') }}
            </span>
            <span v-if="item.coverage === 'partial'">{{
              t('ARROYO.PANEL.FUNNEL.PARTIAL')
            }}</span>
            <span>{{ item.reference }}</span>
          </div>
          <p class="mb-0 px-3 text-label-small text-n-slate-11">
            {{
              t('ARROYO.PANEL.FUNNEL.OWNER', {
                name: item.assignee?.name || t('ARROYO.PANEL.UNASSIGNED'),
              })
            }}
          </p>
          <details class="mx-3 mt-3 rounded-lg border border-n-weak p-3">
            <summary
              class="cursor-pointer text-body-main text-n-blue-11 focus-visible:outline-n-blue-9"
            >
              {{ t('ARROYO.PANEL.FUNNEL.MANAGE') }}
            </summary>
            <div class="mt-3 flex flex-col gap-3">
              <Input
                v-if="!['won', 'lost'].includes(item.state)"
                v-model="products[item.id]"
                :label="t('ARROYO.PANEL.FUNNEL.PRODUCT')"
              />
              <div class="flex flex-wrap gap-2">
                <template v-if="!['won', 'lost'].includes(item.state)">
                  <Button
                    :label="t('ARROYO.PANEL.FUNNEL.ACTIONS.WON')"
                    sm
                    :disabled="busy"
                    :data-testid="`opportunity-${item.id}-won`"
                    @click="updateOpportunity(item, 'won')"
                  />
                  <Button
                    :label="t('ARROYO.PANEL.FUNNEL.ACTIONS.LOST')"
                    slate
                    faded
                    sm
                    :disabled="busy"
                    :data-testid="`opportunity-${item.id}-lost`"
                    @click="updateOpportunity(item, 'lost')"
                  />
                </template>
                <Button
                  v-if="['lost', 'inactive'].includes(item.state)"
                  :label="t('ARROYO.PANEL.FUNNEL.ACTIONS.RESUME')"
                  slate
                  faded
                  sm
                  :disabled="busy"
                  :data-testid="`opportunity-${item.id}-resume`"
                  @click="updateOpportunity(item, 'resume')"
                />
                <Button
                  v-if="item.state === 'won' && confirming !== item.id"
                  :label="t('ARROYO.PANEL.FUNNEL.ACTIONS.NEW')"
                  slate
                  faded
                  sm
                  :disabled="busy"
                  :data-testid="`opportunity-${item.id}-new`"
                  @click="confirming = item.id"
                />
              </div>
              <div v-if="confirming === item.id" class="flex flex-col gap-3">
                <p class="mb-0 text-body-main text-n-slate-11">
                  {{ t('ARROYO.PANEL.FUNNEL.NEW_CONFIRMATION') }}
                </p>
                <Input
                  v-model="products[item.id]"
                  :label="t('ARROYO.PANEL.FUNNEL.PRODUCT')"
                />
                <div class="flex flex-wrap gap-2">
                  <Button
                    :label="t('ARROYO.PANEL.FUNNEL.ACTIONS.CONFIRM')"
                    sm
                    :disabled="busy"
                    :data-testid="`opportunity-${item.id}-confirm`"
                    @click="createOpportunity(item)"
                  /><Button
                    :label="t('ARROYO.PANEL.FUNNEL.ACTIONS.CANCEL')"
                    slate
                    ghost
                    sm
                    :disabled="busy"
                    @click="confirming = null"
                  />
                </div>
              </div>
            </div>
          </details>
        </li>
      </ul>
    </div>
    <p
      v-if="actionError"
      role="alert"
      class="mb-0 px-5 py-3 text-body-main text-n-ruby-11"
    >
      {{ actionError }}
    </p>
    <footer
      class="flex items-center justify-between gap-3 border-t border-n-weak px-5 py-3"
    >
      <Button
        :label="t('ARROYO.PANEL.FUNNEL.PREVIOUS')"
        slate
        faded
        sm
        :disabled="page === 1 || loading || busy"
        data-testid="opportunities-previous"
        @click="fetchPage(page - 1)"
      />
      <span class="text-label-small tabular-nums text-n-slate-11">{{
        t('ARROYO.PANEL.FUNNEL.PAGE', { page })
      }}</span>
      <Button
        :label="t('ARROYO.PANEL.FUNNEL.NEXT')"
        slate
        faded
        sm
        :disabled="!meta.next_page || loading || busy"
        data-testid="opportunities-next"
        @click="fetchPage(meta.next_page)"
      />
    </footer>
  </aside>
</template>

<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';

// Recompras y postventa que no salió: dos listas cortas y colapsables dentro de la misma pestaña.
const props = defineProps({ data: { type: Object, required: true } });
const emit = defineEmits(['select']);
const { t, locale } = useI18n();
const { accountId } = useAccount();

const issues = computed(() => props.data.post_sale_issues);
const REPURCHASE = ['repeat_sales', 'post_sale_replies'];
const repurchaseLabels = computed(() => ({
  repeat_sales: t('ARROYO.PANEL.BOARD.EXTRAS.REPEAT_SALES'),
  post_sale_replies: t('ARROYO.PANEL.BOARD.EXTRAS.POST_SALE_REPLIES'),
}));
const repurchaseLabel = key => repurchaseLabels.value[key];
const link = id =>
  frontendURL(conversationUrl({ accountId: accountId.value, id }));
const when = value =>
  value
    ? new Intl.DateTimeFormat(locale.value, {
        dateStyle: 'short',
        timeStyle: 'short',
        timeZone: props.data.timezone,
      }).format(new Date(value))
    : '';
const statusLabels = computed(() => ({
  failed: t('ARROYO.PANEL.BOARD.EXTRAS.STATUS.FAILED'),
  not_executed: t('ARROYO.PANEL.BOARD.EXTRAS.STATUS.NOT_EXECUTED'),
  unconfirmed: t('ARROYO.PANEL.BOARD.EXTRAS.STATUS.UNCONFIRMED'),
}));
const statusLabel = status => statusLabels.value[status] || status;
</script>

<template>
  <div class="grid min-w-0 gap-5 lg:grid-cols-2">
    <details
      class="group rounded-xl border border-n-weak bg-n-solid-2 p-4 lg:p-5"
      data-testid="board-repurchases"
    >
      <summary
        class="flex cursor-pointer list-none items-center justify-between gap-3"
      >
        <h2 class="text-heading-3 text-n-slate-12">
          {{ t('ARROYO.PANEL.BOARD.EXTRAS.REPURCHASE_TITLE') }}
        </h2>
        <span class="flex items-center gap-2 text-label-small text-n-slate-11">
          {{ data.repurchases.repeat_sales }}
          <span
            class="i-lucide-chevron-down size-4 transition-transform group-open:rotate-180"
            aria-hidden="true"
          />
        </span>
      </summary>
      <div class="mt-3 flex flex-col divide-y divide-n-weak">
        <button
          v-for="key in REPURCHASE"
          :key="key"
          type="button"
          class="flex items-center justify-between gap-3 py-3 text-start text-body-main text-n-slate-11 [@media(hover:hover)]:hover:text-n-slate-12"
          :data-testid="`board-${key}`"
          @click="
            emit('select', {
              title: repurchaseLabel(key),
              filter: { metric: key },
            })
          "
        >
          {{ repurchaseLabel(key) }}
          <span class="text-xl font-medium tabular-nums text-n-teal-11">
            {{ data.repurchases[key] }}
          </span>
        </button>
      </div>
    </details>

    <details
      class="group rounded-xl border border-n-weak bg-n-solid-2 p-4 lg:p-5"
      :open="issues.count > 0"
      data-testid="board-post-sale-issues"
    >
      <summary
        class="flex cursor-pointer list-none items-center justify-between gap-3"
      >
        <h2 class="text-heading-3 text-n-slate-12">
          {{ t('ARROYO.PANEL.BOARD.EXTRAS.ISSUES_TITLE') }}
        </h2>
        <span
          class="flex items-center gap-2 text-label-small"
          :class="issues.count ? 'text-n-amber-11' : 'text-n-slate-11'"
        >
          {{ issues.count }}
          <span
            class="i-lucide-chevron-down size-4 transition-transform group-open:rotate-180"
            aria-hidden="true"
          />
        </span>
      </summary>
      <p v-if="!issues.count" class="mb-0 mt-3 text-body-main text-n-slate-11">
        {{ t('ARROYO.PANEL.BOARD.EXTRAS.ISSUES_EMPTY') }}
      </p>
      <ul v-else class="m-0 mt-3 flex list-none flex-col divide-y divide-n-weak p-0">
        <li
          v-for="item in issues.items"
          :key="item.id"
          class="flex flex-col gap-1 py-3"
        >
          <span class="flex flex-wrap items-center justify-between gap-2">
            <a
              v-if="item.conversation_id"
              :href="link(item.conversation_id)"
              class="text-body-main font-medium text-n-blue-11"
            >
              {{ item.contact || `#${item.conversation_id}` }}
            </a>
            <span
              class="rounded bg-n-amber-3 px-2 py-0.5 text-label-small text-n-amber-11"
            >
              {{ statusLabel(item.status) }}
            </span>
          </span>
          <span class="text-label-small text-n-slate-11">
            {{
              [item.stage.toUpperCase(), item.product, item.seller, when(item.scheduled_at)]
                .filter(Boolean)
                .join(' · ')
            }}
          </span>
          <span v-if="item.error" class="text-label-small text-n-ruby-11">
            {{ item.error }}
          </span>
        </li>
      </ul>
      <p
        v-if="issues.count > issues.items.length"
        class="mb-0 text-label-small text-n-slate-10"
      >
        {{ t('ARROYO.PANEL.BOARD.EXTRAS.ISSUES_MORE', { count: issues.count - issues.items.length }) }}
      </p>
    </details>
  </div>
</template>

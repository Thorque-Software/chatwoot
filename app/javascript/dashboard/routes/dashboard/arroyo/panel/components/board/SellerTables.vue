<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Select from 'dashboard/components-next/select/Select.vue';
import FunnelHelp from '../FunnelHelp.vue';
import { sellerPresentation } from '../../commercialConstants';
import { COUNTERS, useBoardLabels } from './useBoardLabels';

// Resumen por vendedor y tabla día por vendedor: todo lo que hizo cada uno sin entrar conversación por conversación.
const props = defineProps({
  data: { type: Object, required: true },
  sellerIds: { type: Array, default: () => [] },
});
const emit = defineEmits(['select']);
const { t, locale } = useI18n();
const { counters } = useBoardLabels();

const dayMetric = ref('received');
const metricOptions = computed(() =>
  COUNTERS.map(value => ({ value, label: counters.value[value] }))
);

const counterFilter = counter => {
  if (counter === 'received') return {};
  if (counter === 'attended') return { attended: 'true' };
  return { stage: counter };
};
const percent = (part, total) =>
  total ? `${Math.round((part / total) * 100)}%` : '–';
const sellerTotal = computed(() =>
  Object.fromEntries(
    COUNTERS.map(counter => [
      counter,
      props.data.sellers.reduce((sum, seller) => sum + seller[counter], 0),
    ])
  )
);
const days = computed(() => [...props.data.days].reverse());
const dayLabel = date =>
  new Intl.DateTimeFormat(locale.value, {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
  }).format(new Date(`${date}T12:00:00Z`));

const select = (seller, counter, date) => {
  const who = seller ? seller.name : t('ARROYO.PANEL.BOARD.DAYS.TOTAL');
  emit('select', {
    title: [who, counters.value[counter], date && dayLabel(date)]
      .filter(Boolean)
      .join(' · '),
    filter: {
      ...counterFilter(counter),
      ...(seller ? { bucket: String(seller.id) } : {}),
      ...(date ? { date } : {}),
    },
  });
};
</script>

<template>
  <section
    class="flex min-w-0 flex-col gap-4 rounded-xl border border-n-weak bg-n-solid-2 p-4 lg:p-5"
    data-testid="board-sellers"
  >
    <div class="flex items-center gap-1">
      <h2 class="text-heading-3 text-n-slate-12">
        {{ t('ARROYO.PANEL.BOARD.SELLERS.TITLE') }}
      </h2>
      <FunnelHelp
        :title="t('ARROYO.PANEL.BOARD.SELLERS.TITLE')"
        :text="t('ARROYO.PANEL.BOARD.SELLERS.HELP')"
      />
    </div>
    <div class="min-w-0 overflow-x-auto overscroll-x-contain">
      <table class="w-full min-w-[44rem] text-label-small">
        <thead>
          <tr class="border-b border-n-weak text-n-slate-10">
            <th scope="col" class="py-2 pe-3 text-start font-medium">
              {{ t('ARROYO.PANEL.BOARD.SELLERS.SELLER') }}
            </th>
            <th
              v-for="counter in COUNTERS"
              :key="counter"
              scope="col"
              class="px-2 py-2 text-end font-medium"
            >
              {{ counters[counter] }}
            </th>
            <th scope="col" class="px-2 py-2 text-end font-medium">
              {{ t('ARROYO.PANEL.BOARD.SELLERS.RATE_WON') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="seller in data.sellers"
            :key="seller.id"
            class="border-b border-n-weak last:border-0"
          >
            <th
              scope="row"
              class="py-2 pe-3 text-start font-medium text-n-slate-12"
            >
              <span class="flex items-center gap-2">
                <span
                  class="size-2 shrink-0 rounded-full"
                  :class="sellerPresentation(seller.id, sellerIds).dot"
                  aria-hidden="true"
                />
                {{ seller.name }}
              </span>
            </th>
            <td v-for="counter in COUNTERS" :key="counter" class="p-1 text-end">
              <button
                type="button"
                class="w-full rounded-md px-2 py-1.5 text-end tabular-nums [@media(hover:hover)]:hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
                :class="
                  seller[counter] ? 'font-medium text-n-blue-11' : 'text-n-slate-10'
                "
                :data-testid="`seller-${seller.id}-${counter}`"
                @click="select(seller, counter)"
              >
                {{ seller[counter] }}
                <span
                  v-if="counter === 'attended'"
                  class="block text-[11px] font-normal text-n-slate-10"
                  >{{ percent(seller.attended, seller.received) }}</span
                >
              </button>
            </td>
            <td class="px-2 text-end tabular-nums text-n-teal-11">
              {{ percent(seller.won, seller.received) }}
            </td>
          </tr>
          <tr v-if="data.sellers.length > 1" class="text-n-slate-11">
            <th scope="row" class="py-2 pe-3 text-start font-medium">
              {{ t('ARROYO.PANEL.BOARD.SELLERS.TOTAL') }}
            </th>
            <td
              v-for="counter in COUNTERS"
              :key="counter"
              class="px-3 py-2 text-end font-semibold tabular-nums"
            >
              {{ sellerTotal[counter] }}
            </td>
            <td class="px-2 text-end tabular-nums">
              {{ percent(sellerTotal.won, sellerTotal.received) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div
      class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak pt-4"
    >
      <div class="flex items-center gap-1">
        <h3 class="text-heading-3 text-n-slate-12">
          {{ t('ARROYO.PANEL.BOARD.DAYS.TITLE') }}
        </h3>
        <FunnelHelp
          :title="t('ARROYO.PANEL.BOARD.DAYS.TITLE')"
          :text="t('ARROYO.PANEL.BOARD.DAYS.HELP')"
        />
      </div>
      <label class="flex items-center gap-2 text-label-small text-n-slate-11">
        {{ t('ARROYO.PANEL.BOARD.DAYS.METRIC') }}
        <Select
          v-model="dayMetric"
          :options="metricOptions"
          data-testid="board-day-metric"
        />
      </label>
    </div>
    <div
      class="min-w-0 max-h-[28rem] overflow-auto overscroll-contain"
      data-testid="board-days"
    >
      <table class="w-full text-label-small">
        <thead class="sticky top-0 bg-n-solid-2">
          <tr class="border-b border-n-weak text-n-slate-10">
            <th scope="col" class="py-2 pe-3 text-start font-medium">
              {{ t('ARROYO.PANEL.BOARD.DAYS.DAY') }}
            </th>
            <th
              v-for="seller in data.sellers"
              :key="seller.id"
              scope="col"
              class="px-2 py-2 text-end font-medium"
            >
              {{ seller.name }}
            </th>
            <th scope="col" class="px-2 py-2 text-end font-medium">
              {{ t('ARROYO.PANEL.BOARD.DAYS.TOTAL') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="day in days"
            :key="day.date"
            class="border-b border-n-weak last:border-0"
          >
            <th
              scope="row"
              class="whitespace-nowrap py-1 pe-3 text-start font-medium text-n-slate-11"
            >
              {{ dayLabel(day.date) }}
            </th>
            <td v-for="seller in data.sellers" :key="seller.id" class="p-1">
              <button
                type="button"
                class="w-full rounded-md px-2 py-1 text-end tabular-nums [@media(hover:hover)]:hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
                :class="
                  day.sellers[seller.id]?.[dayMetric]
                    ? 'font-medium text-n-blue-11'
                    : 'text-n-slate-9'
                "
                :data-testid="`day-${day.date}-${seller.id}`"
                @click="select(seller, dayMetric, day.date)"
              >
                {{ day.sellers[seller.id]?.[dayMetric] ?? 0 }}
              </button>
            </td>
            <td class="p-1">
              <button
                type="button"
                class="w-full rounded-md px-2 py-1 text-end font-semibold tabular-nums text-n-slate-12 [@media(hover:hover)]:hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
                @click="select(null, dayMetric, day.date)"
              >
                {{ day.total[dayMetric] }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>

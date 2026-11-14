<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import FunnelHelp from '../FunnelHelp.vue';
import { useBoardLabels } from './useBoardLabels';

// Ventas por campaña y por anuncio de Meta: qué publicación trae consultas y cuál vende. La orgánica va al final.
defineProps({ origins: { type: Array, required: true } });
const emit = defineEmits(['select']);
const { t } = useI18n();
const open = ref({});
const { counters } = useBoardLabels();

const name = item =>
  item.kind === 'organic' ? t('ARROYO.PANEL.BOARD.FLOW.ORGANIC') : item.name;
const percent = (part, total) =>
  total ? `${Math.round((part / total) * 100)}%` : '–';
const COLUMNS = ['received', 'attended', 'won', 'lost'];
const filterFor = column => {
  if (column === 'received') return {};
  if (column === 'attended') return { attended: 'true' };
  return { stage: column };
};
const select = (item, column) =>
  emit('select', {
    title: `${name(item)} · ${counters.value[column]}`,
    filter: { origin: item.key, ...filterFor(column) },
  });
</script>

<template>
  <section
    class="flex min-w-0 flex-col gap-4 rounded-xl border border-n-weak bg-n-solid-2 p-4 lg:p-5"
    data-testid="board-origins"
  >
    <div class="flex items-center gap-1">
      <h2 class="text-heading-3 text-n-slate-12">
        {{ t('ARROYO.PANEL.BOARD.ORIGINS.TITLE') }}
      </h2>
      <FunnelHelp
        :title="t('ARROYO.PANEL.BOARD.ORIGINS.TITLE')"
        :text="t('ARROYO.PANEL.BOARD.ORIGINS.HELP')"
      />
    </div>
    <p
      v-if="!origins.some(item => item.kind === 'campaign')"
      class="mb-0 text-body-main text-n-slate-11"
    >
      {{ t('ARROYO.PANEL.BOARD.ORIGINS.EMPTY') }}
    </p>
    <div v-if="origins.length" class="min-w-0 overflow-x-auto">
      <table class="w-full min-w-[36rem] text-label-small">
        <thead>
          <tr class="border-b border-n-weak text-n-slate-10">
            <th scope="col" class="py-2 pe-3 text-start font-medium">
              {{ t('ARROYO.PANEL.BOARD.ORIGINS.NAME') }}
            </th>
            <th
              v-for="column in COLUMNS"
              :key="column"
              scope="col"
              class="px-2 py-2 text-end font-medium"
            >
              {{ counters[column] }}
            </th>
            <th scope="col" class="px-2 py-2 text-end font-medium">
              {{ t('ARROYO.PANEL.BOARD.ORIGINS.CONVERSION') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <template v-for="item in origins" :key="item.key">
            <tr class="border-b border-n-weak">
              <th
                scope="row"
                class="py-2 pe-3 text-start font-medium text-n-slate-12"
              >
                <button
                  v-if="item.ads.length"
                  type="button"
                  class="flex items-center gap-1.5 text-start"
                  :aria-expanded="Boolean(open[item.key])"
                  :data-testid="`origin-toggle-${item.key}`"
                  @click="open[item.key] = !open[item.key]"
                >
                  <span
                    class="size-4 shrink-0"
                    :class="
                      open[item.key]
                        ? 'i-lucide-chevron-down'
                        : 'i-lucide-chevron-right rtl:rotate-180'
                    "
                    aria-hidden="true"
                  />
                  {{ name(item) }}
                  <span class="font-normal text-n-slate-10">
                    {{ `(${item.ads.length})` }}
                  </span>
                </button>
                <span v-else class="ps-5">{{ name(item) }}</span>
              </th>
              <td v-for="column in COLUMNS" :key="column" class="p-1 text-end">
                <button
                  type="button"
                  class="w-full rounded-md px-2 py-1.5 text-end tabular-nums text-n-blue-11 [@media(hover:hover)]:hover:bg-n-alpha-2"
                  @click="select(item, column)"
                >
                  {{ item[column] }}
                </button>
              </td>
              <td
                class="px-2 text-end font-semibold tabular-nums text-n-teal-11"
              >
                {{ percent(item.won, item.received) }}
              </td>
            </tr>
            <template v-if="open[item.key]">
              <tr
                v-for="ad in item.ads"
                :key="ad.key"
                class="border-b border-n-weak bg-n-alpha-1"
              >
                <th
                  scope="row"
                  class="py-1.5 pe-3 ps-9 text-start font-normal text-n-slate-11"
                >
                  {{ ad.name }}
                </th>
                <td
                  v-for="column in COLUMNS"
                  :key="column"
                  class="p-1 text-end"
                >
                  <button
                    type="button"
                    class="w-full rounded-md px-2 py-1 text-end tabular-nums text-n-blue-11 [@media(hover:hover)]:hover:bg-n-alpha-2"
                    @click="select(ad, column)"
                  >
                    {{ ad[column] }}
                  </button>
                </td>
                <td class="px-2 text-end tabular-nums text-n-teal-11">
                  {{ percent(ad.won, ad.received) }}
                </td>
              </tr>
            </template>
          </template>
        </tbody>
      </table>
    </div>
  </section>
</template>

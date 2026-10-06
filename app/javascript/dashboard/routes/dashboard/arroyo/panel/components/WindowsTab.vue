<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConversationListItem from './ConversationListItem.vue';

defineProps({
  windows: { type: Object, default: null },
  isLoading: { type: Boolean, default: false },
});

const { t } = useI18n();

const sections = computed(() => [
  {
    key: 'closing_soon',
    title: t('ARROYO.PANEL.WINDOWS.CLOSING_SOON'),
    help: t('ARROYO.PANEL.WINDOWS.CLOSING_SOON_HELP'),
  },
  {
    key: 'closed_today',
    title: t('ARROYO.PANEL.WINDOWS.CLOSED_TODAY'),
    help: t('ARROYO.PANEL.WINDOWS.CLOSED_TODAY_HELP'),
  },
]);
</script>

<template>
  <div v-if="isLoading || !windows" class="flex justify-center py-10">
    <Spinner />
  </div>
  <div v-else class="grid gap-6 lg:grid-cols-2">
    <section
      v-for="section in sections"
      :key="section.key"
      class="flex flex-col gap-2 p-4 rounded-xl bg-n-solid-2 outline outline-1 outline-n-container"
    >
      <div class="flex items-center justify-between gap-2">
        <h3 class="text-heading-3 text-n-slate-12">
          {{ section.title }}
        </h3>
        <span class="text-label-small text-n-slate-11">
          {{ windows[section.key].length }}
        </span>
      </div>
      <p class="mb-0 text-body-main text-n-slate-11">{{ section.help }}</p>
      <p
        v-if="!windows[section.key].length"
        class="py-6 mb-0 text-center text-body-main text-n-slate-11"
      >
        {{ t('ARROYO.PANEL.WINDOWS.EMPTY') }}
      </p>
      <ConversationListItem
        v-for="conversation in windows[section.key]"
        :key="conversation.id"
        :conversation="conversation"
      />
    </section>
  </div>
</template>

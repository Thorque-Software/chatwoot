<script setup>
import { useI18n } from 'vue-i18n';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConversationListItem from './ConversationListItem.vue';

defineProps({
  title: { type: String, default: '' },
  subtitle: { type: String, default: '' },
  conversations: { type: Array, default: () => [] },
  count: { type: Number, default: 0 },
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['close']);
const isOpen = defineModel('open', { type: Boolean, default: false });

const { t } = useI18n();

const close = () => {
  isOpen.value = false;
  emit('close');
};

useKeyboardEvents({
  Escape: {
    action: () => {
      if (isOpen.value) close();
    },
  },
});
</script>

<template>
  <transition
    enter-active-class="transition-transform duration-200 ease-out"
    leave-active-class="transition-transform duration-150 ease-in"
    enter-from-class="ltr:translate-x-full rtl:-translate-x-full"
    leave-to-class="ltr:translate-x-full rtl:-translate-x-full"
  >
    <aside
      v-if="isOpen"
      class="fixed inset-y-0 z-50 flex flex-col w-full max-w-[30rem] ltr:right-0 rtl:left-0 bg-n-surface-2 border-n-weak ltr:border-l rtl:border-r shadow-lg"
    >
      <header
        class="flex items-start justify-between gap-3 px-5 py-4 border-b border-n-weak"
      >
        <div class="flex flex-col gap-1 min-w-0">
          <h3 class="text-heading-2 text-n-slate-12 truncate">{{ title }}</h3>
          <p v-if="subtitle" class="mb-0 text-body-main text-n-slate-11">
            {{ subtitle }}
          </p>
        </div>
        <Button
          icon="i-lucide-x"
          slate
          ghost
          sm
          :aria-label="t('ARROYO.PANEL.DRAWER.CLOSE')"
          @click="close"
        />
      </header>
      <div class="flex-1 overflow-y-auto px-2 py-2">
        <div v-if="isLoading" class="flex justify-center py-10">
          <Spinner />
        </div>
        <p
          v-else-if="!conversations.length"
          class="py-10 text-center text-body-main text-n-slate-11"
        >
          {{ t('ARROYO.PANEL.DRAWER.EMPTY') }}
        </p>
        <template v-else>
          <p
            v-if="count > conversations.length"
            class="px-3 py-2 mb-0 text-label-small text-n-slate-11"
          >
            {{
              t('ARROYO.PANEL.DRAWER.TRUNCATED', {
                shown: conversations.length,
                count,
              })
            }}
          </p>
          <ConversationListItem
            v-for="conversation in conversations"
            :key="conversation.id"
            :conversation="conversation"
          />
        </template>
      </div>
    </aside>
  </transition>
</template>

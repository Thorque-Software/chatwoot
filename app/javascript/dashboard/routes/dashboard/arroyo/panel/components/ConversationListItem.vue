<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { dynamicTime, messageStamp } from 'shared/helpers/timeHelper';

const props = defineProps({
  conversation: { type: Object, required: true },
});

const { t } = useI18n();
const { accountId } = useAccount();

const url = computed(() =>
  frontendURL(
    conversationUrl({
      accountId: accountId.value,
      id: props.conversation.display_id,
    })
  )
);

const contactName = computed(
  () =>
    props.conversation.contact.name || props.conversation.contact.phone_number
);
</script>

<template>
  <router-link
    :to="url"
    class="flex flex-col gap-1 px-3 py-2.5 rounded-lg hover:bg-n-alpha-2"
  >
    <div class="flex items-center justify-between gap-2">
      <span class="text-body-main font-medium text-n-slate-12 truncate">
        {{ contactName }}
      </span>
      <span class="text-label-small text-n-slate-11 shrink-0">
        {{ t('ARROYO.PANEL.CONVERSATION_ID', { id: conversation.display_id }) }}
      </span>
    </div>
    <p
      v-if="conversation.last_message?.content"
      class="mb-0 text-body-main text-n-slate-11 line-clamp-2"
    >
      {{ conversation.last_message.content }}
    </p>
    <div
      class="flex flex-wrap gap-x-3 gap-y-1 text-label-small text-n-slate-11"
    >
      <span>{{ conversation.inbox.name }}</span>
      <span v-if="conversation.assignee">{{ conversation.assignee.name }}</span>
      <span v-else>{{ t('ARROYO.PANEL.UNASSIGNED') }}</span>
      <span v-if="conversation.closes_at" class="text-n-amber-11">
        {{
          t('ARROYO.PANEL.WINDOWS.CLOSES_AT', {
            time: messageStamp(conversation.closes_at, 'HH:mm'),
          })
        }}
      </span>
      <span v-else-if="conversation.last_message">
        {{ dynamicTime(conversation.last_message.created_at) }}
      </span>
    </div>
  </router-link>
</template>

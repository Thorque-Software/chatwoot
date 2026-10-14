<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import SocialCommentsAPI from '../../api/socialComments';
import { useArroyoFeatures } from '../../composables/useArroyoFeatures';
import { safeMetaUrl } from '../helpers';

const props = defineProps({
  conversationId: { type: [String, Number], default: null },
  inboxId: { type: [String, Number], default: null },
  isPrivate: { type: Boolean, default: false },
});
const { t } = useI18n();
const { features } = useArroyoFeatures();
const context = ref(null);
const eligible = computed(() =>
  features.value?.social_comments?.inboxes?.some(
    item => item.inbox_id === Number(props.inboxId)
  )
);
const source = computed(
  () =>
    context.value?.comments?.find(item => safeMetaUrl(item.post_url))?.post_url
);
const retryable = computed(
  () =>
    context.value?.comments
      ?.flatMap(item => item.replies)
      .filter(item => item.can_retry) || []
);

const load = async () => {
  context.value = null;
  if (!eligible.value || !props.conversationId) return;
  try {
    const { data } = await SocialCommentsAPI.context(props.conversationId);
    context.value = data;
  } catch {
    useAlert(t('ARROYO.SOCIAL_COMMENTS.LOAD_ERROR'));
  }
};

const retry = async id => {
  try {
    await SocialCommentsAPI.retry(id);
    await load();
    useAlert(t('ARROYO.SOCIAL_COMMENTS.RETRY_QUEUED'));
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('ARROYO.SOCIAL_COMMENTS.SAVE_ERROR')
    );
  }
};

watch([() => props.conversationId, eligible], load, { immediate: true });
</script>

<template>
  <section
    v-if="eligible && !isPrivate"
    class="border-t border-n-amber-6 bg-n-amber-2 px-4 py-3 text-sm text-n-slate-12"
    role="note"
  >
    <div class="flex items-center justify-between gap-3">
      <strong class="flex items-center gap-2">
        <span class="i-lucide-globe size-4 text-n-amber-11" />
        {{ t('ARROYO.SOCIAL_COMMENTS.PUBLIC_WARNING') }}
      </strong>
      <a
        v-if="source"
        :href="source"
        target="_blank"
        rel="noopener noreferrer"
        class="text-n-blue-text hover:underline"
      >
        {{ t('ARROYO.SOCIAL_COMMENTS.VIEW_POST') }}
      </a>
    </div>
    <p class="mb-0 mt-1 text-xs text-n-slate-11">
      {{
        t(
          context?.channel?.ready
            ? 'ARROYO.SOCIAL_COMMENTS.HUMAN_ONLY'
            : 'ARROYO.SOCIAL_COMMENTS.CONNECTION_PENDING_BODY'
        )
      }}
    </p>
    <div v-if="retryable.length" class="mt-2 flex flex-wrap gap-2">
      <Button
        v-for="reply in retryable"
        :key="reply.id"
        size="xs"
        variant="faded"
        :label="t('ARROYO.SOCIAL_COMMENTS.RETRY')"
        @click="retry(reply.id)"
      />
    </div>
  </section>
</template>

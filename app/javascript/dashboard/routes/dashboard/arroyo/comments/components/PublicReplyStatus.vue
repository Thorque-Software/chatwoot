<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { publicReplyState } from '../helpers';

const props = defineProps({
  attributes: { type: Object, default: () => ({}) },
});
const { t } = useI18n();
const state = computed(() => publicReplyState(props.attributes));
const error = computed(
  () =>
    props.attributes.arroyoPublicReplyError ||
    props.attributes.arroyo_public_reply_error
);
const author = computed(
  () =>
    props.attributes.arroyoPublicAuthor || props.attributes.arroyo_public_author
);
const color = computed(() => {
  if (state.value === 'published') return 'text-n-teal-11 bg-n-teal-2';
  if (state.value === 'failed') return 'text-n-ruby-11 bg-n-ruby-2';
  if (['pending_configuration', 'unconfirmed'].includes(state.value))
    return 'text-n-amber-11 bg-n-amber-2';
  return 'text-n-slate-11 bg-n-solid-3';
});
</script>

<template>
  <span
    v-if="state"
    :title="error"
    class="inline-flex rounded px-1.5 py-0.5 text-xs font-medium"
    :class="color"
  >
    {{ t('ARROYO.SOCIAL_COMMENTS.PUBLIC') }} ·
    {{ t(`ARROYO.SOCIAL_COMMENTS.STATUS.${state.toUpperCase()}`) }}
  </span>
  <span v-else-if="author" class="text-xs text-n-slate-11">
    {{ t('ARROYO.SOCIAL_COMMENTS.PUBLIC_AUTHOR', { name: author }) }}
  </span>
</template>

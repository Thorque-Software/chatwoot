<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SocialCommentsAPI from '../api/socialComments';
import { useArroyoFeatures } from '../composables/useArroyoFeatures';
import ChannelSettings from './components/ChannelSettings.vue';
import PublicReplyStatus from './components/PublicReplyStatus.vue';
import { safeMetaUrl } from './helpers';

const { t } = useI18n();
const route = useRoute();
const store = useStore();
const role = useMapGetter('getCurrentRole');
const { fetchFeatures, features } = useArroyoFeatures();
const comments = ref([]);
const channels = ref([]);
const loading = ref(false);
const configure = ref(false);
const platform = ref('');
const status = ref('');
const nextPage = ref(null);
const total = ref(0);
const isAdmin = computed(() => role.value === 'administrator');
const pendingConnection = computed(() =>
  channels.value.some(channel => !channel.ready)
);
const statuses = [
  'unanswered',
  'pending_configuration',
  'queued',
  'publishing',
  'published',
  'failed',
  'unconfirmed',
];

const load = async (page = 1) => {
  loading.value = true;
  try {
    const { data } = await SocialCommentsAPI.comments({
      platform: platform.value,
      status: status.value,
      page,
    });
    comments.value =
      page === 1 ? data.comments : [...comments.value, ...data.comments];
    total.value = data.total;
    nextPage.value = data.next_page;
  } catch {
    useAlert(t('ARROYO.SOCIAL_COMMENTS.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
};

const loadChannels = async () => {
  try {
    const { data } = await SocialCommentsAPI.channels();
    channels.value = data.channels;
    await fetchFeatures();
    await load();
  } catch {
    useAlert(t('ARROYO.SOCIAL_COMMENTS.LOAD_ERROR'));
  }
};

const lastReply = record => record.replies.at(-1);
const attributes = record => ({
  arroyo_kind: 'social_comment_reply',
  arroyo_public_reply_status: lastReply(record)?.status,
});
const conversationRoute = record => ({
  name: 'inbox_conversation',
  params: {
    accountId: route.params.accountId,
    conversation_id: record.conversation_id,
  },
});

watch([platform, status], () => load());
onMounted(() => {
  store.dispatch('agents/get');
  loadChannels();
});
</script>

<template>
  <main class="flex h-full w-full flex-col overflow-auto bg-n-background p-6">
    <header class="mb-6 flex flex-wrap items-start justify-between gap-4">
      <div>
        <div
          class="mb-2 flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-n-slate-10"
        >
          <span class="i-lucide-message-circle size-4" />{{
            t('ARROYO.SOCIAL_COMMENTS.HUMAN_LABEL')
          }}
        </div>
        <h1 class="mb-1 text-2xl font-semibold text-n-slate-12">
          {{ t('ARROYO.SOCIAL_COMMENTS.TITLE') }}
        </h1>
        <p class="m-0 text-sm text-n-slate-11">
          {{ t('ARROYO.SOCIAL_COMMENTS.DESCRIPTION') }}
        </p>
      </div>
      <div class="flex gap-2">
        <Button
          v-if="isAdmin"
          variant="faded"
          icon="i-lucide-settings-2"
          :label="t('ARROYO.SOCIAL_COMMENTS.CONFIGURE')"
          @click="configure = !configure"
        />
        <Button
          variant="faded"
          icon="i-lucide-refresh-cw"
          :disabled="loading"
          :label="t('ARROYO.SOCIAL_COMMENTS.REFRESH')"
          @click="loadChannels"
        />
      </div>
    </header>
    <div
      v-if="pendingConnection"
      class="mb-5 rounded-xl border border-n-amber-6 bg-n-amber-2 p-4"
      role="status"
    >
      <strong class="text-sm text-n-slate-12">{{
        t('ARROYO.SOCIAL_COMMENTS.CONNECTION_PENDING')
      }}</strong>
      <p class="mb-0 mt-1 text-sm text-n-slate-11">
        {{ t('ARROYO.SOCIAL_COMMENTS.CONNECTION_PENDING_BODY') }}
      </p>
    </div>
    <ChannelSettings
      v-if="
        isAdmin &&
        (configure || !channels.length) &&
        features?.social_comments?.enabled
      "
      class="mb-5"
      :channels="channels"
      @updated="loadChannels"
    />
    <div class="mb-4 flex flex-wrap items-end justify-between gap-3">
      <div class="flex gap-3">
        <label class="text-xs text-n-slate-11"
          >{{ t('ARROYO.SOCIAL_COMMENTS.NETWORK') }}
          <select v-model="platform" class="mb-0 mt-1 min-w-40">
            <option value="">{{ t('ARROYO.SOCIAL_COMMENTS.ALL') }}</option>
            <option value="instagram">
              {{ t('ARROYO.SOCIAL_COMMENTS.INSTAGRAM') }}
            </option>
            <option value="facebook">
              {{ t('ARROYO.SOCIAL_COMMENTS.FACEBOOK') }}
            </option>
          </select>
        </label>
        <label class="text-xs text-n-slate-11"
          >{{ t('ARROYO.SOCIAL_COMMENTS.STATE') }}
          <select v-model="status" class="mb-0 mt-1 min-w-44">
            <option value="">{{ t('ARROYO.SOCIAL_COMMENTS.ALL') }}</option>
            <option v-for="item in statuses" :key="item" :value="item">
              {{ t(`ARROYO.SOCIAL_COMMENTS.STATUS.${item.toUpperCase()}`) }}
            </option>
          </select>
        </label>
      </div>
      <span class="text-xs text-n-slate-10">{{
        t('ARROYO.SOCIAL_COMMENTS.COUNT', { count: total })
      }}</span>
    </div>
    <div v-if="loading && !comments.length" class="flex justify-center p-12">
      <Spinner />
    </div>
    <div
      v-else-if="!comments.length"
      class="rounded-xl border border-dashed border-n-weak p-12 text-center"
    >
      <span
        class="i-lucide-messages-square mx-auto mb-3 block size-8 text-n-slate-9"
      />
      <h2 class="text-base font-medium text-n-slate-12">
        {{ t('ARROYO.SOCIAL_COMMENTS.EMPTY_TITLE') }}
      </h2>
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t('ARROYO.SOCIAL_COMMENTS.EMPTY_BODY') }}
      </p>
    </div>
    <div v-else class="flex flex-col gap-3">
      <article
        v-for="record in comments"
        :key="record.id"
        class="rounded-xl border border-n-weak bg-n-solid-2 p-5"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div class="flex items-center gap-3">
            <div
              class="flex size-9 shrink-0 items-center justify-center rounded-full bg-n-solid-3 text-sm font-semibold text-n-slate-11"
            >
              {{ (record.author_name || '?').slice(0, 1).toUpperCase() }}
            </div>
            <div>
              <strong class="text-sm text-n-slate-12">{{
                record.author_name
              }}</strong
              ><span class="ml-2 text-xs capitalize text-n-slate-10">{{
                record.platform
              }}</span>
            </div>
          </div>
          <span v-if="record.deleted" class="text-xs text-n-ruby-11">{{
            t('ARROYO.SOCIAL_COMMENTS.DELETED')
          }}</span>
          <PublicReplyStatus
            v-else-if="lastReply(record)"
            :attributes="attributes(record)"
          />
          <span
            v-else
            class="rounded bg-n-solid-3 px-2 py-1 text-xs text-n-slate-11"
            >{{ t('ARROYO.SOCIAL_COMMENTS.STATUS.UNANSWERED') }}</span
          >
        </div>
        <p class="mb-3 mt-4 whitespace-pre-wrap text-sm text-n-slate-12">
          {{ record.body }}
        </p>
        <div
          v-if="lastReply(record)"
          class="mb-4 border-l-2 border-n-weak pl-3"
        >
          <div class="mb-1 text-xs font-medium text-n-slate-10">
            {{ lastReply(record).sender_name }}
          </div>
          <p class="m-0 whitespace-pre-wrap text-sm text-n-slate-11">
            {{ lastReply(record).content }}
          </p>
        </div>
        <footer
          class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak pt-3"
        >
          <a
            v-if="safeMetaUrl(record.post_url)"
            :href="record.post_url"
            target="_blank"
            rel="noopener noreferrer"
            class="text-xs text-n-blue-text hover:underline"
            >{{ t('ARROYO.SOCIAL_COMMENTS.VIEW_POST') }}</a
          >
          <span v-else class="text-xs text-n-slate-10">{{
            t('ARROYO.SOCIAL_COMMENTS.POST_ID', { id: record.media_id })
          }}</span>
          <RouterLink
            :to="conversationRoute(record)"
            class="flex items-center gap-1 text-sm font-medium text-n-blue-text hover:underline"
          >
            {{ t('ARROYO.SOCIAL_COMMENTS.OPEN_CONVERSATION')
            }}<span class="i-lucide-arrow-up-right size-4" />
          </RouterLink>
        </footer>
      </article>
      <Button
        v-if="nextPage"
        variant="faded"
        :disabled="loading"
        :label="t('ARROYO.SOCIAL_COMMENTS.LOAD_MORE')"
        @click="load(nextPage)"
      />
    </div>
  </main>
</template>

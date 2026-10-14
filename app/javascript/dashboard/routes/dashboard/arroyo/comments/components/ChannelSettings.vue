<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import SocialCommentsAPI from '../../api/socialComments';

defineProps({ channels: { type: Array, default: () => [] } });
const emit = defineEmits(['updated']);
const { t } = useI18n();
const agents = useMapGetter('agents/getAgents');
const form = ref({ platform: 'instagram', name: '', user_ids: [] });
const busy = ref(false);
const edits = ref({});
const hasMembers = computed(() => form.value.user_ids.length > 0);

const create = async () => {
  busy.value = true;
  try {
    await SocialCommentsAPI.createChannel({ ...form.value, name: form.value.name || t('ARROYO.SOCIAL_COMMENTS.DEFAULT_INBOX', { platform: form.value.platform }) });
    form.value.name = '';
    emit('updated');
  } catch (error) {
    useAlert(error?.response?.data?.error || t('ARROYO.SOCIAL_COMMENTS.SAVE_ERROR'));
  } finally {
    busy.value = false;
  }
};

const save = async channel => {
  busy.value = true;
  try {
    await SocialCommentsAPI.updateChannel(channel.id, edits.value[channel.id]);
    emit('updated');
    useAlert(t('ARROYO.SOCIAL_COMMENTS.SAVED'));
  } catch (error) {
    useAlert(error?.response?.data?.error || t('ARROYO.SOCIAL_COMMENTS.SAVE_ERROR'));
  } finally {
    busy.value = false;
  }
};

const edit = channel => {
  edits.value[channel.id] = {
    external_account_id: channel.external_account_id || '', api_version: channel.api_version || '', publishing_enabled: channel.publishing_enabled,
  };
};
</script>

<template>
  <section class="rounded-xl border border-n-weak bg-n-solid-2 p-5">
    <h2 class="text-base font-semibold text-n-slate-12">{{ t('ARROYO.SOCIAL_COMMENTS.SETUP_TITLE') }}</h2>
    <p class="text-sm text-n-slate-11">{{ t('ARROYO.SOCIAL_COMMENTS.SETUP_BODY') }}</p>
    <div v-for="channel in channels" :key="channel.id" class="mb-3 rounded-lg border border-n-weak p-3">
      <div class="flex items-center justify-between gap-3">
        <span class="text-sm font-medium text-n-slate-12">{{ channel.name }}</span>
        <Button size="xs" variant="faded" :label="t('ARROYO.SOCIAL_COMMENTS.CONFIGURE')" @click="edit(channel)" />
      </div>
      <form v-if="edits[channel.id]" class="mt-3 flex flex-col gap-3" @submit.prevent="save(channel)">
        <label class="text-xs text-n-slate-11">{{ t('ARROYO.SOCIAL_COMMENTS.ACCOUNT_ID') }}
          <input v-model="edits[channel.id].external_account_id" class="mb-0 mt-1" autocomplete="off" />
        </label>
        <label class="text-xs text-n-slate-11">{{ t('ARROYO.SOCIAL_COMMENTS.API_VERSION') }}
          <input v-model="edits[channel.id].api_version" class="mb-0 mt-1" autocomplete="off" />
        </label>
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <input v-model="edits[channel.id].publishing_enabled" type="checkbox" class="m-0" />
          {{ t('ARROYO.SOCIAL_COMMENTS.ENABLE_PUBLISHING') }}
        </label>
        <p class="m-0 text-xs text-n-slate-11">{{ t('ARROYO.SOCIAL_COMMENTS.ENABLE_WARNING') }}</p>
        <Button type="submit" size="sm" :disabled="busy" :label="t('ARROYO.SOCIAL_COMMENTS.SAVE')" />
      </form>
    </div>
    <form class="mt-4 flex flex-col gap-3" @submit.prevent="create">
      <div class="grid gap-3 sm:grid-cols-2">
        <label class="text-xs text-n-slate-11">{{ t('ARROYO.SOCIAL_COMMENTS.NETWORK') }}
          <select v-model="form.platform" class="mb-0 mt-1"><option value="instagram">Instagram</option><option value="facebook">Facebook</option></select>
        </label>
        <label class="text-xs text-n-slate-11">{{ t('ARROYO.SOCIAL_COMMENTS.INBOX_NAME') }}
          <input v-model="form.name" class="mb-0 mt-1" />
        </label>
      </div>
      <fieldset>
        <legend class="text-xs text-n-slate-11">{{ t('ARROYO.SOCIAL_COMMENTS.SELLERS') }}</legend>
        <div class="mt-2 flex flex-wrap gap-3">
          <label v-for="agent in agents" :key="agent.id" class="flex items-center gap-2 text-sm text-n-slate-12">
            <input v-model="form.user_ids" type="checkbox" :value="agent.id" class="m-0" />{{ agent.name }}
          </label>
        </div>
      </fieldset>
      <Button type="submit" size="sm" icon="i-lucide-plus" :disabled="busy || !hasMembers" :label="t('ARROYO.SOCIAL_COMMENTS.CREATE_INBOX')" />
    </form>
  </section>
</template>

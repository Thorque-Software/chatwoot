<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import ArroyoSettingsAPI from '../api/settings';
import { useArroyoFeatures } from '../composables/useArroyoFeatures';
import GeneralSection from './components/GeneralSection.vue';
import WindowKeeperSection from './components/WindowKeeperSection.vue';
import PostSaleSection from './components/PostSaleSection.vue';
import AgentPanelSection from './components/AgentPanelSection.vue';
import EmailMarketingSection from './components/EmailMarketingSection.vue';
import SocialCommentsSection from './components/SocialCommentsSection.vue';

const { t } = useI18n();
const store = useStore();
const { fetchFeatures } = useArroyoFeatures();
const config = ref(null);
const isLoading = ref(true);
const savingSection = ref('');

const fetchConfig = async () => {
  try {
    const { data } = await ArroyoSettingsAPI.get();
    config.value = data.config;
  } catch (error) {
    useAlert(t('ARROYO.SETTINGS.API.FETCH_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const saveSection = async (section, changes) => {
  savingSection.value = section;
  try {
    const { data } = await ArroyoSettingsAPI.updateConfig(changes);
    config.value = data.config;
    fetchFeatures();
    useAlert(t('ARROYO.SETTINGS.API.SUCCESS'));
  } catch (error) {
    const errors = error?.response?.data?.errors;
    useAlert(
      errors?.length ? errors.join(', ') : t('ARROYO.SETTINGS.API.ERROR')
    );
  } finally {
    savingSection.value = '';
  }
};

onMounted(() => {
  store.dispatch('agents/get');
  fetchConfig();
});
</script>

<template>
  <SettingsLayout :is-loading="isLoading" :no-records-found="false">
    <template #header>
      <BaseSettingsHeader
        :title="t('ARROYO.SETTINGS.HEADER.TITLE')"
        :description="t('ARROYO.SETTINGS.HEADER.DESCRIPTION')"
      />
    </template>
    <template #body>
      <div v-if="config" class="flex flex-col gap-6 mt-4">
        <GeneralSection
          :timezone="config.timezone"
          :is-saving="savingSection === 'general'"
          @save="saveSection('general', $event)"
        />
        <WindowKeeperSection
          :config="config.window_keeper"
          :is-saving="savingSection === 'window_keeper'"
          @save="saveSection('window_keeper', $event)"
        />
        <PostSaleSection
          :config="config.post_sale"
          :is-saving="savingSection === 'post_sale'"
          @save="saveSection('post_sale', $event)"
        />
        <AgentPanelSection
          :config="config.agent_panel"
          :is-saving="savingSection === 'agent_panel'"
          @save="saveSection('agent_panel', $event)"
        />
        <EmailMarketingSection
          :config="config.email_marketing"
          :is-saving="savingSection === 'email_marketing'"
          @save="saveSection('email_marketing', $event)"
        />
        <SocialCommentsSection
          :config="config.social_comments"
          :is-saving="savingSection === 'social_comments'"
          @save="saveSection('social_comments', $event)"
        />
      </div>
    </template>
  </SettingsLayout>
</template>

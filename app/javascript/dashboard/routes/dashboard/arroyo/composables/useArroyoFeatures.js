import { ref, computed } from 'vue';
import ArroyoFeaturesAPI from '../api/features';

// Estado compartido: el sidebar y las pantallas Arroyo leen los mismos flags
const features = ref(null);

export function useArroyoFeatures() {
  const fetchFeatures = async () => {
    try {
      const { data } = await ArroyoFeaturesAPI.get();
      features.value = data;
    } catch (error) {
      features.value = null;
    }
  };

  return {
    features,
    fetchFeatures,
    timezone: computed(() => features.value?.timezone),
    isAgentPanelEnabled: computed(() =>
      Boolean(features.value?.agent_panel?.enabled)
    ),
    isPostSaleVisible: computed(() =>
      Boolean(
        features.value?.post_sale?.enabled ||
          features.value?.post_sale?.has_records
      )
    ),
    hideNativeReports: computed(() =>
      Boolean(
        features.value?.agent_panel?.enabled &&
          features.value?.agent_panel?.hide_native_reports
      )
    ),
  };
}

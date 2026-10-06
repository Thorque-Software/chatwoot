import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

export function useMetricLabels() {
  const { t } = useI18n();

  return computed(() => ({
    conversations_attended: t('ARROYO.PANEL.METRICS.CONVERSATIONS_ATTENDED'),
    messages_sent: t('ARROYO.PANEL.METRICS.MESSAGES_SENT'),
    assignments: t('ARROYO.PANEL.METRICS.ASSIGNMENTS'),
    first_response_median: t('ARROYO.PANEL.METRICS.FIRST_RESPONSE_MEDIAN'),
    windows_closed: t('ARROYO.PANEL.METRICS.WINDOWS_CLOSED'),
    sales: t('ARROYO.PANEL.METRICS.SALES'),
  }));
}

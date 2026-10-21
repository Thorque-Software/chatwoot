import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

export const useCommercialLabels = () => {
  const { t } = useI18n();
  return computed(() => ({
    received: t('ARROYO.PANEL.FUNNEL.METRICS.RECEIVED'),
    bot: t('ARROYO.PANEL.FUNNEL.METRICS.BOT'),
    unassigned: t('ARROYO.PANEL.FUNNEL.METRICS.UNASSIGNED'),
    pending: t('ARROYO.PANEL.FUNNEL.METRICS.PENDING'),
    attended: t('ARROYO.PANEL.FUNNEL.METRICS.ATTENDED'),
    in_progress: t('ARROYO.PANEL.FUNNEL.METRICS.IN_PROGRESS'),
    won: t('ARROYO.PANEL.FUNNEL.METRICS.WON'),
    lost: t('ARROYO.PANEL.FUNNEL.METRICS.LOST'),
    inactive: t('ARROYO.PANEL.FUNNEL.METRICS.INACTIVE'),
    unknown: t('ARROYO.PANEL.FUNNEL.METRICS.UNKNOWN'),
    overdue: t('ARROYO.PANEL.FUNNEL.METRICS.OVERDUE'),
    assigned: t('ARROYO.PANEL.FUNNEL.METRICS.ASSIGNED'),
    repeat_sales: t('ARROYO.PANEL.FUNNEL.METRICS.REPEAT_SALES'),
    post_sale_replies: t('ARROYO.PANEL.FUNNEL.METRICS.POST_SALE_REPLIES'),
    post_sale_issues: t('ARROYO.PANEL.FUNNEL.METRICS.POST_SALE_ISSUES'),
  }));
};

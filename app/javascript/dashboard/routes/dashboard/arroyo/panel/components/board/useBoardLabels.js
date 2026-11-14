import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

export const COUNTERS = [
  'received',
  'attended',
  'pending',
  'in_progress',
  'inactive',
  'abandoned',
  'lost',
  'won',
];

// Textos del embudo del panel: estados, contadores y nodos del gráfico.
export const useBoardLabels = () => {
  const { t } = useI18n();
  const stages = computed(() => ({
    bot: t('ARROYO.PANEL.BOARD.STAGES.BOT'),
    unassigned: t('ARROYO.PANEL.BOARD.STAGES.UNASSIGNED'),
    pending: t('ARROYO.PANEL.BOARD.STAGES.PENDING'),
    in_progress: t('ARROYO.PANEL.BOARD.STAGES.IN_PROGRESS'),
    inactive: t('ARROYO.PANEL.BOARD.STAGES.INACTIVE'),
    abandoned: t('ARROYO.PANEL.BOARD.STAGES.ABANDONED'),
    lost: t('ARROYO.PANEL.BOARD.STAGES.LOST'),
    won: t('ARROYO.PANEL.BOARD.STAGES.WON'),
  }));
  const counters = computed(() => ({
    received: t('ARROYO.PANEL.BOARD.COUNTERS.RECEIVED'),
    attended: t('ARROYO.PANEL.BOARD.COUNTERS.ATTENDED'),
    pending: t('ARROYO.PANEL.BOARD.COUNTERS.PENDING'),
    in_progress: t('ARROYO.PANEL.BOARD.COUNTERS.IN_PROGRESS'),
    inactive: t('ARROYO.PANEL.BOARD.COUNTERS.INACTIVE'),
    abandoned: t('ARROYO.PANEL.BOARD.COUNTERS.ABANDONED'),
    lost: t('ARROYO.PANEL.BOARD.COUNTERS.LOST'),
    won: t('ARROYO.PANEL.BOARD.COUNTERS.WON'),
  }));
  const nodeLabel = node => {
    if (node.kind === 'origin') {
      if (node.key === 'organic') return t('ARROYO.PANEL.BOARD.FLOW.ORGANIC');
      if (node.key === 'other') return t('ARROYO.PANEL.BOARD.FLOW.OTHER');
      return node.label || node.key;
    }
    if (node.kind === 'stage') return stages.value[node.key] || node.key;
    if (node.kind === 'seller') return node.label || `#${node.key}`;
    return stages.value[node.kind] || node.key;
  };
  return { stages, counters, nodeLabel };
};

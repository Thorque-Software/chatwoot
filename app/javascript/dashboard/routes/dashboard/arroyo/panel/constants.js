// Deben coincidir con Arroyo::AgentPanel::Filters::METRICS
export const METRICS = [
  'conversations_attended',
  'messages_sent',
  'assignments',
  'first_response_median',
  'windows_closed',
  'sales',
];
export const TIME_METRICS = ['first_response_median'];
export const MAIN_METRIC = 'conversations_attended';
export const DATE_PRESETS = [
  'today',
  'yesterday',
  'last_7_days',
  'this_month',
  'last_month',
  'custom',
];
export const DEFAULT_PRESET = 'last_7_days';
export const GROUP_BY_OPTIONS = ['day', 'week'];
export const TABS = ['activity', 'windows', 'post_sale'];
export const POST_SALE_STATUSES = [
  'awaiting_plan',
  'scheduled',
  'queued',
  'sent',
  'delivered',
  'read',
  'failed',
  'unconfirmed',
  'not_executed',
  'cancelled',
];
export const CHART_COLOR = 'rgb(31, 147, 255)';

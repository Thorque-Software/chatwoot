import { frontendURL } from 'dashboard/helper/URLHelper';
import Index from './Index.vue';

export default {
  routes: [
    { path: 'panel', name: 'arroyo_agent_panel', tab: 'activity' },
    { path: 'seguimientos', name: 'arroyo_follow_ups', tab: 'windows' },
    { path: 'postventa', name: 'arroyo_post_sale', tab: 'post_sale' },
    {
      path: 'seguimiento-comercial',
      name: 'arroyo_commercial_follow_ups',
      tab: 'follow_ups',
    },
  ].map(({ path, name, tab }) => ({
    path: frontendURL(`accounts/:accountId/arroyo/${path}`),
    name,
    component: Index,
    meta: {
      permissions: ['administrator', 'agent'],
      arroyoTab: tab,
    },
  })),
};

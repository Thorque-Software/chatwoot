import { frontendURL } from 'dashboard/helper/URLHelper';
import Index from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/arroyo/panel'),
      name: 'arroyo_agent_panel',
      component: Index,
      meta: {
        permissions: ['administrator', 'agent'],
      },
    },
  ],
};

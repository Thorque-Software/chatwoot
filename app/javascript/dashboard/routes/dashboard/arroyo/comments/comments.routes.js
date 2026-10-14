import { frontendURL } from 'dashboard/helper/URLHelper';
import Index from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/arroyo/comments'),
      name: 'arroyo_social_comments',
      component: Index,
      meta: { permissions: ['administrator', 'agent'] },
    },
  ],
};

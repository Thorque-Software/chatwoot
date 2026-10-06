import { frontendURL } from 'dashboard/helper/URLHelper';
import SettingsWrapper from 'dashboard/routes/dashboard/settings/SettingsWrapper.vue';
import Index from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/arroyo'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'arroyo_settings_index',
          component: Index,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};

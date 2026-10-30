import { frontendURL } from 'dashboard/helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import ConnectaSettings from './ConnectaSettings.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/connecta'),
      component: SettingsWrapper,
      props: {
        headerTitle: 'CONNECTA.SETTINGS.TITLE',
        icon: 'i-lucide-shield-check',
        showNewButton: false,
      },
      children: [
        {
          path: '',
          name: 'connecta_settings',
          component: ConnectaSettings,
          meta: { permissions: ['administrator', 'agent', 'custom_role'] },
        },
      ],
    },
  ],
};

import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createRouter, createMemoryHistory } from 'vue-router';
import Index from '../Index.vue';
import SocialCommentsAPI from '../../api/socialComments';
import FeaturesAPI from '../../api/features';

vi.mock('vue-i18n', async importOriginal => ({
  ...(await importOriginal()),
  useI18n: () => ({ t: key => key }),
}));

describe('Comments overview', () => {
  afterEach(() => vi.restoreAllMocks());

  it('renders a pending connection, opens the native conversation and sends both filters to the API', async () => {
    vi.spyOn(FeaturesAPI, 'get').mockResolvedValue({
      data: { social_comments: { enabled: true, inboxes: [{ inbox_id: 12 }] } },
    });
    vi.spyOn(SocialCommentsAPI, 'channels').mockResolvedValue({
      data: { channels: [{ id: 1, name: 'Instagram', ready: false }] },
    });
    vi.spyOn(SocialCommentsAPI, 'comments').mockResolvedValue({
      data: {
        total: 1,
        next_page: null,
        comments: [
          {
            id: 1,
            author_name: 'Cliente de ejemplo',
            platform: 'instagram',
            body: '¿Tienen disponibilidad?',
            conversation_id: 42,
            media_id: '123',
            replies: [],
          },
        ],
      },
    });
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        {
          path: '/app/accounts/:accountId/arroyo/comments',
          component: { template: '<div />' },
        },
        {
          path: '/app/accounts/:accountId/conversations/:conversation_id',
          name: 'inbox_conversation',
          component: { template: '<div />' },
        },
      ],
    });
    await router.push('/app/accounts/1/arroyo/comments');
    const store = createStore({
      getters: { getCurrentRole: () => 'agent' },
      modules: {
        agents: {
          namespaced: true,
          actions: { get: vi.fn() },
          getters: { getAgents: () => [] },
        },
      },
    });
    const wrapper = mount(Index, { global: { plugins: [router, store] } });
    await flushPromises();
    expect(wrapper.text()).toContain('Cliente de ejemplo');
    expect(wrapper.text()).toContain(
      'ARROYO.SOCIAL_COMMENTS.CONNECTION_PENDING'
    );
    expect(wrapper.find('a').attributes('href')).toBe(
      '/app/accounts/1/conversations/42'
    );
    await wrapper.findAll('select')[0].setValue('instagram');
    await wrapper.findAll('select')[1].setValue('failed');
    await flushPromises();
    expect(SocialCommentsAPI.comments).toHaveBeenLastCalledWith({
      platform: 'instagram',
      status: 'failed',
      page: 1,
    });
  });
});

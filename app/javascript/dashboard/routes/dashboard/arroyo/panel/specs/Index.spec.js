import { mount, flushPromises } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import { createStore } from 'vuex';
import Index from '../Index.vue';
import PanelFilters from '../components/PanelFilters.vue';
import ArroyoAgentPanelAPI from '../../api/agentPanel';
import ArroyoFeaturesAPI from '../../api/features';
import PostSaleAPI from '../../api/postSale';
import PostSaleTab from '../components/PostSaleTab.vue';
import { useArroyoFeatures } from '../../composables/useArroyoFeatures';

const metrics = values => ({
  conversations_attended: 0,
  messages_sent: 0,
  assignments: 0,
  first_response_median: null,
  windows_closed: 0,
  sales: 0,
  ...values,
});

const report = {
  timezone: 'America/Argentina/Buenos_Aires',
  since: '2026-10-01',
  until: '2026-10-02',
  group_by: 'day',
  periods: ['2026-10-01', '2026-10-02'],
  totals: metrics({ conversations_attended: 3, first_response_median: 90 }),
  agents: [
    {
      id: 7,
      name: 'Julieta',
      totals: metrics({ conversations_attended: 3 }),
      periods: {
        '2026-10-01': metrics({ conversations_attended: 2 }),
        '2026-10-02': metrics({ conversations_attended: 1 }),
      },
    },
  ],
};

const conversation = {
  id: 11,
  display_id: 42,
  status: 'open',
  contact: { id: 1, name: 'Cliente Arroyo', phone_number: '+5491100000000' },
  inbox: { id: 3, name: 'WhatsApp' },
  assignee: { id: 7, name: 'Julieta' },
  last_message: {
    content: 'Te paso el precio',
    message_type: 'outgoing',
    created_at: 1,
  },
  last_activity_at: 1,
};

const mountPanel = async query => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        path: '/app/accounts/:accountId/arroyo/panel',
        name: 'arroyo_agent_panel',
        component: Index,
      },
      { path: '/:pathMatch(.*)*', component: { template: '<div />' } },
    ],
  });
  await router.push({ path: '/app/accounts/1/arroyo/panel', query });
  const store = createStore({
    getters: { getCurrentRole: () => 'administrator' },
    modules: {
      agents: {
        namespaced: true,
        getters: { getAgents: () => [{ id: 7, name: 'Julieta' }] },
        actions: { get: () => {} },
      },
      inboxes: {
        namespaced: true,
        getters: { getInboxes: () => [{ id: 3, name: 'WhatsApp' }] },
      },
    },
  });
  const wrapper = mount(Index, {
    global: {
      plugins: [router, store],
      stubs: { BarChart: true, TabBar: true },
    },
  });
  await flushPromises();
  return { wrapper, router };
};

describe('Arroyo agent panel', () => {
  beforeEach(() => {
    useArroyoFeatures().features.value = null;
    vi.spyOn(ArroyoFeaturesAPI, 'get').mockResolvedValue({
      data: {
        timezone: 'America/Argentina/Buenos_Aires',
        agent_panel: { enabled: true, agents_see_only_own: true },
      },
    });
    vi.spyOn(ArroyoAgentPanelAPI, 'getReport').mockResolvedValue({
      data: report,
    });
    vi.spyOn(ArroyoAgentPanelAPI, 'getConversations').mockResolvedValue({
      data: { count: 1, conversations: [conversation] },
    });
    vi.spyOn(PostSaleAPI, 'getFollowUps').mockResolvedValue({
      data: { follow_ups: [], totals: {} },
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('loads the report with the filters from the URL', async () => {
    await mountPanel({
      preset: 'custom',
      since: '2026-10-01',
      until: '2026-10-02',
      user_ids: '7',
      inbox_ids: '3',
    });

    expect(ArroyoAgentPanelAPI.getReport).toHaveBeenCalledWith({
      since: '2026-10-01',
      until: '2026-10-02',
      group_by: 'day',
      user_ids: [7],
      inbox_ids: [3],
    });
  });

  it('shows enabled post-sale and keeps the shared date and inbox filters', async () => {
    ArroyoFeaturesAPI.get.mockResolvedValue({
      data: {
        timezone: 'America/Argentina/Buenos_Aires',
        agent_panel: { enabled: true, agents_see_only_own: true },
        post_sale: { enabled: true },
      },
    });
    const { wrapper } = await mountPanel({
      tab: 'post_sale',
      preset: 'custom',
      since: '2026-10-01',
      until: '2026-10-13',
      inbox_ids: '3',
    });
    expect(wrapper.findComponent(PostSaleTab).exists()).toBe(true);
    expect(wrapper.findComponent(PanelFilters).props('showDateFilters')).toBe(
      true
    );
    expect(wrapper.findComponent(PanelFilters).props('showGroupBy')).toBe(
      false
    );
    expect(PostSaleAPI.getFollowUps).toHaveBeenCalledWith(
      expect.objectContaining({
        since: '2026-10-01',
        until: '2026-10-13',
        inbox_ids: [3],
      })
    );
    expect(PostSaleAPI.getFollowUps.mock.calls[0][0]).not.toHaveProperty(
      'group_by'
    );
    expect(ArroyoAgentPanelAPI.getReport).not.toHaveBeenCalled();
  });

  it('falls back to activity when the post-sale flag is off', async () => {
    ArroyoFeaturesAPI.get.mockResolvedValue({
      data: {
        timezone: 'America/Argentina/Buenos_Aires',
        agent_panel: { enabled: true },
        post_sale: { enabled: false, has_records: false },
      },
    });
    const { wrapper } = await mountPanel({ tab: 'post_sale' });
    expect(wrapper.findComponent(PostSaleTab).exists()).toBe(false);
    expect(PostSaleAPI.getFollowUps).not.toHaveBeenCalled();
  });

  it('keeps history visible and permits manual resolution after disabling the integration', async () => {
    ArroyoFeaturesAPI.get.mockResolvedValue({
      data: {
        timezone: 'America/Argentina/Buenos_Aires',
        agent_panel: { enabled: true },
        post_sale: { enabled: false, has_records: true },
      },
    });
    const item = {
      id: 12,
      stage: 'd1',
      status: 'failed',
      manual_status: 'pending',
      can_resolve: true,
      purchase: {
        reference: 'purchase-1',
        purchased_at: '2026-10-06T15:00:00Z',
        seller: { id: 7, name: 'Julieta' },
        conversation_id: 42,
        contact: { id: 1, name: 'Cliente Arroyo' },
        can_edit_purchase: true,
      },
      message: null,
    };
    PostSaleAPI.getFollowUps.mockResolvedValue({
      data: { follow_ups: [item], totals: {} },
    });
    vi.spyOn(PostSaleAPI, 'resolve').mockResolvedValue({ data: {} });
    const { wrapper } = await mountPanel({ tab: 'post_sale' });
    expect(wrapper.findComponent(PostSaleTab).exists()).toBe(true);
    expect(wrapper.find('[data-testid="post-sale-disabled"]').text()).toContain(
      'integration is disabled'
    );
    await wrapper.find('[data-testid="follow-up-12"]').trigger('click');
    await flushPromises();
    expect(
      wrapper.find('[data-testid="purchase-date-save"]').attributes('disabled')
    ).toBeUndefined();
    await wrapper
      .find('[data-testid="resolution-note"] textarea')
      .setValue('Contactado por llamada');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(PostSaleAPI.resolve).toHaveBeenCalledWith(12, {
      method: 'call',
      note: 'Contactado por llamada',
    });
  });

  it('writes filter changes to the URL and reloads', async () => {
    const { wrapper, router } = await mountPanel({
      preset: 'custom',
      since: '2026-10-01',
      until: '2026-10-02',
    });

    wrapper.findComponent(PanelFilters).vm.$emit('change', {
      groupBy: 'week',
      userIds: [7],
    });
    await flushPromises();

    expect(router.currentRoute.value.query).toMatchObject({
      preset: 'custom',
      since: '2026-10-01',
      group_by: 'week',
      user_ids: '7',
    });
    expect(ArroyoAgentPanelAPI.getReport).toHaveBeenLastCalledWith(
      expect.objectContaining({ group_by: 'week', user_ids: [7] })
    );
  });

  it('opens the conversations behind a cell in the drawer', async () => {
    const { wrapper } = await mountPanel({
      preset: 'custom',
      since: '2026-10-01',
      until: '2026-10-02',
    });

    await wrapper.find('[data-testid="cell-7-2026-10-01"]').trigger('click');
    await flushPromises();

    expect(ArroyoAgentPanelAPI.getConversations).toHaveBeenCalledWith(
      expect.objectContaining({
        metric: 'conversations_attended',
        since: '2026-10-01',
        until: '2026-10-01',
        user_ids: [7],
      })
    );
    const drawer = wrapper.find('aside');
    expect(drawer.text()).toContain('Cliente Arroyo');
    expect(drawer.text()).toContain('Te paso el precio');
    expect(drawer.find('a').attributes('href')).toBe(
      '/app/accounts/1/conversations/42'
    );
  });
});

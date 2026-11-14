import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import { createStore } from 'vuex';
import FunnelBoard from '../components/board/FunnelBoard.vue';
import BoardAPI from '../../api/board';
import CommercialAPI from '../../api/commercial';

vi.mock('dashboard/helper/downloadHelper', () => ({
  downloadCsvFile: vi.fn(),
}));

enableAutoUnmount(afterEach);

const counts = (overrides = {}) => ({
  received: 0,
  attended: 0,
  pending: 0,
  in_progress: 0,
  inactive: 0,
  abandoned: 0,
  lost: 0,
  won: 0,
  ...overrides,
});
const board = {
  version: 1,
  timezone: 'America/Argentina/Buenos_Aires',
  as_of: '2026-11-12T21:00:00Z',
  since: '2026-11-10',
  until: '2026-11-12',
  origin_level: 'campaign',
  inboxes: [{ id: 2, name: 'Arroyo' }],
  totals: {
    ...counts({ received: 5, attended: 3, pending: 1, abandoned: 1, won: 1 }),
    from_ads: 3,
    organic: 2,
    bot: 1,
    unassigned: 0,
    assigned: 4,
    nudged: 2,
  },
  flow: {
    nodes: [
      {
        id: 'origin:campaign:c1',
        column: 0,
        kind: 'origin',
        key: 'campaign:c1',
        label: 'Bicis Rosario',
        value: 3,
      },
      {
        id: 'origin:organic',
        column: 0,
        kind: 'origin',
        key: 'organic',
        label: null,
        value: 2,
      },
      {
        id: 'bucket:7',
        column: 1,
        kind: 'seller',
        key: '7',
        label: 'Julieta',
        value: 4,
      },
      {
        id: 'bucket:bot',
        column: 1,
        kind: 'bot',
        key: 'bot',
        label: null,
        value: 1,
      },
      {
        id: 'stage:pending',
        column: 2,
        kind: 'stage',
        key: 'pending',
        label: null,
        value: 1,
      },
      {
        id: 'stage:won',
        column: 2,
        kind: 'stage',
        key: 'won',
        label: null,
        value: 3,
      },
    ],
    links: [
      { source: 'origin:campaign:c1', target: 'bucket:7', value: 3 },
      { source: 'origin:organic', target: 'bucket:7', value: 1 },
      { source: 'origin:organic', target: 'bucket:bot', value: 1 },
      { source: 'bucket:7', target: 'stage:pending', value: 1 },
      { source: 'bucket:7', target: 'stage:won', value: 3 },
    ],
  },
  info_labels: [{ label: 'cotizado', count: 2 }],
  sellers: [
    {
      id: 7,
      name: 'Julieta',
      ...counts({ received: 4, attended: 3, pending: 1, won: 1 }),
    },
  ],
  days: [
    {
      date: '2026-11-10',
      total: counts({ received: 2 }),
      sellers: { 7: counts({ received: 2 }) },
    },
    {
      date: '2026-11-11',
      total: counts({ received: 3, won: 1 }),
      sellers: { 7: counts({ received: 2, won: 1 }) },
    },
  ],
  origins: [
    {
      key: 'campaign:c1',
      kind: 'campaign',
      name: 'Bicis Rosario',
      received: 3,
      attended: 2,
      won: 1,
      lost: 0,
      ads: [
        {
          key: 'ad:1',
          name: 'Reel Bici',
          received: 3,
          attended: 2,
          won: 1,
          lost: 0,
        },
      ],
    },
    {
      key: 'organic',
      kind: 'organic',
      name: 'organic',
      received: 2,
      attended: 1,
      won: 0,
      lost: 0,
      ads: [],
    },
  ],
  repurchases: { repeat_sales: 1, post_sale_replies: 2 },
  post_sale_issues: {
    count: 1,
    items: [
      {
        id: 9,
        stage: 'd7',
        status: 'failed',
        scheduled_at: '2026-11-11T13:00:00Z',
        error: 'Plantilla pausada',
        product: 'Bici R29',
        seller: 'Julieta',
        conversation_id: 42,
        contact: 'Juan',
      },
    ],
  },
};
const params = {
  since: '2026-11-10',
  until: '2026-11-12',
  user_ids: undefined,
  inbox_ids: [2],
};

const mountBoard = async () => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/:pathMatch(.*)*', component: { template: '<div />' } }],
  });
  await router.push('/app/accounts/1/arroyo/panel');
  const wrapper = mount(FunnelBoard, {
    props: { params, sellerIds: [7] },
    global: {
      plugins: [
        router,
        createStore({
          getters: {
            'accounts/isRTL': () => false,
            getCurrentAccountId: () => 1,
          },
        }),
      ],
    },
  });
  await flushPromises();
  return wrapper;
};

describe('Arroyo panel funnel board', () => {
  beforeEach(() => {
    vi.spyOn(BoardAPI, 'get').mockResolvedValue({ data: board });
    vi.spyOn(BoardAPI, 'getOpportunities').mockResolvedValue({
      data: { opportunities: [], meta: { total: 0, next_page: null } },
    });
    vi.spyOn(CommercialAPI, 'getOpportunities');
  });
  afterEach(() => vi.restoreAllMocks());

  it('loads the board for the filters and shows the totals and the stuck alert', async () => {
    const wrapper = await mountBoard();

    expect(BoardAPI.get).toHaveBeenCalledWith({
      ...params,
      origin_level: 'campaign',
    });
    expect(wrapper.find('[data-testid="board-kpi-received"]').text()).toContain(
      '5'
    );
    expect(wrapper.find('[data-testid="board-stuck"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="board-info-labels"]').text()).toContain(
      'cotizado'
    );
  });

  it('draws one block per node and opens its inquiries from the board endpoint', async () => {
    const wrapper = await mountBoard();

    expect(wrapper.findAll('[data-testid^="flow-node-"]')).toHaveLength(6);
    await wrapper
      .find('[data-testid="flow-node-stage:pending"]')
      .trigger('click');
    await flushPromises();

    expect(BoardAPI.getOpportunities).toHaveBeenCalledWith(
      expect.objectContaining({
        stage: 'pending',
        since: '2026-11-10',
        page: 1,
      })
    );
    expect(CommercialAPI.getOpportunities).not.toHaveBeenCalled();
  });

  it('opens a day cell of a seller with the day and the chosen counter', async () => {
    const wrapper = await mountBoard();

    await wrapper.find('[data-testid="day-2026-11-11-7"]').trigger('click');
    await flushPromises();

    expect(BoardAPI.getOpportunities).toHaveBeenCalledWith(
      expect.objectContaining({ bucket: '7', date: '2026-11-11' })
    );
  });

  it('reloads grouped by ad when the origin level changes', async () => {
    const wrapper = await mountBoard();

    await wrapper.find('[data-testid="board-level-ad"]').trigger('click');
    await flushPromises();

    expect(BoardAPI.get).toHaveBeenLastCalledWith(
      expect.objectContaining({ origin_level: 'ad' })
    );
  });

  it('expands a campaign into its ads', async () => {
    const wrapper = await mountBoard();

    expect(wrapper.text()).not.toContain('Reel Bici');
    await wrapper
      .find('[data-testid="origin-toggle-campaign:c1"]')
      .trigger('click');
    expect(wrapper.text()).toContain('Reel Bici');
  });
});

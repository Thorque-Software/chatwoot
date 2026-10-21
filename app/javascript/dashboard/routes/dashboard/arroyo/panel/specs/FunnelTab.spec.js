import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import { createStore } from 'vuex';
import FunnelTab from '../components/FunnelTab.vue';
import CommercialAPI from '../../api/commercial';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';

vi.mock('dashboard/helper/downloadHelper', () => ({
  downloadCsvFile: vi.fn(),
}));

enableAutoUnmount(afterEach);

const params = {
  since: '2026-10-01',
  until: '2026-10-08',
  group_by: 'week',
  user_ids: [7],
  inbox_ids: [3],
};
const totals = {
  received: 6,
  assigned: 5,
  bot: 1,
  unassigned: 0,
  pending: 1,
  attended: 4,
  in_progress: 1,
  won: 1,
  lost: 1,
  inactive: 1,
  unknown: 0,
  overdue: 1,
  repeat_sales: 1,
  post_sale_replies: 1,
  post_sale_issues: 1,
};
const report = {
  version: 2,
  timezone: 'America/Argentina/Buenos_Aires',
  as_of: '2026-10-08T18:00:00Z',
  ...params,
  totals,
  activity_totals: { received: 6, assigned: 5, attended: 3, won: 2 },
  coverage: { complete: 5, partial: 1 },
  series: [
    { date: '2026-09-28', received: 4, assigned: 3, attended: 2, won: 1 },
  ],
  agents: [
    {
      id: 7,
      name: 'Julieta',
      totals,
      periods: {
        '2026-09-28': { received: 4, assigned: 3, attended: 2, won: 1 },
      },
    },
  ],
};
const opportunity = (id = 12, state = 'in_progress') => ({
  id,
  reference: `opp-${id}`,
  state,
  overdue: true,
  coverage: 'partial',
  started_at: '2026-10-01T12:00:00Z',
  assignee: { id: 7, name: 'Julieta' },
  conversation: {
    id: 1,
    display_id: 42,
    contact: { name: 'Cliente Arroyo' },
    inbox: { name: 'WhatsApp' },
    assignee: { id: 7, name: 'Julieta' },
    last_message: { content: 'Quiero una bicicleta', created_at: 1 },
    status: 'open',
  },
});
const mountTab = async () => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        path: '/app/accounts/:accountId/arroyo/panel',
        component: { template: '<div />' },
      },
      { path: '/:pathMatch(.*)*', component: { template: '<div />' } },
    ],
  });
  await router.push('/app/accounts/1/arroyo/panel');
  const wrapper = mount(FunnelTab, {
    props: { params },
    global: {
      plugins: [
        router,
        createStore({ getters: { 'accounts/isRTL': () => false } }),
      ],
      stubs: { BarChart: true },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('Arroyo commercial funnel', () => {
  beforeEach(() => {
    vi.spyOn(CommercialAPI, 'getReport').mockResolvedValue({ data: report });
    vi.spyOn(CommercialAPI, 'getOpportunities').mockResolvedValue({
      data: {
        opportunities: [opportunity()],
        meta: { total: 2, next_page: 2 },
      },
    });
    vi.spyOn(CommercialAPI, 'updateOpportunity').mockResolvedValue({
      data: {},
    });
    vi.spyOn(CommercialAPI, 'createOpportunity').mockResolvedValue({
      data: {},
    });
    vi.spyOn(CommercialAPI, 'exportReport').mockResolvedValue({
      data: 'reference,state\nopp-12,won',
    });
  });
  afterEach(() => vi.restoreAllMocks());

  it('preserves the cards, flow and chart while refreshing filters', async () => {
    const wrapper = await mountTab();
    const card = wrapper.get('[data-testid="metric-received"]').element;
    const flow = wrapper.get('[data-testid="cohort-flow"]').element;
    const chart = wrapper.findComponent({ name: 'BarChart' }).vm;
    let resolve;
    CommercialAPI.getReport.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    await wrapper.setProps({ params: { ...params, user_ids: [8] } });
    expect(wrapper.get('[data-testid="metric-received"]').element).toBe(card);
    expect(wrapper.get('[data-testid="cohort-flow"]').element).toBe(flow);
    expect(wrapper.findComponent({ name: 'BarChart' }).vm).toBe(chart);
    expect(wrapper.attributes('aria-busy')).toBe('true');
    expect(
      wrapper.get('[data-testid="funnel-refresh-status"]').text()
    ).toContain('Updating');
    await wrapper.get('[data-testid="metric-received"]').trigger('click');
    expect(CommercialAPI.getOpportunities).not.toHaveBeenCalled();
    resolve({ data: { ...report, totals: { ...totals, received: 10 } } });
    await flushPromises();
    expect(wrapper.get('[data-testid="metric-received"]').element).toBe(card);
    expect(wrapper.get('[data-testid="metric-received"]').text()).toContain(
      '10'
    );
    expect(wrapper.findComponent({ name: 'BarChart' }).vm).toBe(chart);
    expect(wrapper.attributes('aria-busy')).toBe('false');
  });

  it('keeps the previous report on a refresh error without opening or exporting stale filters', async () => {
    const wrapper = await mountTab();
    const card = wrapper.get('[data-testid="metric-received"]').element;
    CommercialAPI.getReport.mockRejectedValueOnce(new Error('offline'));
    await wrapper.setProps({ params: { ...params, user_ids: [8] } });
    await flushPromises();
    expect(wrapper.get('[data-testid="metric-received"]').element).toBe(card);
    expect(wrapper.get('[role="alert"]').text()).toContain('Could not load');
    expect(
      wrapper.get('[data-testid="funnel-refresh-status"]').text()
    ).toContain('previous');
    await wrapper.get('[data-testid="metric-received"]').trigger('click');
    await wrapper.get('[data-testid="funnel-export"]').trigger('click');
    expect(CommercialAPI.getOpportunities).not.toHaveBeenCalled();
    expect(CommercialAPI.exportReport).not.toHaveBeenCalled();
    await wrapper.get('[data-testid="funnel-retry"]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-testid="metric-received"]').trigger('click');
    await flushPromises();
    expect(CommercialAPI.getOpportunities).toHaveBeenCalledWith(
      expect.objectContaining({ user_ids: [8] })
    );
  });

  it('ignores an older refresh response after a newer filter has finished', async () => {
    const wrapper = await mountTab();
    let resolveOld;
    let resolveLatest;
    CommercialAPI.getReport
      .mockImplementationOnce(
        () =>
          new Promise(done => {
            resolveOld = done;
          })
      )
      .mockImplementationOnce(
        () =>
          new Promise(done => {
            resolveLatest = done;
          })
      );
    await wrapper.setProps({ params: { ...params, user_ids: [8] } });
    await wrapper.setProps({ params: { ...params, user_ids: [9] } });
    resolveLatest({ data: { ...report, totals: { ...totals, received: 20 } } });
    await flushPromises();
    resolveOld({ data: { ...report, totals: { ...totals, received: 99 } } });
    await flushPromises();
    expect(wrapper.get('[data-testid="metric-received"]').text()).toContain(
      '20'
    );
    expect(wrapper.attributes('aria-busy')).toBe('false');
    await wrapper.get('[data-testid="metric-received"]').trigger('click');
    await flushPromises();
    expect(CommercialAPI.getOpportunities).toHaveBeenCalledWith(
      expect.objectContaining({ user_ids: [9] })
    );
  });

  it('exports exactly the report filters and selected drilldown filters', async () => {
    const wrapper = await mountTab();
    await wrapper.get('[data-testid="funnel-export"]').trigger('click');
    await flushPromises();
    expect(CommercialAPI.exportReport).toHaveBeenLastCalledWith({
      ...params,
      metric: 'received',
      scope: 'cohort',
    });
    expect(downloadCsvFile).toHaveBeenCalledWith(
      'consultas_2026-10-01_2026-10-08.csv',
      'reference,state\nopp-12,won'
    );
    await wrapper.get('[data-testid="activity-7-2026-09-28"]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-testid="opportunities-export"]').trigger('click');
    await flushPromises();
    expect(CommercialAPI.exportReport).toHaveBeenLastCalledWith({
      ...params,
      since: '2026-10-01',
      until: '2026-10-04',
      metric: 'attended',
      scope: 'activity',
    });
  });

  it('resumes inactive inquiries without creating another opportunity and shows permission errors', async () => {
    CommercialAPI.getOpportunities.mockResolvedValue({
      data: {
        opportunities: [opportunity(12, 'inactive')],
        meta: { total: 1, next_page: null },
      },
    });
    CommercialAPI.updateOpportunity.mockRejectedValueOnce({
      response: { data: { errors: ['Permission denied'] } },
    });
    const wrapper = await mountTab();
    await wrapper.get('[data-testid="state-inactive"]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-testid="opportunity-12-resume"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('aside [role="alert"]').text()).toBe(
      'Permission denied'
    );
    await wrapper.get('[data-testid="opportunity-12-resume"]').trigger('click');
    await flushPromises();
    expect(CommercialAPI.updateOpportunity).toHaveBeenLastCalledWith(12, {
      outcome: 'resume',
    });
    expect(CommercialAPI.createOpportunity).not.toHaveBeenCalled();
  });

  it('keeps cohort states and attention incidents separate and displays coverage', async () => {
    const wrapper = await mountTab();
    expect(CommercialAPI.getReport).toHaveBeenCalledWith(params);
    expect(wrapper.get('[data-testid="cohort-states"]').text()).toContain(
      'Won'
    );
    expect(wrapper.get('[data-testid="cohort-states"]').text()).not.toContain(
      'Seller response overdue'
    );
    expect(wrapper.get('[data-testid="coverage"]').text()).toContain('1');
    await wrapper.get('[data-testid="metric-overdue"]').trigger('click');
    await flushPromises();
    expect(CommercialAPI.getOpportunities).toHaveBeenCalledWith({
      ...params,
      metric: 'overdue',
      scope: 'cohort',
      page: 1,
    });
    expect(wrapper.get('aside').text()).toContain('Cliente Arroyo');
    expect(wrapper.get('aside a').attributes('href')).toBe(
      '/app/accounts/1/conversations/42'
    );
  });

  it('shares the activity metric across chart, daily table and clipped weekly drilldown', async () => {
    const wrapper = await mountTab();
    await wrapper.get('[data-testid="activity-metric"] select').setValue('won');
    await wrapper.get('[data-testid="activity-7-2026-09-28"]').trigger('click');
    await flushPromises();
    expect(CommercialAPI.getOpportunities).toHaveBeenLastCalledWith({
      ...params,
      since: '2026-10-01',
      until: '2026-10-04',
      user_ids: [7],
      metric: 'won',
      scope: 'activity',
      page: 1,
    });
    expect(
      wrapper.findAllComponents({ name: 'BarChart' }).at(-1).props('collection')
        .datasets[0].data
    ).toEqual([1]);
  });

  it('groups the evolution by seller and opens the clicked seller bar', async () => {
    CommercialAPI.getReport.mockResolvedValue({
      data: {
        ...report,
        agents: [
          ...report.agents,
          {
            id: 8,
            name: 'Marcos',
            totals,
            periods: { '2026-09-28': { attended: 1 } },
          },
        ],
      },
    });
    const wrapper = await mountTab();
    const chart = wrapper.findComponent({ name: 'BarChart' });
    expect(chart.props('collection').datasets.map(item => item.label)).toEqual([
      'Julieta',
      'Marcos',
    ]);
    chart.props('chartOptions').onClick(null, [{ index: 0, datasetIndex: 1 }]);
    await flushPromises();
    expect(CommercialAPI.getOpportunities).toHaveBeenLastCalledWith({
      ...params,
      since: '2026-10-01',
      until: '2026-10-04',
      user_ids: [8],
      metric: 'attended',
      scope: 'activity',
      page: 1,
    });
  });

  it('keeps the daily table available through its mobile disclosure', async () => {
    const wrapper = await mountTab();
    const toggle = wrapper.get('[data-testid="activity-table-toggle"]');
    expect(toggle.attributes('aria-expanded')).toBe('false');
    await toggle.trigger('click');
    expect(toggle.attributes('aria-expanded')).toBe('true');
    expect(wrapper.get('[data-testid="activity-7-2026-09-28"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-testid="agent-summary-table"]').exists()).toBe(
      false
    );
  });

  it('keeps a zero overdue count from looking like an active alert', async () => {
    CommercialAPI.getReport.mockResolvedValue({
      data: { ...report, totals: { ...totals, overdue: 0 } },
    });
    const wrapper = await mountTab();
    expect(wrapper.find('[data-testid="metric-overdue"]').exists()).toBe(false);
    expect(wrapper.get('[data-testid="cohort-flow"]').exists()).toBe(true);
  });

  it('distinguishes no new intake from activity on earlier inquiries', async () => {
    CommercialAPI.getReport.mockResolvedValue({
      data: {
        ...report,
        totals: Object.fromEntries(Object.keys(totals).map(key => [key, 0])),
      },
    });
    const wrapper = await mountTab();
    expect(wrapper.text()).toContain('No inquiries started');
    expect(wrapper.get('[data-testid="activity-total"]').text()).toContain('3');
  });

  it('explains sale attribution instead of claiming every metric is a reply', async () => {
    const wrapper = await mountTab();
    await wrapper.get('[data-testid="activity-metric"] select').setValue('won');
    const help = wrapper
      .findAllComponents({ name: 'FunnelHelp' })
      .find(item => item.props('title').includes('date'));
    expect(help.props('text')).toContain('sale was recorded');
    expect(help.props('text')).toContain('distinct inquiries');
    expect(help.props('text')).not.toContain('they answered');
  });

  it('paginates the filtered list and reloads the report after a sale', async () => {
    const wrapper = await mountTab();
    await wrapper.get('[data-testid="metric-received"]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-testid="opportunities-next"]').trigger('click');
    await flushPromises();
    expect(CommercialAPI.getOpportunities).toHaveBeenLastCalledWith(
      expect.objectContaining({ page: 2, metric: 'received' })
    );
    await wrapper.get('[data-testid="opportunity-12-won"]').trigger('click');
    await flushPromises();
    expect(CommercialAPI.updateOpportunity).toHaveBeenCalledWith(12, {
      outcome: 'won',
    });
    expect(CommercialAPI.getReport).toHaveBeenCalledTimes(2);
  });

  it('requires explicit confirmation before starting a new opportunity in a sold chat', async () => {
    CommercialAPI.getOpportunities.mockResolvedValue({
      data: {
        opportunities: [opportunity(12, 'won')],
        meta: { total: 1, next_page: null },
      },
    });
    const wrapper = await mountTab();
    await wrapper.get('[data-testid="metric-won"]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-testid="opportunity-12-new"]').trigger('click');
    expect(CommercialAPI.createOpportunity).not.toHaveBeenCalled();
    await wrapper
      .get('[data-testid="opportunity-12-confirm"]')
      .trigger('click');
    await flushPromises();
    expect(CommercialAPI.createOpportunity).toHaveBeenCalledWith(
      expect.objectContaining({
        conversation_id: 42,
        request_key: expect.any(String),
      })
    );
  });

  it('shows a retry on report failure and loads an empty report successfully', async () => {
    CommercialAPI.getReport.mockRejectedValueOnce(new Error('offline'));
    const wrapper = await mountTab();
    expect(wrapper.get('[role="alert"]').text()).toContain('Could not load');
    CommercialAPI.getReport.mockResolvedValue({
      data: {
        ...report,
        agents: [],
        series: [],
        totals: { ...totals, received: 0 },
      },
    });
    await wrapper.get('[data-testid="funnel-retry"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('No inquiries');
  });
});

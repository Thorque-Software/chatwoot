import { mount, flushPromises } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import PostSaleTab from '../components/PostSaleTab.vue';
import PostSaleAPI from '../../api/postSale';

vi.mock('vue-i18n', async importOriginal => ({
  ...(await importOriginal()),
  useI18n: () => ({ t: key => key, locale: { value: 'en' } }),
}));

const followUp = overrides => ({
  id: 12,
  stage: 'd7',
  status: 'unconfirmed',
  scheduled_at: '2026-10-13T13:00:00Z',
  attempted_at: '2026-10-13T13:01:00Z',
  delivered_at: null,
  read_at: null,
  error_code: 'delivery_timeout',
  error_message: 'No delivery confirmation',
  manual_status: 'pending',
  can_resolve: true,
  purchase: {
    reference: 'purchase-1',
    revision: 1,
    purchased_at: '2026-10-06T15:00:00Z',
    product: 'Bicicleta',
    seller: { id: 7, name: 'Julieta' },
    conversation_id: 42,
    contact: { id: 1, name: 'Cliente Arroyo', phone_number: '+5491100000000' },
    can_edit_purchase: true,
  },
  message: {
    id: 90,
    content: '¿Cómo viene tu bicicleta?',
    status: 'sent',
    source_id: 'wamid.1',
    template_params: { name: 'postventa_test' },
  },
  ...overrides,
});

const params = {
  since: '2026-10-01',
  until: '2026-10-13',
  user_ids: [7],
  inbox_ids: [3],
};

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
  const wrapper = mount(PostSaleTab, {
    props: { params, timezone: 'America/Argentina/Buenos_Aires' },
    global: { plugins: [router] },
  });
  await flushPromises();
  return wrapper;
};

describe('Arroyo post-sale panel', () => {
  beforeEach(() => {
    vi.spyOn(PostSaleAPI, 'getFollowUps').mockResolvedValue({
      data: {
        follow_ups: [followUp()],
        totals: { manual_pending: 1, unconfirmed: 1 },
      },
    });
    vi.spyOn(PostSaleAPI, 'resolve').mockResolvedValue({ data: {} });
    vi.spyOn(PostSaleAPI, 'updatePurchase').mockResolvedValue({ data: {} });
  });

  afterEach(() => vi.restoreAllMocks());

  it('shows delivery evidence separately from manual work and links to the actual message', async () => {
    const wrapper = await mountTab();
    expect(wrapper.text()).toContain('Cliente Arroyo');
    expect(wrapper.text()).toContain(
      'ARROYO.PANEL.POST_SALE.STATUSES.UNCONFIRMED'
    );
    await wrapper.find('[data-testid="follow-up-12"]').trigger('click');
    expect(wrapper.text()).toContain('No delivery confirmation');
    expect(wrapper.text()).toContain('¿Cómo viene tu bicicleta?');
    expect(wrapper.text()).toContain('postventa_test');
    expect(
      wrapper.find('[data-testid="message-link"]').attributes('href')
    ).toBe('/app/accounts/1/conversations/42?messageId=90');
    expect(
      wrapper.find('[data-testid="purchase-date"] input').element.value
    ).toBe('2026-10-06T12:00');
  });

  it('reloads with the shared filters and selected status', async () => {
    const wrapper = await mountTab();
    expect(PostSaleAPI.getFollowUps).toHaveBeenCalledWith(
      expect.objectContaining(params)
    );
    await wrapper
      .find('[data-testid="status-filter"] select')
      .setValue('failed');
    await flushPromises();
    expect(PostSaleAPI.getFollowUps).toHaveBeenLastCalledWith(
      expect.objectContaining({ ...params, status: 'failed' })
    );
  });

  it('loads the next page and resets pagination when filters change', async () => {
    PostSaleAPI.getFollowUps.mockResolvedValue({
      data: {
        follow_ups: [followUp()],
        totals: {},
        meta: { total: 201, next_page: 2 },
      },
    });
    const wrapper = await mountTab();
    expect(wrapper.find('[data-testid="next-page"]').exists()).toBe(true);
    await wrapper.find('[data-testid="next-page"]').trigger('click');
    await flushPromises();
    expect(PostSaleAPI.getFollowUps).toHaveBeenLastCalledWith(
      expect.objectContaining({ page: 2 })
    );
    await wrapper
      .find('[data-testid="status-filter"] select')
      .setValue('failed');
    await flushPromises();
    expect(PostSaleAPI.getFollowUps.mock.lastCall[0]).not.toHaveProperty(
      'page'
    );
    expect(PostSaleAPI.getFollowUps.mock.lastCall[0].status).toBe('failed');
  });

  it('records a manual resolution without marking a message delivered', async () => {
    const wrapper = await mountTab();
    await wrapper.find('[data-testid="follow-up-12"]').trigger('click');
    await wrapper
      .find('[data-testid="resolution-note"] textarea')
      .setValue('Llamé y recibió todo bien');
    PostSaleAPI.getFollowUps.mockResolvedValue({
      data: {
        follow_ups: [
          followUp({
            manual_status: 'resolved',
            resolution_method: 'call',
            resolution_note: 'Llamé y recibió todo bien',
          }),
        ],
        totals: {},
      },
    });
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(PostSaleAPI.resolve).toHaveBeenCalledWith(12, {
      method: 'call',
      note: 'Llamé y recibió todo bien',
    });
    expect(PostSaleAPI.getFollowUps).toHaveBeenLastCalledWith({
      purchase_reference: 'purchase-1',
    });
    expect(wrapper.find('[data-testid="resolve-submit"]').exists()).toBe(false);
    expect(wrapper.text()).toContain(
      'ARROYO.PANEL.POST_SALE.STATUSES.UNCONFIRMED'
    );
    expect(wrapper.text()).toContain('Llamé y recibió todo bien');
  });

  it('corrects the purchase date using the business timezone', async () => {
    const wrapper = await mountTab();
    await wrapper.find('[data-testid="follow-up-12"]').trigger('click');
    await wrapper
      .find('[data-testid="purchase-date"] input')
      .setValue('2026-10-05T18:30');
    const corrected = followUp();
    corrected.purchase.purchased_at = '2026-10-05T21:30:00Z';
    PostSaleAPI.getFollowUps.mockResolvedValue({
      data: { follow_ups: [corrected], totals: {} },
    });
    await wrapper.find('[data-testid="purchase-date-save"]').trigger('click');
    await flushPromises();
    expect(PostSaleAPI.updatePurchase).toHaveBeenCalledWith('purchase-1', {
      purchased_at: '2026-10-05T21:30:00.000Z',
    });
    expect(
      wrapper.find('[data-testid="purchase-date"] input').element.value
    ).toBe('2026-10-05T18:30');
  });

  it('keeps the manual task open and shows the backend reason when resolution fails', async () => {
    PostSaleAPI.resolve.mockRejectedValue({
      response: { data: { error: 'Not authorized for this task' } },
    });
    const wrapper = await mountTab();
    await wrapper.find('[data-testid="follow-up-12"]').trigger('click');
    await wrapper
      .find('[data-testid="resolution-note"] textarea')
      .setValue('Contactado');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').text()).toContain(
      'Not authorized for this task'
    );
    expect(wrapper.find('[data-testid="resolve-submit"]').exists()).toBe(true);
    expect(
      wrapper.find('[data-testid="resolution-note"] textarea').element.value
    ).toBe('Contactado');
  });

  it('hides mutation controls when the backend policy denies them', async () => {
    const item = followUp({ can_resolve: false });
    item.purchase.can_edit_purchase = false;
    PostSaleAPI.getFollowUps.mockResolvedValue({
      data: { follow_ups: [item], totals: {} },
    });
    const wrapper = await mountTab();
    await wrapper.find('[data-testid="follow-up-12"]').trigger('click');
    expect(wrapper.find('[data-testid="resolve-submit"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="purchase-date-save"]').exists()).toBe(
      false
    );
  });

  it('shows an actionable loading error and recovers on retry', async () => {
    PostSaleAPI.getFollowUps.mockRejectedValueOnce(new Error('network'));
    const wrapper = await mountTab();
    expect(wrapper.find('[role="alert"]').text()).toContain(
      'ARROYO.PANEL.POST_SALE.LOAD_ERROR'
    );
    await wrapper.find('[data-testid="retry"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Cliente Arroyo');
  });

  it('renders all backend statuses, empty results and automatic closure', async () => {
    const statuses = [
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
    PostSaleAPI.getFollowUps.mockResolvedValueOnce({
      data: {
        follow_ups: statuses.map((status, id) =>
          followUp({ id, status, manual_status: 'closed_automatically' })
        ),
        totals: {},
      },
    });
    const wrapper = await mountTab();
    statuses.forEach(status =>
      expect(wrapper.text()).toContain(
        `ARROYO.PANEL.POST_SALE.STATUSES.${status.toUpperCase()}`
      )
    );
    expect(wrapper.text()).toContain(
      'ARROYO.PANEL.POST_SALE.MANUAL_STATUSES.CLOSED_AUTOMATICALLY'
    );
    PostSaleAPI.getFollowUps.mockResolvedValue({
      data: { follow_ups: [], totals: {} },
    });
    await wrapper.find('[data-testid="status-filter"] select').setValue('read');
    await flushPromises();
    expect(wrapper.text()).toContain('ARROYO.PANEL.POST_SALE.EMPTY');
  });
});

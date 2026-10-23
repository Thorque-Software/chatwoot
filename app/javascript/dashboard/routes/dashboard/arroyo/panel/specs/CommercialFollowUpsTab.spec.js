import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import CommercialFollowUpsTab from '../components/CommercialFollowUpsTab.vue';
import CommercialFollowUpsAPI from '../../api/commercialFollowUps';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('../helpers', async importOriginal => ({
  ...(await importOriginal()),
  todayIn: () => '2026-10-23',
}));

enableAutoUnmount(afterEach);

const pendingSteps = [1, 2, 3].map(step => ({
  step,
  status: 'pending',
  sent_at: null,
  scheduled_for: null,
}));

const row = overrides => ({
  conversation_id: 10458,
  contact_name: 'Cliente Uno',
  contact_phone: '+5491100000001',
  assignee: { id: 5, name: 'Marcos Peralta' },
  advisor_alias: 'marcos',
  opportunity_reference: 'opp-1',
  status: 'scheduled',
  sent_count: 1,
  steps: [
    {
      step: 1,
      status: 'delivered',
      sent_at: '2026-10-21T13:00:00Z',
      scheduled_for: null,
    },
    {
      step: 2,
      status: 'scheduled',
      sent_at: null,
      scheduled_for: '2026-10-23T13:00:00Z',
    },
    pendingSteps[2],
  ],
  next_at: '2026-10-23T13:00:00Z',
  next_step: 2,
  due_today: true,
  enrolled_at: '2026-10-20T21:00:00Z',
  finished_at: null,
  blocked_reason: null,
  can_send_now: true,
  can_reschedule: true,
  can_enroll: false,
  ...overrides,
});

const unenrolled = (id, name) =>
  row({
    conversation_id: id,
    contact_name: name,
    advisor_alias: null,
    opportunity_reference: null,
    status: 'unenrolled',
    sent_count: 0,
    steps: pendingSteps,
    next_at: null,
    next_step: null,
    due_today: false,
    enrolled_at: null,
    blocked_reason: 'not_enrolled',
    can_send_now: false,
    can_reschedule: false,
    can_enroll: true,
  });

const finished = row({
  conversation_id: 8001,
  contact_name: 'Cliente Terminado',
  status: 'finished',
  sent_count: 3,
  steps: [1, 2, 3].map(step => ({
    step,
    status: 'read',
    sent_at: '2026-10-15T13:00:00Z',
    scheduled_for: null,
  })),
  next_at: null,
  next_step: null,
  due_today: false,
  finished_at: '2026-10-21T13:00:00Z',
  can_send_now: false,
  can_reschedule: false,
});

const payload = {
  follow_ups: [
    row(),
    unenrolled(9001, 'Cliente Dos'),
    unenrolled(9002, 'Cliente Tres'),
    finished,
  ],
  totals: {
    scheduled: 1,
    awaiting_finish: 0,
    finished: 1,
    paused: 0,
    unenrolled: 2,
  },
  agenda: [
    { date: '2026-10-23', count: 1 },
    { date: '2026-10-24', count: 3 },
  ],
};

const mountTab = async () => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        path: '/app/accounts/:accountId/arroyo/seguimiento-comercial',
        component: { template: '<div />' },
      },
      { path: '/:pathMatch(.*)*', component: { template: '<div />' } },
    ],
  });
  await router.push('/app/accounts/1/arroyo/seguimiento-comercial');
  const wrapper = mount(CommercialFollowUpsTab, {
    props: { timezone: 'America/Argentina/Buenos_Aires' },
    global: { plugins: [router] },
  });
  await flushPromises();
  return wrapper;
};

describe('Arroyo commercial follow-up tab', () => {
  beforeEach(() => {
    vi.spyOn(CommercialFollowUpsAPI, 'getAll').mockResolvedValue({
      data: payload,
    });
    vi.spyOn(CommercialFollowUpsAPI, 'sendNow').mockResolvedValue({
      data: { follow_up: row() },
    });
    vi.spyOn(CommercialFollowUpsAPI, 'reschedule').mockResolvedValue({
      data: { follow_up: row() },
    });
    vi.spyOn(CommercialFollowUpsAPI, 'enroll').mockResolvedValue({
      data: { enrolled: [9001, 9002], skipped: [] },
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.mocked(useAlert).mockClear();
  });

  it('shows the counters, the agenda with today highlighted and every row', async () => {
    const wrapper = await mountTab();
    expect(wrapper.get('[data-testid="filter-scheduled"]').text()).toContain(
      '1'
    );
    expect(wrapper.get('[data-testid="filter-unenrolled"]').text()).toContain(
      '2'
    );
    expect(
      wrapper.get('[data-testid="agenda-2026-10-23"]').classes()
    ).toContain('bg-n-blue-3');
    expect(
      wrapper.get('[data-testid="agenda-2026-10-24"]').classes()
    ).not.toContain('bg-n-blue-3');
    expect(wrapper.get('[data-testid="agenda-2026-10-24"]').text()).toContain(
      'Sends: 3'
    );
    ['10458', '9001', '9002', '8001'].forEach(id =>
      expect(wrapper.find(`[data-testid="row-${id}"]`).exists()).toBe(true)
    );
    const first = wrapper.get('[data-testid="row-10458"]');
    expect(first.text()).toContain('Marcos Peralta');
    expect(first.text()).toContain('Signs as: marcos');
    expect(first.text()).toContain('Goes out today');
    expect(first.get('[data-testid="step-10458-1"]').text()).toContain(
      'Delivered'
    );
    expect(first.get('[data-testid="step-10458-2"]').text()).toContain(
      'Scheduled'
    );
    expect(first.get('[data-testid="step-10458-3"]').text()).toContain(
      'Pending'
    );
    expect(
      wrapper.get('[data-testid="conversation-10458"]').attributes('href')
    ).toBe('/app/accounts/1/conversations/10458');
  });

  it('explains why a chat will not go out', async () => {
    const wrapper = await mountTab();
    expect(wrapper.get('[data-testid="blocked-9001"]').text()).toBe(
      'Will not go out: it is not enrolled in follow-up yet.'
    );
    expect(wrapper.find('[data-testid="blocked-10458"]').exists()).toBe(false);
  });

  it('filters the rows by status and toggles the filter off', async () => {
    const wrapper = await mountTab();
    await wrapper.get('[data-testid="filter-unenrolled"]').trigger('click');
    expect(wrapper.find('[data-testid="row-9001"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="row-9002"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="row-10458"]').exists()).toBe(false);
    await wrapper.get('[data-testid="filter-unenrolled"]').trigger('click');
    expect(wrapper.find('[data-testid="row-10458"]').exists()).toBe(true);
    await wrapper.get('[data-testid="filter-paused"]').trigger('click');
    expect(wrapper.text()).toContain('No chats have this status');
  });

  it('offers only the actions each row allows', async () => {
    const wrapper = await mountTab();
    const has = id => testid => wrapper.find(`[data-testid="${testid}-${id}"]`);
    const scheduled = has(10458);
    expect(scheduled('send-now').exists()).toBe(true);
    expect(scheduled('reschedule').exists()).toBe(true);
    expect(scheduled('enroll').exists()).toBe(false);
    expect(scheduled('select').exists()).toBe(false);
    const pending = has(9001);
    expect(pending('send-now').exists()).toBe(false);
    expect(pending('reschedule').exists()).toBe(false);
    expect(pending('enroll').exists()).toBe(true);
    expect(pending('select').exists()).toBe(true);
    const done = has(8001);
    ['send-now', 'reschedule', 'enroll', 'select'].forEach(testid =>
      expect(done(testid).exists()).toBe(false)
    );
  });

  it('asks for confirmation before sending now and reloads afterwards', async () => {
    const wrapper = await mountTab();
    await wrapper.get('[data-testid="send-now-10458"]').trigger('click');
    expect(CommercialFollowUpsAPI.sendNow).not.toHaveBeenCalled();
    await wrapper.get('[data-testid="confirm-send-10458"]').trigger('click');
    await flushPromises();
    expect(CommercialFollowUpsAPI.sendNow).toHaveBeenCalledWith({
      conversation_id: 10458,
      opportunity_reference: 'opp-1',
    });
    expect(CommercialFollowUpsAPI.getAll).toHaveBeenCalledTimes(2);
    expect(useAlert).toHaveBeenCalledWith('Follow-up sent');
    expect(wrapper.find('[data-testid="action-10458"]').exists()).toBe(false);
  });

  it('reschedules with the chosen date and rejects dates that are not after today', async () => {
    const wrapper = await mountTab();
    await wrapper.get('[data-testid="reschedule-10458"]').trigger('click');
    const dateInput = wrapper.get(
      '[data-testid="reschedule-date-10458"] input'
    );
    const save = wrapper.get('[data-testid="confirm-reschedule-10458"]');
    expect(save.attributes('disabled')).toBeDefined();
    await dateInput.setValue('2026-10-23');
    expect(save.attributes('disabled')).toBeDefined();
    await dateInput.setValue('2026-10-26');
    expect(save.attributes('disabled')).toBeUndefined();
    await save.trigger('click');
    await flushPromises();
    expect(CommercialFollowUpsAPI.reschedule).toHaveBeenCalledWith({
      conversation_id: 10458,
      opportunity_reference: 'opp-1',
      date: '2026-10-26',
    });
    expect(CommercialFollowUpsAPI.getAll).toHaveBeenCalledTimes(2);
  });

  it('enrolls one chat after confirmation', async () => {
    const wrapper = await mountTab();
    await wrapper.get('[data-testid="enroll-9001"]').trigger('click');
    expect(wrapper.get('[data-testid="action-9001"]').text()).toContain(
      'tomorrow at 10:00'
    );
    await wrapper.get('[data-testid="confirm-enroll-9001"]').trigger('click');
    await flushPromises();
    expect(CommercialFollowUpsAPI.enroll).toHaveBeenCalledWith({
      conversation_ids: [9001],
    });
  });

  it('enrolls the selected chats at once after warning about the first send', async () => {
    const wrapper = await mountTab();
    expect(wrapper.find('[data-testid="enroll-selected"]').exists()).toBe(
      false
    );
    await wrapper.get('[data-testid="select-9001"]').setValue(true);
    await wrapper.get('[data-testid="select-9002"]').setValue(true);
    expect(wrapper.get('[data-testid="enroll-selected"]').text()).toContain(
      'Enroll selected (2)'
    );
    await wrapper.get('[data-testid="enroll-selected"]').trigger('click');
    expect(wrapper.get('[data-testid="bulk-confirm"]').text()).toContain(
      'tomorrow at 10:00'
    );
    expect(CommercialFollowUpsAPI.enroll).not.toHaveBeenCalled();
    await wrapper
      .get('[data-testid="confirm-enroll-selected"]')
      .trigger('click');
    await flushPromises();
    expect(CommercialFollowUpsAPI.enroll).toHaveBeenCalledWith({
      conversation_ids: [9001, 9002],
    });
    expect(useAlert).toHaveBeenCalledWith('Enrolled: 2. Skipped: 0.');
    expect(wrapper.find('[data-testid="enroll-selected"]').exists()).toBe(
      false
    );
  });

  it('selects every chat that can be enrolled with the header checkbox', async () => {
    const wrapper = await mountTab();
    await wrapper.get('[data-testid="select-all"]').setValue(true);
    expect(wrapper.get('[data-testid="enroll-selected"]').text()).toContain(
      'Enroll selected (2)'
    );
    await wrapper.get('[data-testid="select-all"]').setValue(false);
    expect(wrapper.find('[data-testid="enroll-selected"]').exists()).toBe(
      false
    );
  });

  it('keeps the page usable when an action fails', async () => {
    CommercialFollowUpsAPI.sendNow.mockRejectedValue({
      response: { data: { errors: ['not_due'] } },
    });
    const wrapper = await mountTab();
    await wrapper.get('[data-testid="send-now-10458"]').trigger('click');
    await wrapper.get('[data-testid="confirm-send-10458"]').trigger('click');
    await flushPromises();
    expect(useAlert).toHaveBeenCalledWith('not_due');
    expect(wrapper.find('[data-testid="row-10458"]').exists()).toBe(true);
  });

  it('shows the load error and retries', async () => {
    CommercialFollowUpsAPI.getAll.mockRejectedValueOnce(new Error('offline'));
    const wrapper = await mountTab();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'Could not load commercial follow-up'
    );
    await wrapper.get('[data-testid="retry"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="row-10458"]').exists()).toBe(true);
  });

  it('shows an empty state when nobody is in follow-up', async () => {
    CommercialFollowUpsAPI.getAll.mockResolvedValue({
      data: { follow_ups: [], totals: {}, agenda: [] },
    });
    const wrapper = await mountTab();
    expect(wrapper.text()).toContain('There are no chats in follow-up yet');
    expect(wrapper.text()).toContain('There are no scheduled sends.');
  });
});

import { mount, enableAutoUnmount } from '@vue/test-utils';
import { createStore } from 'vuex';
import FunnelBoardSection from '../components/FunnelBoardSection.vue';
import SectionCard from '../components/SectionCard.vue';

enableAutoUnmount(afterEach);

const defaults = () => ({
  enabled: false,
  abandon_hours: 24,
  lost_label: 'noquierenada',
  repurchase_label: 'recompra',
  info_labels: [
    { label: 'cotizado', enabled: true },
    { label: 'cuota', enabled: true },
  ],
  inboxes: [{ id: 3, name: 'Evolution' }],
  window_nudge: {
    enabled: false,
    text: 'Hola {{contact.first_name}}',
    morning_time: '08:30',
    evening_time: '19:00',
    skip_sundays: true,
    margin_minutes: 30,
    skip_labels: ['seguimiento'],
  },
});

const mountSection = (config = defaults()) =>
  mount(FunnelBoardSection, {
    props: { config },
    global: {
      plugins: [
        createStore({
          getters: {
            'inboxes/getInboxes': () => [
              { id: 2, name: 'WhatsApp' },
              { id: 3, name: 'Arroyo Evolution' },
            ],
          },
        }),
      ],
    },
  });

const save = async wrapper => {
  wrapper.findComponent(SectionCard).vm.$emit('save');
  await wrapper.vm.$nextTick();
  const events = wrapper.emitted('save') || [];
  return events.length ? events[events.length - 1][0].funnel_board : null;
};

it('saves the whole section in one payload, keeping the saved numbers', async () => {
  const wrapper = mountSection();

  expect(await save(wrapper)).toEqual({
    enabled: false,
    abandon_hours: 24,
    lost_label: 'noquierenada',
    repurchase_label: 'recompra',
    info_labels: [
      { label: 'cotizado', enabled: true },
      { label: 'cuota', enabled: true },
    ],
    inboxes: [{ id: 3, name: 'Evolution' }],
    window_nudge: {
      enabled: false,
      text: 'Hola {{contact.first_name}}',
      morning_time: '08:30',
      evening_time: '19:00',
      skip_sundays: true,
      margin_minutes: 30,
      skip_labels: ['seguimiento'],
    },
  });
  expect(wrapper.find('[data-testid="board-inbox-2"]').exists()).toBe(true);
});

it('adds informative labels and splits the excluded labels by comma', async () => {
  const wrapper = mountSection();

  await wrapper.find('[data-testid="new-info-label"] input').setValue('taller');
  await wrapper.find('[data-testid="add-info-label"]').trigger('click');
  await wrapper
    .find('[data-testid="window-nudge-skip-labels"] input')
    .setValue(' seguimiento, cuota ,, ');

  const payload = await save(wrapper);
  expect(payload.info_labels.map(item => item.label)).toEqual([
    'cotizado',
    'cuota',
    'taller',
  ]);
  expect(payload.window_nudge.skip_labels).toEqual(['seguimiento', 'cuota']);
});

it('does not save an evening limit before the morning time', async () => {
  const config = defaults();
  config.window_nudge.morning_time = '20:00';
  const wrapper = mountSection(config);

  expect(await save(wrapper)).toBeNull();
  expect(wrapper.find('[data-testid="funnel-board-errors"]').exists()).toBe(
    true
  );
});

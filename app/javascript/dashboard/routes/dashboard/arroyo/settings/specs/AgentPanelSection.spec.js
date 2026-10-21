import { mount, enableAutoUnmount } from '@vue/test-utils';
import { createStore } from 'vuex';
import AgentPanelSection from '../components/AgentPanelSection.vue';
import SectionCard from '../components/SectionCard.vue';
import MultiSelect from 'dashboard/components-next/filter/inputs/MultiSelect.vue';

enableAutoUnmount(afterEach);

it('defaults the commercial features off and saves seller IDs with numeric limits', async () => {
  const wrapper = mount(AgentPanelSection, {
    props: {
      config: {
        enabled: true,
        agents_see_only_own: true,
        hide_native_reports: false,
      },
    },
    global: {
      plugins: [
        createStore({
          getters: {
            'agents/getAgents': () => [
              { id: 7, name: 'Julieta' },
              { id: 8, name: 'Marcos' },
            ],
          },
        }),
      ],
      stubs: { MultiSelect: true },
    },
  });
  wrapper.findComponent(SectionCard).vm.$emit('save');
  await wrapper.vm.$nextTick();
  expect(wrapper.emitted('save')[0][0].agent_panel).toMatchObject({
    funnel_enabled: false,
    balanced_assignment_enabled: false,
    seller_ids: [],
    response_hours: 4,
    lookback_days: 7,
  });
  wrapper
    .findComponent(MultiSelect)
    .vm.$emit('update:modelValue', [{ id: 8, name: 'Marcos' }]);
  await wrapper.findAll('input[type="number"]')[0].setValue('6');
  wrapper.findComponent(SectionCard).vm.$emit('save');
  await wrapper.vm.$nextTick();
  expect(wrapper.emitted('save')[1][0].agent_panel).toMatchObject({
    seller_ids: [8],
    response_hours: 6,
  });
});

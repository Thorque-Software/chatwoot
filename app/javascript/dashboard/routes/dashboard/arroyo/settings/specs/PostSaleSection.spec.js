import { mount, enableAutoUnmount } from '@vue/test-utils';
import { createStore } from 'vuex';
import PostSaleSection from '../components/PostSaleSection.vue';
import SectionCard from '../components/SectionCard.vue';

enableAutoUnmount(afterEach);

it('shows fixed Meta templates and never offers or saves editable message bodies', async () => {
  const wrapper = mount(PostSaleSection, {
    props: {
      config: {
        enabled: false,
        trigger_label: 'vendido',
        send_hour_local: 10,
        skip_sundays: false,
        delivery_timeout_hours: 6,
        alert_user_ids: [],
        stages: Object.fromEntries(
          ['d1', 'd7', 'd30'].map(stage => [
            stage,
            {
              days: 1,
              template: `postventa_${stage}`,
              free_text: 'Legacy text',
            },
          ])
        ),
      },
    },
    global: {
      plugins: [createStore({ getters: { 'agents/getAgents': () => [] } })],
      stubs: { MultiSelect: true, 'fluent-icon': true },
    },
  });
  expect(wrapper.findAll('textarea')).toHaveLength(0);
  expect(wrapper.text()).toContain('postventa_d1');
  expect(wrapper.find('input[name="d1_template"]').exists()).toBe(false);
  wrapper.findComponent(SectionCard).vm.$emit('save');
  await wrapper.vm.$nextTick();
  const config = wrapper.emitted('save')[0][0].post_sale;
  expect(config.stages.d1).toEqual({ days: 1 });
});

import { mount, enableAutoUnmount } from '@vue/test-utils';
import CommercialFollowUpSection from '../components/CommercialFollowUpSection.vue';
import SectionCard from '../components/SectionCard.vue';

enableAutoUnmount(afterEach);

const config = {
  enabled: true,
  aliases: [
    { name: 'Julieta Peralta', alias: 'juli' },
    { name: 'Marcos Peralta', alias: 'marcos' },
  ],
};

const mountSection = (props = { config }) =>
  mount(CommercialFollowUpSection, { props });

const save = async wrapper => {
  wrapper.findComponent(SectionCard).vm.$emit('save');
  await wrapper.vm.$nextTick();
};

describe('Arroyo commercial follow-up settings', () => {
  it('shows the preset aliases and saves them with the enabled flag', async () => {
    const wrapper = mountSection();
    const inputs = wrapper.findAll('input');
    expect(inputs.map(input => input.element.value)).toEqual([
      'Julieta Peralta',
      'juli',
      'Marcos Peralta',
      'marcos',
    ]);
    await save(wrapper);
    expect(wrapper.emitted('save')[0][0]).toEqual({
      follow_up: {
        enabled: true,
        aliases: [
          { name: 'Julieta Peralta', alias: 'juli' },
          { name: 'Marcos Peralta', alias: 'marcos' },
        ],
      },
    });
  });

  it('defaults to disabled without aliases when the account has no configuration yet', async () => {
    const wrapper = mountSection({ config: {} });
    expect(wrapper.find('[data-testid="alias-0"]').exists()).toBe(false);
    await save(wrapper);
    expect(wrapper.emitted('save')[0][0]).toEqual({
      follow_up: { enabled: false, aliases: [] },
    });
  });

  it('adds, edits and removes aliases and trims what it saves', async () => {
    const wrapper = mountSection();
    await wrapper.get('[data-testid="add-alias"]').trigger('click');
    const row = wrapper.get('[data-testid="alias-2"]');
    const [name, alias] = row.findAll('input');
    await name.setValue('  Laura Gomez ');
    await alias.setValue(' lau ');
    await wrapper.get('[data-testid="remove-alias-0"]').trigger('click');
    await save(wrapper);
    expect(wrapper.emitted('save')[0][0].follow_up.aliases).toEqual([
      { name: 'Marcos Peralta', alias: 'marcos' },
      { name: 'Laura Gomez', alias: 'lau' },
    ]);
  });

  it('does not save and shows an error while an alias row is blank', async () => {
    const wrapper = mountSection();
    await wrapper.get('[data-testid="add-alias"]').trigger('click');
    await save(wrapper);
    expect(wrapper.emitted('save')).toBeUndefined();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'Fill in the name and alias of every row'
    );
    await wrapper.get('[data-testid="remove-alias-2"]').trigger('click');
    await save(wrapper);
    expect(wrapper.emitted('save')).toHaveLength(1);
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });

  it('rejects an alias that is only whitespace', async () => {
    const wrapper = mountSection();
    const alias = wrapper.get('[data-testid="alias-1"]').findAll('input')[1];
    await alias.setValue('   ');
    await save(wrapper);
    expect(wrapper.emitted('save')).toBeUndefined();
  });
});

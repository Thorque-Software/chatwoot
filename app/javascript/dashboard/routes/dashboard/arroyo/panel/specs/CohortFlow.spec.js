import { mount, flushPromises } from '@vue/test-utils';
import CohortFlow from '../components/CohortFlow.vue';

const metrics = {
  received: 11,
  assigned: 9,
  attended: 7,
  bot: 1,
  unassigned: 1,
  pending: 1,
  in_progress: 2,
  won: 4,
  lost: 1,
  inactive: 1,
  unknown: 1,
};
const report = {
  totals: metrics,
  agents: [
    {
      id: 21,
      name: 'Una vendedora con nombre largo de demostración',
      totals: metrics,
    },
    { id: 32, name: 'Otro vendedor', totals: { ...metrics, pending: 0 } },
    { id: 43, name: 'Tercer vendedor', totals: { ...metrics, unknown: 2 } },
  ],
};

describe('Arroyo connected cohort flow', () => {
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it('anchors connectors to block centers and updates them when layout changes', async () => {
    let resize;
    const disconnect = vi.fn();
    vi.stubGlobal(
      'ResizeObserver',
      class {
        constructor(callback) {
          resize = callback;
          this.observe = vi.fn();
          this.disconnect = disconnect;
        }
      }
    );
    let sellerTop = 80;
    let stageLeft = 340;
    vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(
      function getRect() {
        const key = this.getAttribute('data-testid');
        const boxes = {
          'cohort-flow': [100, 50, 1000, 450],
          'flow-received': [100, 150, 200, 100],
          'flow-bot': [stageLeft, 100, 200, 40],
          'flow-unassigned': [stageLeft, 220, 200, 40],
          'flow-assigned': [stageLeft, 340, 200, 40],
          'flow-seller': [
            580,
            sellerTop +
              Array.from(this.parentElement.children).indexOf(this) * 120,
            520,
            100,
          ],
        };
        const [left, top, width, height] = boxes[key] || [0, 0, 0, 0];
        return { left, top, right: left + width, width, height };
      }
    );
    const wrapper = mount(CohortFlow, { props: { report } });
    await flushPromises();
    const intake = () => wrapper.get('[data-testid="flow-intake-connectors"]');
    const sellers = () => wrapper.get('[data-testid="flow-seller-connectors"]');
    expect(intake().attributes('d')).toContain('M 200 150 H 220');
    expect(intake().attributes('d')).toContain('M 220 70 V 310');
    expect(intake().attributes('d')).toContain('M 220 310 H 240');
    expect(sellers().attributes('d')).toContain('M 440 310 H 460');
    expect(sellers().attributes('d')).toContain('M 460 80 V 320');
    sellerTop = 160;
    resize();
    await flushPromises();
    expect(sellers().attributes('d')).toContain('M 460 160 V 400');
    await wrapper.setProps({ report: { ...report, agents: [] } });
    expect(
      wrapper.find('[data-testid="flow-seller-connectors"]').exists()
    ).toBe(false);
    stageLeft = 100;
    resize();
    await flushPromises();
    expect(
      wrapper.find('[data-testid="flow-intake-connectors"]').exists()
    ).toBe(false);
    wrapper.unmount();
  });

  it('uses dynamic sellers and preserves each seller drilldown for an outcome', async () => {
    const wrapper = mount(CohortFlow, { props: { report } });
    expect(wrapper.findAll('[data-testid="flow-seller"]').length).toBe(3);
    expect(wrapper.text()).toContain(report.agents[0].name);
    await wrapper.get('[data-testid="flow-43-won"]').trigger('click');
    expect(wrapper.emitted('drillDown').at(-1)).toEqual([
      { metric: 'won', userId: 43 },
    ]);
    expect(wrapper.get('[data-testid="flow-43-unknown"]').text()).toContain(
      '2'
    );
  });

  it('keeps milestones and customer inactivity distinct from current seller outcomes', async () => {
    const wrapper = mount(CohortFlow, { props: { report } });
    await wrapper.get('[data-testid="flow-assigned"]').trigger('click');
    expect(wrapper.emitted('drillDown').at(-1)).toEqual([
      { metric: 'assigned' },
    ]);
    expect(wrapper.get('[data-testid="flow-21-inactive"]').text()).toContain(
      'customer'
    );
    expect(wrapper.get('[data-testid="flow-21-attended"]').exists()).toBe(true);
  });
});

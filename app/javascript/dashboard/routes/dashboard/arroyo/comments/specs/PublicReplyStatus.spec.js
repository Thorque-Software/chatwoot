import { mount } from '@vue/test-utils';
import PublicReplyStatus from '../components/PublicReplyStatus.vue';

vi.mock('vue-i18n', async importOriginal => ({
  ...(await importOriginal()),
  useI18n: () => ({ t: key => key }),
}));

describe('Public reply evidence', () => {
  it('does not add public badges to ordinary messages', () => {
    expect(mount(PublicReplyStatus).text()).toBe('');
  });

  it('shows the confirmed publication state without a delivery receipt', () => {
    const wrapper = mount(PublicReplyStatus, {
      props: {
        attributes: {
          arroyoKind: 'social_comment_reply',
          arroyoPublicReplyStatus: 'published',
        },
      },
    });
    expect(wrapper.text()).toContain('ARROYO.SOCIAL_COMMENTS.STATUS.PUBLISHED');
    expect(wrapper.text()).not.toMatch(/DELIVERED|READ/);
  });

  it('preserves the distinction between pending configuration and unconfirmed publication', async () => {
    const wrapper = mount(PublicReplyStatus, {
      props: {
        attributes: {
          arroyo_kind: 'social_comment_reply',
          arroyo_public_reply_status: 'pending_configuration',
        },
      },
    });
    expect(wrapper.text()).toContain('STATUS.PENDING_CONFIGURATION');
    await wrapper.setProps({
      attributes: {
        arroyo_kind: 'social_comment_reply',
        arroyo_public_reply_status: 'unconfirmed',
      },
    });
    expect(wrapper.text()).toContain('STATUS.UNCONFIRMED');
  });
});

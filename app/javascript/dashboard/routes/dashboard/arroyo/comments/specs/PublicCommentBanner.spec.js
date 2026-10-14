import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import PublicCommentBanner from '../components/PublicCommentBanner.vue';
import SocialCommentsAPI from '../../api/socialComments';

const features = ref({
  social_comments: { enabled: true, inboxes: [{ inbox_id: 12 }] },
});
vi.mock('../../composables/useArroyoFeatures', () => ({
  useArroyoFeatures: () => ({ features }),
}));
vi.mock('vue-i18n', async importOriginal => ({
  ...(await importOriginal()),
  useI18n: () => ({ t: key => key }),
}));

describe('Public comment warning', () => {
  beforeEach(() => {
    vi.spyOn(SocialCommentsAPI, 'context').mockResolvedValue({
      data: { channel: { ready: false }, comments: [] },
    });
  });
  afterEach(() => vi.restoreAllMocks());

  it('does not fetch or show a warning for an ordinary inbox', async () => {
    const wrapper = mount(PublicCommentBanner, {
      props: { inboxId: 99, conversationId: 1 },
    });
    await flushPromises();
    expect(SocialCommentsAPI.context).not.toHaveBeenCalled();
    expect(wrapper.find('[role="note"]').exists()).toBe(false);
  });

  it('warns about public replies and pending setup but hides the warning for private notes', async () => {
    const wrapper = mount(PublicCommentBanner, {
      props: { inboxId: 12, conversationId: 1 },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('ARROYO.SOCIAL_COMMENTS.PUBLIC_WARNING');
    expect(wrapper.text()).toContain('CONNECTION_PENDING_BODY');
    await wrapper.setProps({ isPrivate: true });
    expect(wrapper.find('[role="note"]').exists()).toBe(false);
  });

  it('only exposes a verified post URL and a retry explicitly allowed by the server', async () => {
    SocialCommentsAPI.context.mockResolvedValue({
      data: {
        channel: { ready: true },
        comments: [
          {
            post_url: 'https://www.instagram.com/p/demo/',
            replies: [{ id: 4, status: 'unconfirmed', can_retry: false }],
          },
        ],
      },
    });
    const wrapper = mount(PublicCommentBanner, {
      props: { inboxId: 12, conversationId: 1 },
    });
    await flushPromises();
    expect(wrapper.find('a').attributes('href')).toBe(
      'https://www.instagram.com/p/demo/'
    );
    expect(wrapper.find('button').exists()).toBe(false);
  });
});

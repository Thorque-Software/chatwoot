import { publicReplyState, safeMetaUrl } from '../helpers';

describe('Arroyo public comment UI helpers', () => {
  it('handles native camelized message attributes and raw API attributes', () => {
    expect(
      publicReplyState({
        arroyoKind: 'social_comment_reply',
        arroyoPublicReplyStatus: 'queued',
      })
    ).toBe('queued');
    expect(
      publicReplyState({
        arroyo_kind: 'social_comment_reply',
        arroyo_public_reply_status: 'published',
      })
    ).toBe('published');
    expect(publicReplyState({})).toBeNull();
  });

  it('does not treat a native sent status as a published comment', () => {
    expect(publicReplyState({ arroyo_kind: 'social_comment_reply' })).toBe(
      'queued'
    );
  });

  it('only links to explicit HTTPS Meta publication domains', () => {
    expect(safeMetaUrl('https://www.instagram.com/p/demo/')).toBe(true);
    expect(safeMetaUrl('https://www.facebook.com/123/posts/456')).toBe(true);
    expect(safeMetaUrl(['javascript', 'alert(1)'].join(':'))).toBe(false);
    expect(safeMetaUrl('https://www.instagram.com.evil.example/')).toBe(false);
    expect(safeMetaUrl('https://user:password@www.facebook.com/')).toBe(false);
    expect(safeMetaUrl(null)).toBe(false);
  });
});

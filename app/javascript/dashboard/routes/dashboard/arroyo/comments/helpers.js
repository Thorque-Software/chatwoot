export const publicReplyState = attributes => {
  const kind = attributes?.arroyoKind || attributes?.arroyo_kind;
  if (kind !== 'social_comment_reply') return null;
  return (
    attributes.arroyoPublicReplyStatus ||
    attributes.arroyo_public_reply_status ||
    'queued'
  );
};

export const safeMetaUrl = value => {
  if (!value) return false;
  try {
    const url = new URL(value);
    return (
      url.protocol === 'https:' &&
      !url.username &&
      !url.password &&
      [
        'instagram.com',
        'www.instagram.com',
        'facebook.com',
        'www.facebook.com',
        'm.facebook.com',
        'fb.com',
        'www.fb.com',
      ].includes(url.hostname)
    );
  } catch {
    return false;
  }
};

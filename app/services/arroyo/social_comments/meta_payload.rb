class Arroyo::SocialComments::MetaPayload
  pattr_initialize [:payload_base64!, :signature!]

  def perform
    raw = Base64.strict_decode64(payload_base64)
    verify_signature!(raw)
    payload = JSON.parse(raw)
    platform = { 'instagram' => 'instagram', 'page' => 'facebook' }[payload['object']]
    return [] unless platform

    Array(payload['entry']).flat_map { |entry| events_for(entry, platform) }
  rescue JSON::ParserError, ArgumentError
    raise Arroyo::SocialComments::Error, 'invalid_payload'
  end

  private

  def verify_signature!(raw)
    secret = ENV.fetch('ARROYO_SOCIAL_COMMENTS_META_APP_SECRET', '')
    raise Arroyo::SocialComments::Error.new('not_configured', :service_unavailable) if secret.blank?

    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, raw)}"
    valid = signature.to_s.match?(/\Asha256=[0-9a-f]{64}\z/) && ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    raise Arroyo::SocialComments::Error.new('invalid_signature', :forbidden) unless valid
  end

  def events_for(entry, platform)
    Array(entry['changes']).filter_map do |change|
      value = change['value'] || {}
      next unless comment_event?(change, value, platform)

      attrs = attributes(value, entry, platform)
      { platform: platform, external_account_id: entry['id'].to_s, attributes: attrs } if attrs['remote_id'].present?
    end
  end

  def comment_event?(change, value, platform)
    return change['field'] == 'comments' if platform == 'instagram'

    change['field'] == 'feed' && value['item'] == 'comment'
  end

  def event_time(entry)
    timestamp = entry.fetch('time', Time.current.to_i).to_f
    timestamp /= 1000 if timestamp > 10_000_000_000
    Time.at(timestamp).utc.iso8601(6)
  end

  def attributes(value, entry, platform)
    remote_id = (platform == 'instagram' ? value['id'] : value['comment_id']).to_s
    parent = value['parent_id'].presence
    media_id = (platform == 'instagram' ? value.dig('media', 'id') : value['post_id']).to_s
    parent = nil if parent == media_id
    {
      'remote_id' => remote_id, 'thread_id' => parent || remote_id, 'parent_id' => parent,
      'author_id' => value.dig('from', 'id').to_s, 'author_name' => value.dig('from', 'username') || value.dig('from', 'name'),
      'body' => value['text'] || value['message'], 'media_id' => media_id,
      'post_url' => value['permalink_url'], 'comment_url' => nil,
      'deleted' => %w[remove delete].include?(value['verb']),
      'remote_updated_at' => event_time(entry)
    }
  end
end

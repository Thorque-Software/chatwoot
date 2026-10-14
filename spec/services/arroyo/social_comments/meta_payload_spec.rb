require 'rails_helper'

RSpec.describe Arroyo::SocialComments::MetaPayload do
  let(:raw) do
    { object: 'instagram', entry: [{ id: '1789001', time: 1_792_000_000, changes: [{ field: 'comments', value: {
      id: '179001', text: '¿Precio?', from: { id: '179555', username: 'cliente' }, media: { id: '180001' }
    } }] }] }.to_json
  end

  def parse(body, secret = 'fixture-only-secret')
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
    described_class.new(payload_base64: Base64.strict_encode64(body), signature: signature).perform
  end

  it 'checks the original bytes and normalizes an Instagram comment' do
    with_modified_env ARROYO_SOCIAL_COMMENTS_META_APP_SECRET: 'fixture-only-secret' do
      expect(parse(raw).first).to include(platform: 'instagram', external_account_id: '1789001')
      expect(parse(raw).first[:attributes]).to include('remote_id' => '179001', 'body' => '¿Precio?')
      signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', 'fixture-only-secret', raw)}"
      expect { described_class.new(payload_base64: Base64.strict_encode64("#{raw} "), signature: signature).perform }
        .to raise_error(Arroyo::SocialComments::Error)
    end
  end

  it 'rejects unsigned input when configuration is missing' do
    with_modified_env ARROYO_SOCIAL_COMMENTS_META_APP_SECRET: nil do
      expect { parse(raw) }.to raise_error(Arroyo::SocialComments::Error)
    end
  end

  it 'normalizes Facebook comments and excludes unrelated events' do
    body = { object: 'page', entry: [{ id: 'page1', time: 1_792_000_000, changes: [{ field: 'feed', value: {
      item: 'comment', verb: 'add', comment_id: 'page1_55', post_id: 'page1_44', message: 'Hola', from: { id: 'user1', name: 'Cliente' }
    } }, { field: 'feed', value: { item: 'like' } }] }] }.to_json
    with_modified_env ARROYO_SOCIAL_COMMENTS_META_APP_SECRET: 'fixture-only-secret' do
      result = parse(body)
      expect(result.size).to eq(1)
      expect(result.first[:attributes]).to include('remote_id' => 'page1_55', 'media_id' => 'page1_44')
    end
  end
end

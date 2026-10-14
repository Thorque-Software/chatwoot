require 'rails_helper'

RSpec.describe 'Arroyo social comments API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:seller) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/arroyo/social_comments" }
  let(:channel) do
    Arroyo::SocialComments::ChannelService.new(account: account).create!(name: 'Comentarios', platform: 'instagram',
                                                                         user_ids: [seller.id], external_account_id: '1789001')
  end

  before { Arroyo::Setting.for(account).tap { |s| s.merge_config(social_comments: { enabled: true }) }.save! }

  it 'requires authentication and only administrators can claim publications' do
    get "#{base}/channels"
    expect(response).to have_http_status(:unauthorized)
    post "#{base}/claim", headers: seller.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'only exposes channels assigned to the seller' do
    channel
    get "#{base}/channels", headers: seller.create_new_auth_token
    expect(response.parsed_body['channels'].pluck('id')).to eq([channel.id])
    get "#{base}/channels", headers: outsider.create_new_auth_token
    expect(response.parsed_body['channels']).to be_empty
  end

  it 'does not mutate a channel from another account and preserves a false toggle' do
    foreign = create(:account)
    foreign_user = create(:user, account: foreign, role: :administrator)
    record = Arroyo::SocialComments::ChannelService.new(account: foreign).create!(name: 'Foreign', platform: 'facebook', user_ids: [foreign_user.id])
    patch "#{base}/channels/#{record.id}", headers: admin.create_new_auth_token, params: { channel: { publishing_enabled: true } }, as: :json
    expect(response).to have_http_status(:not_found)
    patch "#{base}/channels/#{channel.id}", headers: admin.create_new_auth_token, params: { channel: { publishing_enabled: false } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(channel.reload.publishing_enabled).to be(false)
  end

  it 'rejects forged imports even with a valid integration login' do
    with_modified_env ARROYO_SOCIAL_COMMENTS_META_APP_SECRET: 'fixture-only-secret' do
      post "#{base}/ingest", headers: admin.create_new_auth_token,
                             params: { payload_base64: Base64.strict_encode64('{}'), signature: "sha256=#{'a' * 64}" }, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Arroyo::SocialComment.count).to eq(0)
    end
  end

  it 'rejects public messages from integration API keys but permits a private note' do
    comment = Arroyo::SocialComments::ImportService.new(channel: channel, attributes: {
                                                          'remote_id' => '179001', 'thread_id' => '179001',
                                                          'author_id' => '179555', 'author_name' => 'Cliente',
                                                          'body' => 'Hola', 'media_id' => '180001', 'remote_updated_at' => Time.current.iso8601
                                                        }).perform
    url = "/api/v1/accounts/#{account.id}/conversations/#{comment.conversation.display_id}/messages"
    headers = { api_access_token: admin.access_token.token }
    post url, headers: headers, params: { content: 'Publicación automática', message_type: 'outgoing' }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(Arroyo::SocialReply.count).to eq(0)
    post url, headers: headers, params: { content: 'Nota interna', message_type: 'outgoing', private: true }, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'allows a seller session to create a public reply without leaking the interactive context' do
    comment = Arroyo::SocialComments::ImportService.new(channel: channel, attributes: {
                                                          'remote_id' => '179002', 'thread_id' => '179002',
                                                          'author_id' => '179555', 'author_name' => 'Cliente',
                                                          'body' => 'Hola', 'media_id' => '180001', 'remote_updated_at' => Time.current.iso8601
                                                        }).perform
    url = "/api/v1/accounts/#{account.id}/conversations/#{comment.conversation.display_id}/messages"
    expect do
      post url, headers: admin.create_new_auth_token, params: { content: 'Respuesta del vendedor', message_type: 'outgoing' }, as: :json
    end.to change(Arroyo::SocialReply, :count).by(1)
    expect(response).to have_http_status(:ok)
    expect(Arroyo::SocialReply.last.status).to eq('pending_configuration')
    expect(Arroyo::SocialComments::HumanReplyContext.user).to be_nil
  end
end

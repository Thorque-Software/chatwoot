require 'rails_helper'

RSpec.describe Arroyo::SocialComments::ReplyService do
  let(:account) { create(:account) }
  let(:seller) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    Arroyo::SocialComments::ChannelService.new(account: account).create!(name: 'Comentarios Instagram', platform: 'instagram',
                                                                         user_ids: [seller.id], external_account_id: '1789001')
  end
  let(:event) do
    { 'remote_id' => '179001', 'thread_id' => '179001', 'author_id' => '179555', 'author_name' => 'Cliente de prueba',
      'body' => '¿Tienen disponibilidad?', 'media_id' => '180001', 'remote_updated_at' => Time.current.iso8601 }
  end

  before { Arroyo::Setting.for(account).tap { |s| s.merge_config(social_comments: { enabled: true }) }.save! }

  def import(data = event)
    Arroyo::SocialComments::ImportService.new(channel: channel, attributes: data).perform
  end

  def reply(comment, user = seller, request_id = 'request-1')
    Arroyo::SocialComments::HumanReplyContext.set(user: user) do
      Messages::MessageBuilder.new(user, comment.conversation, content: 'Sí, te contamos las opciones.', message_type: 'outgoing',
                                                               echo_id: request_id).perform
    end
  end

  def publisher
    Arroyo::SocialComments::DeliveryService.new(account: account)
  end

  it 'imports once into an open conversation without attaching a bot' do
    expect { 2.times { import } }.to change(Arroyo::SocialComment, :count).by(1)
    record = Arroyo::SocialComment.last
    expect(record.message).to be_incoming
    expect(record.conversation).to be_open
    expect(channel.inbox.agent_bot_inbox).to be_nil
  end

  it 'groups replies to a comment in the same thread' do
    parent = import
    child = import(event.merge('remote_id' => '179002', 'parent_id' => parent.remote_id))
    expect(child.conversation_id).to eq(parent.conversation_id)
    expect(child.message_id).not_to eq(parent.message_id)
  end

  it 'ignores the page own comments' do
    expect(import(event.merge('author_id' => channel.external_account_id))).to be_nil
    expect(Arroyo::SocialComment.count).to eq(0)
  end

  it 'does not route a public comment through native API inbox email delivery' do
    message = reply(import)
    expect(Messages::SendEmailNotificationService).not_to receive(:new)
    SendReplyJob.perform_now(message.id)
  end

  it 'requires explicit retry after configuring Meta' do
    response = Arroyo::SocialReply.find_by!(message: reply(import))
    expect(response.status).to eq('pending_configuration')
    channel.update!(publishing_enabled: true, api_version: 'v25.0')
    expect(publisher.claim).to be_empty
    publisher.retry!(response, seller)
    expect(publisher.claim.size).to eq(1)
  end

  it 'rejects automated public responses and preserves private notes' do
    comment = import
    expect { reply(comment, nil) }.to raise_error(Arroyo::SocialComments::Error)
    message = Messages::MessageBuilder.new(nil, comment.conversation, content: 'Nota privada', private: true).perform
    expect(message).to be_private
    expect(Arroyo::SocialReply.count).to eq(0)
  end

  it 'deduplicates repeated human submissions' do
    comment = import
    first = reply(comment)
    expect(reply(comment).id).to eq(first.id)
    expect(Arroyo::SocialReply.count).to eq(1)
  end

  it 'claims once and accepts a repeated confirmation of the same Meta reply' do
    channel.update!(publishing_enabled: true, api_version: 'v25.0')
    response = Arroyo::SocialReply.find_by!(message: reply(import))
    claim = publisher.claim.first
    expect(publisher.claim).to be_empty
    2.times { publisher.acknowledge(response.id, claim_token: claim[:claim_token], status: 'published', remote_reply_id: '180999') }
    expect(response.reload).to have_attributes(status: 'published', remote_reply_id: '180999')
  end

  it 'rejects the wrong attempt token and does not overwrite success with a late failure' do
    channel.update!(publishing_enabled: true, api_version: 'v25.0')
    response = Arroyo::SocialReply.find_by!(message: reply(import))
    claim = publisher.claim.first
    expect { publisher.acknowledge(response.id, claim_token: 'other', status: 'published', remote_reply_id: '99') }
      .to raise_error(Arroyo::SocialComments::Error)
    publisher.acknowledge(response.id, claim_token: claim[:claim_token], status: 'published', remote_reply_id: '180999')
    publisher.acknowledge(response.id, claim_token: claim[:claim_token], status: 'failed')
    expect(response.reload.status).to eq('published')
  end

  it 'does not repeat a publication with an unknown outcome' do
    channel.update!(publishing_enabled: true, api_version: 'v25.0')
    response = Arroyo::SocialReply.find_by!(message: reply(import))
    publisher.claim
    response.update!(claimed_at: 20.minutes.ago)
    expect(publisher.claim).to be_empty
    expect(response.reload.status).to eq('unconfirmed')
    expect { publisher.retry!(response, seller) }.to raise_error(Arroyo::SocialComments::Error)
  end

  it 'preserves deleted comments and blocks subsequent replies' do
    comment = import
    import(event.merge('deleted' => true, 'remote_updated_at' => 1.minute.from_now.iso8601))
    expect(comment.reload.deleted_at).to be_present
    expect { reply(comment) }.to raise_error(Arroyo::SocialComments::Error)
  end

  it 'rejects publication links outside Meta domains' do
    expect { import(event.merge('post_url' => 'https://evil.example/phishing')) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'does not publish messages generated by a macro with a seller identity' do
    comment = import
    macro = create(:macro, account: account, actions: [{ 'action_name' => 'send_message', 'action_params' => ['Mensaje automático'] }])
    expect { Macros::ExecutionService.new(macro, comment.conversation, seller).perform }.not_to change(Arroyo::SocialReply, :count)
  end

  it 'imports an edit sharing the original event timestamp without duplicating the message' do
    comment = import
    expect { import(event.merge('body' => '¿Tienen otro modelo?')) }.not_to change(Message, :count)
    expect(comment.reload.body).to eq('¿Tienen otro modelo?')
    expect(comment.message.reload.content).to eq(comment.body)
  end

  it 'does not represent an unconfirmed publication as a failed native delivery with a generic retry' do
    response = Arroyo::SocialReply.find_by!(message: reply(import))
    response.update!(status: 'unconfirmed', error_message: 'Revisar en Meta antes de reenviar')
    response.sync_message!
    expect(response.message.reload.status).to eq('sent')
    expect(response.message.content_attributes['external_error']).to be_nil
    expect(response.message.content_attributes['arroyo_public_reply_status']).to eq('unconfirmed')
  end
end

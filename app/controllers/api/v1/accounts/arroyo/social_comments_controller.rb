class Api::V1::Accounts::Arroyo::SocialCommentsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?, only: %i[create_channel update_channel verify ingest enrich claim acknowledge]
  before_action :require_enabled, except: %i[channels index context acknowledge update_channel]
  rescue_from ::Arroyo::SocialComments::Error, with: :render_social_error

  def channels
    render json: { channels: visible_channels.includes(:inbox).map { |record| presenter.channel(record) } }
  end

  def create_channel
    record = ::Arroyo::SocialComments::ChannelService.new(account: Current.account).create!(**channel_params.to_h.symbolize_keys)
    render json: presenter.channel(record), status: :created
  end

  def update_channel
    record = ::Arroyo::SocialChannel.where(account: Current.account).find(params[:id])
    record.update!(params.require(:channel).permit(:external_account_id, :api_version, :publishing_enabled))
    render json: presenter.channel(record)
  end

  def index
    records = filtered_comments
    page = [params[:page].to_i, 1].max
    total = records.count
    data = records.order(created_at: :desc, id: :desc).offset((page - 1) * 30).limit(30).includes(:channel, :conversation,
                                                                                                  replies: [:message, :sender])
    render json: { comments: data.map { |record| presenter.comment(record) }, total: total, next_page: page * 30 < total ? page + 1 : nil }
  end

  def context
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    channel = visible_channels.find_by!(inbox_id: conversation.inbox_id)
    records = visible_comments.where(conversation: conversation).order(:id).includes(:channel, :conversation, replies: [:sender, :message])
    render json: { channel: presenter.channel(channel), comments: records.map { |record| presenter.comment(record) } }
  end

  def verify
    expected = ENV.fetch('ARROYO_SOCIAL_COMMENTS_META_VERIFY_TOKEN', '')
    supplied = params['hub.verify_token'].to_s
    raise ::Arroyo::SocialComments::Error.new('not_configured', :service_unavailable) if expected.blank?

    valid = params['hub.mode'] == 'subscribe' && supplied.present? && ActiveSupport::SecurityUtils.secure_compare(expected, supplied)
    raise ::Arroyo::SocialComments::Error.new('invalid_signature', :forbidden) unless valid

    render json: { challenge: params.require('hub.challenge') }
  end

  def ingest
    events = ::Arroyo::SocialComments::MetaPayload.new(payload_base64: params.require(:payload_base64), signature: params[:signature].to_s).perform
    posts = events.filter_map do |event|
      channel = ::Arroyo::SocialChannel.find_by(account: Current.account, platform: event[:platform],
                                                external_account_id: event[:external_account_id])
      next unless channel

      record = ::Arroyo::SocialComments::ImportService.new(channel: channel, attributes: event[:attributes]).perform
      next unless record && record.media_id.present? && !record.deleted_at?

      { channel_id: channel.id, platform: channel.platform, api_version: channel.api_version, media_id: record.media_id }
    end
    render json: { accepted: true, posts: posts.uniq }
  end

  def enrich
    channel = ::Arroyo::SocialChannel.where(account: Current.account).find(params.require(:channel_id))
    link = params.require(:post_url)
    raise ::Arroyo::SocialComments::Error, 'invalid_link' unless ::Arroyo::SocialComment.safe_url?(link)

    channel.comments.where(media_id: params.require(:media_id)).find_each { |record| record.update!(post_url: link) }
    render json: { updated: true }
  end

  def claim
    render json: { replies: delivery.claim }
  end

  def acknowledge
    record = delivery.acknowledge(params[:id], **params.permit(:claim_token, :status, :remote_reply_id, :error_message).to_h.symbolize_keys)
    render json: presenter.reply(record)
  end

  def retry
    record = ::Arroyo::SocialReply.where(account: Current.account, comment_id: visible_comments.select(:id)).find(params[:id])
    raise ::Arroyo::SocialComments::Error.new('humans_only', :forbidden) if request.headers['api_access_token'].present?

    delivery.retry!(record, Current.user)
    render json: presenter.reply(record)
  end

  private

  def filtered_comments
    records = visible_comments.where.not(conversation_id: nil)
    records = records.joins(:channel).where(arroyo_social_channels: { platform: params[:platform] }) if params[:platform].present?
    return records if params[:status].blank?

    replies = ::Arroyo::SocialReply.where(account: Current.account)
    return records.where.not(id: replies.select(:comment_id)) if params[:status] == 'unanswered'

    records.where(id: replies.where(status: params[:status]).select(:comment_id))
  end

  def visible_channels
    ::Arroyo::SocialChannel.visible_to(Current.account_user)
  end

  def visible_comments
    ::Arroyo::SocialComment.where(account: Current.account, channel_id: visible_channels.select(:id))
  end

  def channel_params
    params.require(:channel).permit(:name, :platform, :external_account_id, :api_version, user_ids: [])
  end

  def require_enabled
    raise ::Arroyo::SocialComments::Error.new('disabled', :forbidden) unless ::Arroyo::Setting.for(Current.account).feature_enabled?(:social_comments)
  end

  def presenter
    @presenter ||= ::Arroyo::SocialComments::Presenter.new
  end

  def delivery
    ::Arroyo::SocialComments::DeliveryService.new(account: Current.account)
  end

  def render_social_error(error)
    render json: { error: error.message }, status: error.status
  end
end

class Api::V1::Accounts::Conversations::MessagesController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_api_inbox, only: :update
  # ARROYO: solo sesiones humanas pueden crear o reintentar respuestas públicas.
  before_action :ensure_arroyo_human_reply, only: [:create, :retry]
  # ARROYO: la procedencia humana no puede forjarse mediante parámetros ni macros/jobs.
  around_action :with_arroyo_human_reply_context, only: :create
  rescue_from ::Arroyo::SocialComments::Error, with: :render_arroyo_social_error

  def index
    @messages = message_finder.perform
  end

  def create
    user = Current.user || @resource
    mb = Messages::MessageBuilder.new(user, @conversation, params)
    @message = mb.perform
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def update
    Messages::StatusUpdateService.new(message, permitted_params[:status], permitted_params[:external_error]).perform
    @message = message
  end

  def destroy
    # ARROYO: borrar un mensaje local no retira un comentario publicado ni cancela su intento.
    raise ::Arroyo::SocialComments::Error, 'cannot_delete_reply' if ::Arroyo::SocialReply.exists?(account: Current.account, message: message)

    ActiveRecord::Base.transaction do
      message.update!(content: I18n.t('conversations.messages.deleted'), content_type: :text, content_attributes: { deleted: true })
      message.attachments.destroy_all
    end
  end

  def retry
    return if message.blank?

    # ARROYO: conservar el estado/idempotencia de la publicación, sin usar el reenvío genérico.
    social_reply = ::Arroyo::SocialReply.find_by(account: Current.account, message: message)
    if social_reply
      ::Arroyo::SocialComments::DeliveryService.new(account: Current.account).retry!(social_reply, Current.user)
      @message = message.reload
      return render :create
    end

    service = Messages::StatusUpdateService.new(message, 'sent')
    service.perform
    message.update!(content_attributes: {})
    ::SendReplyJob.perform_later(message.id)
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def translate
    return head :ok if already_translated_content_available?

    translated_content = Integrations::GoogleTranslate::ProcessorService.new(
      message: message,
      target_language: permitted_params[:target_language]
    ).perform

    if translated_content.present?
      translations = {}
      translations[permitted_params[:target_language]] = translated_content
      translations = message.translations.merge!(translations) if message.translations.present?
      message.update!(translations: translations)
    end

    render json: { content: translated_content }
  end

  private

  # ARROYO: contexto limitado a la creación directa autenticada; nunca se propaga a jobs.
  def with_arroyo_human_reply_context(&)
    human = Current.user if request.headers['api_access_token'].blank?
    ::Arroyo::SocialComments::HumanReplyContext.set(user: human, &)
  end

  # ARROYO: una API key de integración no equivale a una respuesta escrita por el vendedor.
  def ensure_arroyo_human_reply
    return unless request.headers['api_access_token'].present? && ::Arroyo::SocialChannel.for_inbox(@conversation.inbox)
    return if action_name == 'create' && (params[:message_type] == 'incoming' || ActiveModel::Type::Boolean.new.cast(params[:private]))

    raise ::Arroyo::SocialComments::Error.new('humans_only', :forbidden)
  end

  def render_arroyo_social_error(error)
    render json: { error: error.message }, status: error.status
  end

  def message
    @message ||= @conversation.messages.find(permitted_params[:id])
  end

  def message_finder
    @message_finder ||= MessageFinder.new(@conversation, params)
  end

  def permitted_params
    params.permit(:id, :target_language, :status, :external_error)
  end

  def already_translated_content_available?
    message.translations.present? && message.translations[permitted_params[:target_language]].present?
  end

  # API inbox check
  def ensure_api_inbox
    # Only API inboxes can update messages
    render json: { error: 'Message status update is only allowed for API inboxes' }, status: :forbidden unless @conversation.inbox.api?
  end
end

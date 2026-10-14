class Arroyo::SocialComments::Error < StandardError
  attr_reader :status

  def initialize(key, status = :unprocessable_entity)
    @status = status
    super(I18n.t("arroyo.social_comments.errors.#{key}"))
  end
end

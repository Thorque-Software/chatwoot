class Arroyo::Commercial::Error < StandardError
  attr_reader :code, :status

  def initialize(code, status: :unprocessable_entity)
    @code = code
    @status = status
    super(I18n.t("arroyo.commercial.errors.#{code}"))
  end
end

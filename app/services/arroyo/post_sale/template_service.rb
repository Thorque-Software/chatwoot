class Arroyo::PostSale::TemplateService
  pattr_initialize [:purchase!, :stage!]

  def perform
    return unless template && supported_components?(template)
    return unless valid_body?

    { content: body.gsub(/\{\{\s*([^{}]+?)\s*\}\}/) { variables[Regexp.last_match(1)] }, template_params: parameters }
  end

  private

  def template
    @template ||= Array(purchase.inbox.channel.message_templates).find do |item|
      item['name'] == "postventa_#{stage}" && item['language']&.downcase == 'es_ar' && item['status']&.downcase == 'approved'
    end
  end

  def body
    @body ||= Array(template['components']).find { |item| item['type'] == 'BODY' }&.fetch('text', nil)
  end

  def names
    @names ||= body.scan(/\{\{\s*([^{}]+?)\s*\}\}/).flatten.uniq
  end

  def valid_body?
    return false if body.blank?
    return false if names.any? && template['parameter_format'] != 'NAMED'

    names.all? { |name| variables[name].present? }
  end

  def parameters
    template.slice('name', 'language', 'category').merge('processed_params' => { 'body' => variables.slice(*names) })
  end

  def variables
    @variables ||= { 'asesor' => purchase.seller&.available_name, 'producto' => purchase.product }
  end

  def supported_components?(template)
    Array(template['components']).none? do |item|
      (item['type'] == 'HEADER' && item['format'] != 'TEXT') ||
        (item['type'] != 'BODY' && item.to_json.include?('{{'))
    end
  end
end

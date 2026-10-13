class Arroyo::PostSale::ResolveService
  pattr_initialize [:follow_up!, :user!, :method!, :note!]

  def perform
    validate_resolution
    follow_up.purchase.with_lock do
      follow_up.with_lock do
        next if follow_up.manual_status == 'resolved'
        raise Arroyo::PostSale::Error, 'no_pending_alert' unless follow_up.manual_status == 'pending'

        follow_up.update!(resolution_attributes)
      end
      Arroyo::PostSale::LabelService.clear_resolved(follow_up.conversation)
    end
    follow_up
  end

  private

  def validate_resolution
    return if Arroyo::FollowUp::RESOLUTION_METHODS.include?(method) && note.to_s.strip.present?

    raise Arroyo::PostSale::Error, 'invalid_resolution'
  end

  def resolution_attributes
    { manual_status: 'resolved', resolved_by: user, resolved_at: Time.current,
      resolution_method: method, resolution_note: note.to_s.strip }
  end
end

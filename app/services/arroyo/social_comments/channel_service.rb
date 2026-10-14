class Arroyo::SocialComments::ChannelService
  pattr_initialize [:account!]

  def create!(name:, platform:, user_ids:, external_account_id: nil, api_version: nil)
    ids = Array(user_ids).map(&:to_i).uniq
    raise Arroyo::SocialComments::Error, 'invalid_members' if ids.empty? || (ids - account.account_users.pluck(:user_id)).any?

    Arroyo::SocialChannel.transaction do
      api = Channel::Api.create!(account: account, additional_attributes: { 'arroyo_social_comments' => true })
      inbox = account.inboxes.create!(channel: api, name: name, timezone: 'America/Argentina/Buenos_Aires', enable_auto_assignment: false)
      ids.each { |id| InboxMember.create!(inbox: inbox, user_id: id) }
      Arroyo::SocialChannel.create!(account: account, inbox: inbox, platform: platform,
                                    external_account_id: external_account_id.presence, api_version: api_version.presence)
    end
  end
end

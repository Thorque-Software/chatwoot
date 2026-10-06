# == Schema Information
#
# Table name: arroyo_assignment_events
#
#  id              :bigint           not null, primary key
#  created_at      :datetime         not null
#  account_id      :bigint           not null
#  assignee_id     :bigint           not null
#  conversation_id :bigint           not null
#  inbox_id        :bigint           not null
#
# Indexes
#
#  index_arroyo_assignment_events_on_account_id_and_created_at  (account_id,created_at)
#  index_arroyo_assignment_events_on_conversation_id            (conversation_id)
#
# Registro de cada asignación de conversación, para la métrica "Conversaciones nuevas asignadas"
# del panel de vendedores. reporting_events no guarda asignaciones (ver ARCHITECTURE_NOTES D7).
class Arroyo::AssignmentEvent < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  belongs_to :inbox
  belongs_to :assignee, class_name: 'User'
end

class CreateArroyoAssignmentEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :arroyo_assignment_events do |t|
      t.references :account, null: false, index: false
      t.references :conversation, null: false
      t.references :inbox, null: false, index: false
      t.references :assignee, null: false, index: false
      t.datetime :created_at, null: false
    end
    add_index :arroyo_assignment_events, [:account_id, :created_at]
  end
end

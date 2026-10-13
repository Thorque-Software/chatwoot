class CreateArroyoPostSaleTracking < ActiveRecord::Migration[7.1]
  def change
    create_table :arroyo_post_sale_purchases do |t|
      purchase_columns(t)
      t.timestamps
    end
    add_index :arroyo_post_sale_purchases, :reference, unique: true
    add_index :arroyo_post_sale_purchases, [:account_id, :purchased_at], name: 'index_arroyo_purchases_on_account_and_date'
    create_table :arroyo_follow_ups do |t|
      follow_up_columns(t)
      t.timestamps
    end
    add_index :arroyo_follow_ups, [:purchase_id, :stage], unique: true
    add_index :arroyo_follow_ups, :message_id, unique: true, name: 'unique_arroyo_follow_up_message'
    add_index :arroyo_follow_ups, [:account_id, :manual_status]
    add_index :arroyo_follow_ups, [:status, :scheduled_at]
  end

  private

  def purchase_columns(table)
    purchase_references(table)
    table.string :reference, null: false
    table.datetime :purchased_at, null: false
    table.datetime :recorded_at, null: false
    table.string :product
    table.string :rubro
    table.integer :revision, null: false, default: 1
    table.integer :planned_revision, null: false, default: 0
    table.datetime :cancelled_at
    table.jsonb :date_changes, null: false, default: []
  end

  def purchase_references(table)
    table.references :account, null: false, foreign_key: { on_delete: :cascade }
    table.references :conversation, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
    table.references :contact, null: false, foreign_key: { on_delete: :cascade }
    table.references :inbox, null: false, foreign_key: { on_delete: :cascade }
    table.references :seller, foreign_key: { to_table: :users, on_delete: :nullify }
  end

  def follow_up_columns(table)
    table.references :account, null: false, foreign_key: { on_delete: :cascade }
    table.references :purchase, null: false, foreign_key: { to_table: :arroyo_post_sale_purchases, on_delete: :cascade }
    table.string :stage, null: false
    table.string :status, null: false, default: 'awaiting_plan'
    table.datetime :scheduled_at
    table.datetime :attempted_at
    table.references :message, index: false, foreign_key: { on_delete: :nullify }
    table.string :execution_id
    table.string :channel_used
    table.string :template_name
    delivery_columns(table)
    alert_columns(table)
  end

  def delivery_columns(table)
    table.string :error_code
    table.text :error_message
    table.datetime :delivered_at
    table.datetime :read_at
  end

  def alert_columns(table)
    table.string :manual_status
    table.datetime :alerted_at
    table.references :alert_assignee, foreign_key: { to_table: :users, on_delete: :nullify }
    table.references :alert_message, foreign_key: { to_table: :messages, on_delete: :nullify }
    table.references :resolved_by, foreign_key: { to_table: :users, on_delete: :nullify }
    table.datetime :resolved_at
    table.string :resolution_method
    table.text :resolution_note
  end
end

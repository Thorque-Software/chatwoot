class CreateArroyoCommercialOpportunities < ActiveRecord::Migration[7.1]
  def change
    create_opportunities
    create_events
    link_purchases
  end

  private

  def create_opportunities
    create_table :arroyo_opportunities do |table|
      opportunity_references(table)
      opportunity_attributes(table)
      opportunity_dates(table)
      table.timestamps
    end
    add_index :arroyo_opportunities, :reference, unique: true
    add_index :arroyo_opportunities, [:account_id, :request_key], unique: true
    add_index :arroyo_opportunities, [:account_id, :started_at]
    add_index :arroyo_opportunities, :conversation_id, unique: true,
                                                       where: "state NOT IN ('won', 'lost')", name: 'unique_arroyo_active_opportunity'
  end

  def opportunity_references(table)
    table.references :account, null: false, foreign_key: true
    table.references :conversation, null: false, foreign_key: true
    table.references :contact, null: false, foreign_key: true
    table.references :inbox, null: false, foreign_key: true
    table.references :assignee, foreign_key: { to_table: :users }
    table.references :first_assignee, foreign_key: { to_table: :users }
    table.references :result_user, foreign_key: { to_table: :users }
  end

  def opportunity_attributes(table)
    table.string :reference, null: false
    table.string :request_key
    table.string :state, null: false, default: 'unassigned'
    table.string :coverage, null: false, default: 'complete'
    table.string :product
  end

  def opportunity_dates(table)
    table.datetime :started_at, null: false
    table.datetime :ownership_started_at
    table.datetime :first_human_at
    table.datetime :last_human_at
    table.datetime :last_client_at
    table.datetime :pending_since
    table.datetime :attention_due_at
    table.datetime :outcome_at
  end

  def create_events
    create_table :arroyo_opportunity_events do |table|
      table.references :opportunity, null: false, foreign_key: { to_table: :arroyo_opportunities }
      table.references :actor, foreign_key: { to_table: :users }
      table.references :message, foreign_key: true
      table.string :kind, null: false
      table.string :source_key, null: false
      table.string :origin, null: false
      table.datetime :occurred_at, null: false
      table.jsonb :data, null: false, default: {}
      table.timestamps
    end
    add_index :arroyo_opportunity_events, [:opportunity_id, :source_key], unique: true, name: 'unique_arroyo_opportunity_event'
    add_index :arroyo_opportunity_events, [:kind, :occurred_at]
  end

  def link_purchases
    add_reference :arroyo_post_sale_purchases, :opportunity, foreign_key: { to_table: :arroyo_opportunities }, index: { unique: true }
    remove_index :arroyo_post_sale_purchases, :conversation_id
    add_index :arroyo_post_sale_purchases, :conversation_id
    add_column :arroyo_follow_ups, :cancellation_reason, :string
  end
end

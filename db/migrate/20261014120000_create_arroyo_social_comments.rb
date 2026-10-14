class CreateArroyoSocialComments < ActiveRecord::Migration[7.1]
  def change
    create_channels
    create_comments
    create_replies
  end

  private

  def create_channels
    create_table :arroyo_social_channels do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :inbox, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.string :platform, null: false
      t.string :external_account_id
      t.string :api_version
      t.boolean :publishing_enabled, null: false, default: false
      t.timestamps
    end
    add_index(:arroyo_social_channels, [:account_id, :platform, :external_account_id],
              unique: true, where: 'external_account_id IS NOT NULL', name: 'arroyo_social_channel_external_account')
  end

  def create_comments
    create_table :arroyo_social_comments do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :channel, null: false, foreign_key: { to_table: :arroyo_social_channels, on_delete: :cascade }
      t.references :conversation, foreign_key: { on_delete: :nullify }
      t.references :message, foreign_key: { on_delete: :nullify }
      t.string :remote_id, null: false
      t.string :thread_id, null: false
      t.string :parent_id
      t.string :author_id
      t.string :author_name
      t.text :body
      t.string :media_id
      t.text :post_url
      t.text :comment_url
      t.datetime :remote_updated_at, null: false
      t.datetime :deleted_at
      t.timestamps
    end
    add_comment_indexes
  end

  def add_comment_indexes
    add_index :arroyo_social_comments, [:channel_id, :remote_id], unique: true
    add_index :arroyo_social_comments, [:channel_id, :thread_id]
    add_index :arroyo_social_comments, [:account_id, :created_at]
  end

  def create_replies
    create_table :arroyo_social_replies do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :comment, null: false, foreign_key: { to_table: :arroyo_social_comments, on_delete: :cascade }
      t.references :message, index: { unique: true }, foreign_key: { on_delete: :nullify }
      t.references :sender, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :client_request_id
      t.string :status, null: false, default: 'pending_configuration'
      t.string :claim_token
      t.datetime :claimed_at
      t.datetime :published_at
      t.string :remote_reply_id
      t.text :error_message
      t.timestamps
    end
    add_index :arroyo_social_replies, [:comment_id, :client_request_id], unique: true, name: 'arroyo_social_reply_request'
    add_index :arroyo_social_replies, [:account_id, :status, :created_at], name: 'arroyo_social_reply_queue'
  end
end

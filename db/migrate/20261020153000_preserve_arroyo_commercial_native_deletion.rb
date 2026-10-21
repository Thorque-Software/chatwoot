class PreserveArroyoCommercialNativeDeletion < ActiveRecord::Migration[7.1]
  def change
    %i[account conversation contact inbox].each do |parent|
      replace_key(:arroyo_opportunities, parent.to_s.pluralize, "#{parent}_id", :cascade)
    end
    %i[assignee first_assignee result_user].each do |parent|
      replace_key(:arroyo_opportunities, :users, "#{parent}_id", :nullify)
    end
    replace_key(:arroyo_opportunity_events, :arroyo_opportunities, :opportunity_id, :cascade)
    replace_key(:arroyo_opportunity_events, :messages, :message_id, :nullify)
    replace_key(:arroyo_opportunity_events, :users, :actor_id, :nullify)
    replace_key(:arroyo_post_sale_purchases, :arroyo_opportunities, :opportunity_id, :nullify)
  end

  private

  def replace_key(table, target, column, on_delete)
    remove_foreign_key table, target, column: column
    add_foreign_key table, target, column: column, on_delete: on_delete
  end
end

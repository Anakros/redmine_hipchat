class AddHipChatFromToProject < ActiveRecord::Migration
  def change
    add_column :projects, :hipchat_from, :string, :default => '', :null => false
  end
end

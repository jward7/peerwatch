class CreatePeerwatchTables < ActiveRecord::Migration[8.0]
  def change
    create_table :peerwatch_peers do |t|
      t.string :name, null: false
      t.string :url, null: false
      t.string :health_path, null: false, default: "/up"
      t.string :ip
      t.string :environment
      t.json :contact_emails, null: false, default: []
      t.datetime :maintenance_until
      t.string :maintenance_note
      t.datetime :revision_at, precision: 6, null: false
      t.datetime :removed_at
      t.timestamps
    end
    add_index :peerwatch_peers, :name, unique: true

    create_table :peerwatch_checks do |t|
      t.string :peer_name, null: false
      t.datetime :checked_at, null: false
      t.string :state, null: false
      t.integer :status_code
      t.integer :latency_ms
      t.string :error_class
      t.string :cause
    end
    add_index :peerwatch_checks, [ :peer_name, :checked_at ]

    create_table :peerwatch_incidents do |t|
      t.string :peer_name, null: false
      t.datetime :started_at, null: false
      t.datetime :resolved_at
      t.boolean :planned, null: false, default: false
      t.datetime :notified_at
      t.datetime :alerted_at
      t.string :alerted_by
      t.datetime :recovery_alerted_at
      t.timestamps
    end
    add_index :peerwatch_incidents, [ :peer_name, :resolved_at ]
  end
end

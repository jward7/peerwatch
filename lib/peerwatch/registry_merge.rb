module Peerwatch
  # Applies registry rows from another app. Per name, the newest revision_at
  # wins; an equal or older one is ignored, so merging is idempotent.
  module RegistryMerge
    module_function

    # Returns the number of rows applied. One bad row never stops the rest.
    def call(rows)
      return 0 unless rows.is_a?(Array)

      rows.count do |row|
        Peerwatch.quietly("registry merge") { apply(row) } == true
      end
    end

    def apply(row)
      return false unless row.is_a?(Hash)

      row = row.stringify_keys.slice(*Peer::REGISTRY_FIELDS)
      incoming_at = ActiveModel::Type::DateTime.new(precision: 6).cast(row["revision_at"])
      return false if incoming_at.nil?

      peer = Peer.find_or_initialize_by(name: row["name"].to_s)
      return false if peer.persisted? && peer.revision_at >= incoming_at

      peer.assign_attributes(row.except("name"))
      peer.revision_at = incoming_at
      peer.syncing = true
      peer.save
    end
  end
end

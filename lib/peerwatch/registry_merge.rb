module Peerwatch
  # Applies registry rows from another app. Per name, the newest revision_at
  # wins; an equal or older one is ignored, so merging is idempotent.
  #
  # A row stamped more than MAX_CLOCK_SKEW in the future is rejected, so an app
  # whose clock runs fast cannot pin a row against every later edit. The row
  # is offered again on the next pull and accepted once real time catches up.
  module RegistryMerge
    MAX_CLOCK_SKEW = 5.minutes

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

      if incoming_at > Time.current + MAX_CLOCK_SKEW
        Peerwatch.logger&.warn(
          "[Peerwatch] registry merge: ignored #{row["name"].inspect}, revision_at " \
          "#{incoming_at.utc.iso8601} is in the future; check the sending app's clock"
        )
        return false
      end

      peer = Peer.find_or_initialize_by(name: row["name"].to_s)
      return false if peer.persisted? && peer.revision_at >= incoming_at

      peer.assign_attributes(row.except("name"))
      peer.revision_at = incoming_at
      peer.syncing = true
      return true if peer.save

      # Names the row and the rule, never the token. Messages name the
      # field and the rule broken, not the offending value.
      Peerwatch.logger&.warn(
        "[Peerwatch] registry merge: ignored #{peer.name.inspect}: #{peer.errors.full_messages.to_sentence}"
      )
      false
    end
  end
end

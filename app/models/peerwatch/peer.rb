require "uri"

module Peerwatch
  class Peer < ApplicationRecord
    NAME_FORMAT = /\A[a-z0-9][a-z0-9_-]*\z/
    REGISTRY_FIELDS = %w[name url health_path ip environment contact_emails
                         maintenance_until maintenance_note revision_at removed_at].freeze
    TIME_FIELDS = %w[maintenance_until revision_at removed_at].freeze

    # Set by RegistryMerge so an incoming revision_at is kept, not re-stamped.
    attr_accessor :syncing

    validates :name, presence: true, uniqueness: true, format: { with: NAME_FORMAT, allow_blank: true }
    validates :url, presence: true
    validates :revision_at, presence: true, if: :syncing
    validate :url_must_be_web_address
    validate :health_path_must_be_absolute
    validate :contact_emails_must_be_valid
    validate :must_follow_this_apps_rules

    before_save :stamp_revision, unless: :syncing

    scope :live, -> { where(removed_at: nil) }

    # Whether this app's rules let it contact this peer and email its
    # contacts: public addresses only (unless allow_private_addresses), and
    # the allowed_peer_hosts and allowed_contact_domains lists. Validation
    # enforces the same rules on save, but rules can be tightened after a row
    # exists, so the probe job, sync and alerting ask this on every read.
    def permitted?
      rule_violations.empty?
    end

    # Why this app refuses the row, as full sentences; empty when permitted.
    def blocked_reasons
      rule_violations.map { |attribute, message| errors.full_message(attribute, message) }
    end

    # [[attribute, message], ...] for every one of this app's rules the row breaks.
    def rule_violations
      config = Peerwatch.config
      violations = []

      if ip.present?
        if Address.parse(ip).nil?
          violations << [ :ip, "is not an IP address" ]
        elsif !config.allow_private_addresses && !Address.public?(ip)
          violations << [ :ip, "must be a public address" ]
        end
      end

      host = url_hostname
      if host && !config.allow_private_addresses
        if Address.localhost_name?(host)
          violations << [ :url, "must not point at localhost" ]
        elsif Address.ip_literal?(host) && !Address.public?(host)
          violations << [ :url, "must not point at a loopback, private or link-local address" ]
        end
      end
      if host && config.allowed_peer_hosts &&
         Array(config.allowed_peer_hosts).map { |h| Address.normalize_host(h) }.exclude?(Address.normalize_host(host))
        violations << [ :url, "host is not in this app's allowed_peer_hosts" ]
      end

      if config.allowed_contact_domains
        domains = Array(config.allowed_contact_domains).map { |d| d.to_s.strip.downcase }
        outside = Array(contact_emails).grep(String).reject { |e| domains.include?(e.rpartition("@").last.downcase) }
        violations << [ :contact_emails, "must all be at a domain in this app's allowed_contact_domains" ] if outside.any?
      end

      violations
    end

    def in_maintenance?(at = Time.current)
      maintenance_until.present? && maintenance_until > at
    end

    def self?
      name == Peerwatch.config.self_name
    end

    def health_url
      url.to_s.chomp("/") + health_path.to_s
    end

    # A tombstone: rows are never destroyed, so the removal can sync.
    def remove!
      update!(removed_at: Time.current)
    end

    # A new peer, or the removed one with the same name brought back with
    # these attributes. Reviving keeps the row, so saving it stamps a newer
    # revision that syncs over the tombstone in every other app. Unsaved.
    def self.new_or_revived(attributes)
      attributes = attributes.to_h.stringify_keys
      peer = where.not(removed_at: nil).find_by(name: attributes["name"].to_s) || new
      peer.assign_attributes(attributes)
      peer.removed_at = nil
      peer
    end

    def registry_row
      REGISTRY_FIELDS.index_with do |field|
        value = public_send(field)
        TIME_FIELDS.include?(field) ? value&.utc&.iso8601(6) : value
      end
    end

    def contact_emails_text
      Array(contact_emails).join("\n")
    end

    def contact_emails_text=(text)
      self.contact_emails = text.to_s.split(/[\n,]/).map(&:strip).reject(&:blank?).uniq
    end

    private

    def stamp_revision
      self.revision_at = Time.current
    end

    def url_must_be_web_address
      return if url.blank?

      uri = URI.parse(url)
      allowed = Peerwatch.config.allow_http ? %w[http https] : %w[https]
      unless allowed.include?(uri.scheme) && uri.host.present?
        errors.add(:url, Peerwatch.config.allow_http ? "must be an http(s) URL with a host" : "must be an https URL with a host")
      end
    rescue URI::InvalidURIError
      errors.add(:url, "is not a valid URL")
    end

    def must_follow_this_apps_rules
      rule_violations.each { |attribute, message| errors.add(attribute, message) }
    end

    def url_hostname
      URI.parse(url.to_s).hostname.presence
    rescue URI::InvalidURIError
      nil
    end

    def health_path_must_be_absolute
      return errors.add(:health_path, "must start with /") unless health_path.to_s.start_with?("/")
      return if errors[:url].any?

      URI.parse(health_url)
    rescue URI::InvalidURIError
      errors.add(:health_path, "does not make a valid URL")
    end

    def contact_emails_must_be_valid
      emails = contact_emails
      unless emails.is_a?(Array) && emails.all? { |e| e.is_a?(String) && e.match?(URI::MailTo::EMAIL_REGEXP) }
        errors.add(:contact_emails, "must all be valid email addresses")
      end
    end
  end
end

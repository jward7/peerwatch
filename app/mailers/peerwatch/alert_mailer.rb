module Peerwatch
  # Inherits the host's mailer so its From address, interceptors and
  # suppression rules apply.
  #
  # Mail goes only to a peer this app's rules permit, checked again when the
  # mail is built, so a rule tightened while it waited in the queue still
  # holds. Without a call to mail, Action Mailer sends nothing.
  class AlertMailer < Peerwatch.config.mailer_parent.constantize
    def down(peer, incident, overrun: false)
      return unless peer.permitted?

      @body = AlertText.down_body(peer, incident, overrun: overrun)
      mail(to: peer.contact_emails, subject: AlertText.down_subject(peer, incident, overrun: overrun))
    end

    def recovered(peer, incident)
      return unless peer.permitted?

      @body = AlertText.recovered_body(peer, incident)
      mail(to: peer.contact_emails, subject: AlertText.recovered_subject(peer, incident))
    end
  end
end

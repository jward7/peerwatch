module Peerwatch
  # Inherits the host's mailer so its From address, interceptors and
  # suppression rules apply.
  class AlertMailer < Peerwatch.config.mailer_parent.constantize
    def down(peer, incident, overrun: false)
      @body = AlertText.down_body(peer, incident, overrun: overrun)
      mail(to: peer.contact_emails, subject: AlertText.down_subject(peer, incident, overrun: overrun))
    end

    def recovered(peer, incident)
      @body = AlertText.recovered_body(peer, incident)
      mail(to: peer.contact_emails, subject: AlertText.recovered_subject(peer, incident))
    end
  end
end

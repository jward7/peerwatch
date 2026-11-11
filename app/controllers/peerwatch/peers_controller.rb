module Peerwatch
  class PeersController < AdminController
    before_action :set_peer, only: %i[edit update destroy]

    def index
      @peers = Peer.live.order(:name)
      @removed_peers = Peer.where.not(removed_at: nil).order(:name)
    end

    def new
      @peer = Peer.new
    end

    def create
      @peer = Peer.new_or_revived(peer_params(:name))
      revived = @peer.persisted?
      if @peer.save
        pushed(revived ? "restored" : "saved")
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @peer.update(peer_params)
        pushed
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @peer.remove!
      pushed("removed")
    end

    private

    def set_peer
      @peer = Peer.live.find(params[:id])
    end

    def pushed(verb = "saved")
      PushJob.perform_later(@peer.name)
      redirect_to peerwatch.mesh_peers_path, notice: "#{@peer.name} #{verb}; the change is being sent to the other apps."
    end

    # name is set on create only: it is the key every other app syncs on.
    def peer_params(*extra)
      params.require(:peer).permit(:url, :health_path, :ip, :environment, :contact_emails_text,
                                   :maintenance_until, :maintenance_note, *extra)
    end
  end
end

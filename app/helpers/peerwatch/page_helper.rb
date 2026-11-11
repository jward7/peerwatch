module Peerwatch
  # Ties each admin page into the host's layout without knowing anything about
  # it: the page sets content_for(:title) and hands its title, breadcrumbs and
  # section to peerwatch/_page_chrome, which renders nothing until the host
  # overrides it (bin/rails g peerwatch:views -v chrome).
  module PageHelper
    # section: :dashboard or :peers. trail: further labels after the section,
    # such as "Add a peer". The last crumb has no link.
    def peerwatch_page(section, *trail)
      crumbs = [ [ "Peerwatch", peerwatch.dashboard_path ] ]
      crumbs << [ "Peers", peerwatch.mesh_peers_path ] if section == :peers
      crumbs.concat(trail.map { |label| [ label, nil ] })
      crumbs[-1] = [ crumbs.last.first, nil ]
      title = crumbs.map(&:first).join(" · ")

      content_for(:title, title) unless content_for?(:title)
      render "peerwatch/page_chrome", section: section, title: title, crumbs: crumbs
    end
  end
end

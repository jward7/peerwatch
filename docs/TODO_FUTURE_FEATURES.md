# Future features

Ideas that have been considered and deliberately deferred. Nothing here is promised; each
entry says why it waits and what would bring it forward.

## 1. Per-app identity for registry writes

**The problem.** The whole mesh shares one token. Whoever holds it can write any registry
row: add, change or remove peers (within `allowed_peer_hosts`), change contacts (within
`allowed_contact_domains`), and declare a maintenance window for any peer, which
silences that peer's alerts. A token copied from one app's credentials is enough to
quietly switch off alerting for every app.

**Why "only accept rows the sender owns" is not enough on its own.** With a shared
secret, the receiving app cannot tell which app sent a request. A token holder can
claim to be any app, so an ownership check would only be as strong as the claim.

**Sketch of a real fix.**

- Each app has its own keypair. The private key lives in that app's credentials; the
  public key is part of its registry row.
- An app signs its own row (including maintenance windows) with its private key. Other
  apps accept a change to a row only if it carries a valid signature from that row's
  key.
- A peer's public key is pinned when an admin first adds the peer, the same way an SSH
  host key is (trust on first use). Changing a key needs an admin on each app, or a
  signature from the old key.
- Editing another app's row from one admin page becomes a request that the owning app
  applies and signs, rather than a direct write.
- The shared token can stay as a coarse "is this a mesh member" check for reading status
  and the registry, or be replaced by per-app keys entirely.

**What limits the risk today.** `allowed_peer_hosts` and `allowed_contact_domains` stop a
token holder from sending probes, or alert mail, outside your own hosts and domains. The
remaining exposure is silencing alerts with a maintenance window, and adding or removing
peers within the allowlist. Keep the token in a credentials store and rotate it if it
may have leaked.

**When to revisit.** After the mesh has run in production for a few weeks, or sooner if
the mesh grows beyond a handful of apps run by one person.

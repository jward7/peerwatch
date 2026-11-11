# Security policy

## Reporting a vulnerability

Please report a vulnerability privately, through GitHub's private vulnerability
reporting: open the [Security tab](https://github.com/jward7/peerwatch/security) of the
repository and choose "Report a vulnerability". Do not open a public issue, and do not
include a real token, hostname or email address in the report; placeholders are enough.

Peerwatch is maintained by one person in their own time. Reports are read and handled on
a best-effort basis, and a fix is released as a new patch version with a CHANGELOG entry.

## Supported versions

Only the latest 0.x release receives fixes.

## Trust model

Every app in a mesh shares one token, and whoever holds it can read and edit the
registry in every app. What that allows, and how to limit it, is described in
[Security and trust model](README.md#security-and-trust-model).

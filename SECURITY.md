# Security

## Reporting a vulnerability

Please report security issues privately rather than in a public issue.

- Use GitHub's [private vulnerability reporting](https://github.com/souriscloud/optakube/security/advisories/new), or
- email **security@souris.cloud**

Please include the OptaKube version, macOS version, and enough detail to reproduce.
You'll get an acknowledgement within a few days. If the report is valid, I'll aim to ship
a fix in the next release and credit you in the changelog unless you'd rather not be.

Only the **latest release** is supported. Fixes ship forward, not as patches to older
versions — OptaKube auto-updates via Sparkle, so the upgrade path is a restart.

## How OptaKube handles your credentials

Worth stating plainly, because it's the first question people ask about a Kubernetes GUI.

**Nothing leaves your machine except traffic to your own clusters.** There is no OptaKube
backend, no telemetry, and no analytics. The only outbound requests the app makes are:

- to the Kubernetes API servers in your kubeconfig,
- to `raw.githubusercontent.com` for the Sparkle update feed and to `github.com` to
  download an update,
- to `github.com` when you open a link, or use Help ▸ Send Feedback (which opens a
  pre-filled issue form in your browser — nothing is submitted until you press submit).

**Credentials are read, not stored.** OptaKube reads the kubeconfig files you point it at
and keeps the parsed credentials in memory for the lifetime of the process. It does not
copy them into its own storage. What it does persist, in `UserDefaults`, is limited to
kubeconfig *paths*, selected namespace and resource type per cluster, saved views, and
window geometry.

**TLS is pinned to your cluster's CA.** When your kubeconfig supplies a certificate
authority, that CA is installed as the sole trust anchor and evaluated with
`SecTrustEvaluateWithError` — the same behaviour as `kubectl`, so a self-hosted cluster
with a private CA works without weakening verification. `insecure-skip-tls-verify` is
honoured if you set it, and only if you set it.

**Client certificates.** Converting a PEM certificate and key into a `SecIdentity`
requires a PKCS#12 bundle, which means a short-lived temporary file inside the app's
per-user temporary directory. It is deleted immediately afterwards, including on the
error paths.

**Diagnostics in feedback.** The optional diagnostics line in Help ▸ Send Feedback
contains the app version, macOS version, and CPU architecture. Never cluster names,
server URLs, kubeconfig contents, or tokens.

**Subprocesses.** OptaKube shells out in three places: `openssl` to build the PKCS#12
bundle above, `kubectl` for port forwarding and pod exec, and your login shell for
kubeconfig `exec` credential plugins (so they pick up your `PATH` and profile, the same as
`kubectl`). Credential plugins run with the arguments your kubeconfig specifies.

## Update integrity

Releases are signed with a Developer ID certificate, notarized and stapled by Apple, and
the Sparkle appcast is EdDSA-signed. The public key is pinned in the app bundle
(`SUPublicEDKey`), so an update that isn't signed by the corresponding private key is
rejected. CI verifies on every commit that the published appcast is well-formed and that
its newest entry is signed and matches the shipped version.

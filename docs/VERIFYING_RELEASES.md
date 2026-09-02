# Verifying Thaw releases

Thaw ships macOS app builds intended for wide use. Releases are protected by
several layers. This page explains what those layers are and how you can check
them.

## What we sign

| Layer | What it proves | How it is produced |
| --- | --- | --- |
| **Apple Developer ID + notarization** | Binary came from the Thaw developer team and passed Apple’s notarization checks | Release GitHub Actions (signing + `notarytool`) |
| **Sparkle EdDSA** | Downloaded **update archives** (e.g. release ZIPs) match signatures produced with the project’s Sparkle private key; the app verifies them with `SUPublicEDKey` | Sparkle tools in the release pipeline sign update packages; public key embedded in the app (`Info.plist`). The appcast lists those updates over HTTPS; **feed-level** signing (`SURequireSignedFeed`) is not enabled |
| **Sigstore (cosign)** | GitHub Release **DMG** (and **SBOM**) blobs match a keyless cosign signature bundle uploaded beside the asset | Release workflow runs `cosign sign-blob` and attaches `*.sigstore.json` |
| **SLSA build provenance** | Subject was produced by this repository’s release pipeline; provenance is signed in a dedicated reusable workflow, so verification can be pinned to that signing identity (**SLSA v1.0 Build L2**) | `attest-build-provenance.yml` via `actions/attest`; stored in the GitHub Attestation Store and attached as `*.intoto.jsonl` |
| **CycloneDX SBOM** | Machine-readable inventory of the SwiftPM dependencies linked into the shipped app | Syft (pinned by version and archive digest) over the tagged source tree in the release workflow; uploaded as `Thaw_<tag>.cdx.json` |
| **Git tag signatures** | Important version tags are GPG-signed by the releaser | `git tag -s` (or equivalent) on release tags |

The Sparkle **private** key and Apple signing credentials are stored as CI
secrets. They are not kept on the public download host as the long-term way
users fetch builds (GitHub Releases / Homebrew are the distribution surfaces;
signing happens in CI before publish).

## Public Sparkle key

The EdDSA public key shipped inside Thaw:

```text
fQ2kWqCLfAPAxQX1rp8gVNoG9hlAV/Gmm7kMBbxFe+A=
```

Source of truth in-tree: `Thaw/Resources/Info.plist` key `SUPublicEDKey`.  
Appcast URL: `https://thaw-app.github.io/updates/appcast.xml` (`SUFeedURL`).
Legacy installs may still poll `https://stonerl.github.io/Thaw/appcast.xml`;
release CI mirrors the same `appcast.xml` there (see [RELEASES.md](RELEASES.md)).

How installers vs Sparkle payloads are split across repos:
[Release and update distribution](RELEASES.md).

Sparkle uses this key automatically when checking for updates inside the app.
You normally do **not** need to verify EdDSA by hand if you install a notarized
build and use in-app updates.

## Check a downloaded `.app` (Gatekeeper / notarization)

After unzipping a GitHub Release archive:

```sh
# Quarantine + Gatekeeper assessment (macOS)
spctl --assess --type execute -v /path/to/Thaw.app

# Notarization ticket staple / history (when available)
xcrun stapler validate /path/to/Thaw.app
codesign --verify --deep --strict --verbose=2 /path/to/Thaw.app
codesign -dv --verbose=4 /path/to/Thaw.app 2>&1 | grep -E 'Authority|TeamIdentifier|Timestamp'
```

Expect a **Developer ID Application** certificate and a successful assessment
for notarized release builds. Homebrew-installed builds follow Homebrew’s own
cask/bottle verification in addition to Apple’s checks.

## Check a release DMG with Sigstore

Release installers on `thaw-app/Thaw` include a companion
`Thaw.dmg.sigstore.json` (or similarly named) asset produced by cosign keyless
signing in CI, plus a `Thaw.dmg.sha256` checksum.

The identity pattern below is anchored to the release workflow on purpose: a
loose pattern such as `https://github.com/thaw-app/Thaw/` would also accept a
bundle signed by **any other workflow** in this repository. The trailing
`@refs/…` component records the ref the release was dispatched from; print the
certificate with `cosign verify-blob … --output json` if you want to pin it
exactly for a given release.

```sh
# Download DMG + bundle + checksum from the GitHub Release, then:
shasum -a 256 -c Thaw.dmg.sha256

cosign verify-blob \
  --bundle Thaw.dmg.sigstore.json \
  --certificate-identity-regexp '^https://github\.com/thaw-app/Thaw/\.github/workflows/release\.yml@refs/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  Thaw.dmg
```

## Check SLSA build provenance

Releases that went through the current release workflow also publish **GitHub
Artifact Attestations** for the installer DMG and SBOM. Provenance is generated
in [`.github/workflows/attest-build-provenance.yml`](../.github/workflows/attest-build-provenance.yml)
(a reusable workflow called from the release job) so the signing identity is
separate from the macOS build and its Apple/Sparkle credential boundary. That
gives **SLSA v1.0 Build L2** plus a signer you can pin.

It is not Build L3. L3 additionally requires the *build itself* to run inside the
trusted reusable workflow, so that the caller cannot influence what gets
attested. Here the macOS release job builds the DMG and passes the digest to the
signer. Moving the build into [`thaw-app/org-ci`](https://github.com/thaw-app/org-ci)
is the prerequisite for that claim.

The same attestation bundle is attached to the GitHub Release as
`Thaw.dmg.intoto.jsonl` / `Thaw_<tag>.cdx.json.intoto.jsonl` (for offline copy
and OpenSSF Scorecard Signed-Releases). Prefer verifying via the Attestation
Store:

```sh
# After downloading Thaw.dmg from the GitHub Release:
gh attestation verify Thaw.dmg --repo thaw-app/Thaw \
  --signer-workflow thaw-app/Thaw/.github/workflows/attest-build-provenance.yml

# Same for the SBOM:
gh attestation verify Thaw_2.0.0.cdx.json --repo thaw-app/Thaw \
  --signer-workflow thaw-app/Thaw/.github/workflows/attest-build-provenance.yml
```

`--signer-workflow` pins verification to the reusable provenance workflow: the
identity that actually signed, rather than any workflow in the repository.
Cosign `*.sigstore.json` bundles prove **blob integrity** from the release job;
attestations prove **build provenance**. Check both for a full release review.

## Check the release SBOM

Each Thaw GitHub Release that went through the current release workflow includes:

| Asset | Purpose |
| --- | --- |
| `Thaw_<tag>.cdx.json` | CycloneDX Software Bill of Materials for the release's resolved SwiftPM dependencies |
| `Thaw_<tag>.cdx.json.sha256` | SHA-256 of the SBOM file |
| `Thaw_<tag>.cdx.json.sigstore.json` | Cosign keyless signature bundle for the SBOM |
| `Thaw_<tag>.cdx.json.intoto.jsonl` | SLSA build provenance attestation bundle (also in the GitHub Attestation Store) |

```sh
# After downloading the three files from the GitHub Release:
shasum -a 256 -c Thaw_2.0.0.cdx.json.sha256

cosign verify-blob \
  --bundle Thaw_2.0.0.cdx.json.sigstore.json \
  --certificate-identity-regexp '^https://github\.com/thaw-app/Thaw/\.github/workflows/release\.yml@refs/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  Thaw_2.0.0.cdx.json
```

The SBOM is generated by Syft from the tagged source tree, whose
`Package.resolved` is the authoritative record of the SwiftPM dependencies linked
into the shipped app. Build output and CI workflow definitions are excluded, so
the SBOM describes shipped dependencies rather than release tooling. It is a
best-effort inventory, not a legal license notice.

## Check a Git version tag

1. Fetch tags and identify the release tag (e.g. `2.0.0-rc.1`).
2. **Before trusting a new key:** obtain the releaser’s **full GPG fingerprint**
   from a source you already trust (for example the Project Lead’s GitHub
   profile GPG keys page, or a fingerprint previously confirmed out-of-band).
   Compare that fingerprint **character-for-character** to the key you are about
   to import. Do not import or trust a key solely because `git verify-tag`
   downloaded it from a keyserver.
3. Verify the tag signature, then confirm the tag points at the intended release
   commit (the commit published for that GitHub Release).

```sh
git fetch --tags origin

# After importing a key whose full fingerprint you already matched to a trusted source:
git verify-tag <tag>    # e.g. 2.0.0-rc.1

# Tag must resolve to the intended release commit:
git rev-parse <tag>^{}
# Compare to the commit SHA shown on the GitHub Release page for that tag.
```

If `git verify-tag` reports an unknown key, import only after the fingerprint
check above succeeds.

## Install channels

- **GitHub Releases:** https://github.com/thaw-app/Thaw/releases  
- **Homebrew:** `brew install thaw` / `brew install thaw@beta`  
- **In-app updates:** Sparkle (stable / beta channels in Settings)

## Related

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [ASSURANCE_CASE.md](ASSURANCE_CASE.md)
- [SECURITY.md](../.github/SECURITY.md)

# Verifying Thaw releases

Thaw ships macOS app builds intended for wide use. Releases are protected by
several layers. This page explains what those layers are and how you can check
them.

## What we sign

| Layer | What it proves | How it is produced |
| --- | --- | --- |
| **Apple Developer ID + notarization** | Binary came from the Thaw developer team and passed Apple’s notarization checks | Release GitHub Actions (signing + `notarytool`) |
| **Sparkle EdDSA** | Appcast / update payload matches the project’s Sparkle private key | Sparkle tools in release pipeline; public key embedded in the app |
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
Appcast URL: `https://stonerl.github.io/Thaw/appcast.xml` (`SUFeedURL`).

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

## Check a Git version tag

```sh
git fetch --tags
git verify-tag <tag>    # e.g. 2.0.0-rc.1
```

Import the releaser’s public GPG key from their GitHub profile or a published
keyserver if `git verify-tag` reports an unknown key.

## Install channels

- **GitHub Releases:** https://github.com/stonerl/Thaw/releases  
- **Homebrew:** `brew install thaw` / `brew install thaw@beta`  
- **In-app updates:** Sparkle (stable / beta channels in Settings)

## Related

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [ASSURANCE_CASE.md](ASSURANCE_CASE.md)
- [SECURITY.md](../.github/SECURITY.md)

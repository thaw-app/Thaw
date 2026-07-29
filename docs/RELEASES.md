# Release and update distribution

How Thaw ships installers vs in-app updates.

## Who hosts what

| What | Where | URL pattern |
| --- | --- | --- |
| **Appcast** (`appcast.xml`) | [`thaw-app/updates`](https://github.com/thaw-app/updates) GitHub Pages | `https://thaw-app.github.io/updates/appcast.xml` |
| **Update payloads** (Sparkle ZIP + deltas, all channels) | `thaw-app/updates` GitHub Releases | `https://github.com/thaw-app/updates/releases/download/<tag>/…` |
| **DMG** (human installer) | [`thaw-app/Thaw`](https://github.com/thaw-app/Thaw) GitHub Releases only | `https://github.com/thaw-app/Thaw/releases/…` |

The app polls the appcast (`SUFeedURL` in `Thaw/Resources/Info.plist`). Sparkle
never downloads the DMG for in-app updates.

## Diagram

```mermaid
flowchart LR
  subgraph clients["Clients"]
    App["Thaw.app<br/>Sparkle updater"]
    Human["Human / Homebrew"]
  end

  subgraph updatesRepo["thaw-app/updates"]
    Pages["GitHub Pages<br/>appcast.xml"]
    UpRel["GitHub Releases<br/>ZIP + deltas"]
  end

  subgraph thawRepo["thaw-app/Thaw"]
    ThawRel["GitHub Releases<br/>DMG only"]
    CI["Release workflow"]
  end

  App -->|"1. GET SUFeedURL"| Pages
  Pages -->|"2. enclosure URLs"| App
  App -->|"3. download + EdDSA verify"| UpRel

  Human --> ThawRel

  CI -->|"publish ZIP/deltas + appcast"| updatesRepo
  CI -->|"publish DMG"| ThawRel
```

## In-app update path

1. App opens `https://thaw-app.github.io/updates/appcast.xml`.
2. Appcast lists the newest build and points at a ZIP (or delta) on `updates` releases.
3. Sparkle downloads that file from `thaw-app/updates`.
4. Sparkle verifies the EdDSA signature against `SUPublicEDKey`.
5. Sparkle installs the update.

The DMG is **not** on this path. It is for people who download an installer from
GitHub (or similar).

## What the release job does

Order matters: update assets are published **before** the Thaw DMG so a failed
`updates` publish does not leave a public installer without matching Sparkle
payloads.

1. Build and notarize.
2. Create Sparkle ZIP (and deltas when prior ZIPs exist).
3. Publish ZIP + deltas to **`thaw-app/updates`** (same tag).
4. Publish DMG to **`thaw-app/Thaw`**.
5. Push signed `appcast.xml` to **`thaw-app/updates`** `gh-pages`.

Workflow: [`.github/workflows/release.yml`](../.github/workflows/release.yml).  
Shared Sparkle action: [`thaw-app/org-ci` `sparkle-release`](https://github.com/thaw-app/org-ci/tree/main/actions/sparkle-release).

Required secret on Thaw: `UPDATES_GITHUB_TOKEN` (`contents: write` on
`thaw-app/updates`).

## Channels

Stable, beta, and alpha all use the same feed host and updates releases. The
appcast marks non-stable items with `sparkle:channel`. Tag suffixes map to
channels in the release workflow (`-beta` / `-rc` → beta, `-alpha` / `-nightly`
→ alpha).

## Legacy installs

Older builds may still poll `https://stonerl.github.io/Thaw/appcast.xml`
(GitHub Pages from [`stonerl/Thaw`](https://github.com/stonerl/Thaw) `main`,
path `/appcast.xml`). Release CI **mirrors** the same signed `appcast.xml` to
that repo after publishing to `thaw-app/updates`, so existing installs keep
updating without an HTTP redirect. Bridge / new builds ship the
`thaw-app.github.io/updates` `SUFeedURL` directly.

Historical enclosure URLs already in the appcast (for example old
`stonerl/Thaw` release ZIP links) stay as-is so EdDSA signatures remain valid.
Only **new** items point at `thaw-app/updates` releases.

## Related

- [Verifying releases](VERIFYING_RELEASES.md) — signatures, public key, how to check a build
- [Assurance case](ASSURANCE_CASE.md) — update authenticity claims

# Versions and update channels

## Find your version

Open the Apple menu, choose **About This Mac**, and read the macOS number. Then use this table.

| Your Mac runs | You get | Install |
|---|---|---|
| macOS 27 | Thaw 3, in beta | `brew install thaw@beta` |
| macOS 26 | Thaw 2, the stable release | `brew install thaw` |
| macOS 14 or 15 | Thaw 1 | Download from the [releases](https://github.com/thaw-app/Thaw/releases) |

Each major version is built for one macOS. Thaw 2 needs macOS 26, so a Mac on macOS 14 or 15 stays on Thaw 1.

No Homebrew? Every version is on the [releases](https://github.com/thaw-app/Thaw/releases) page as a disk image.

## Check which Thaw you have

1. Right-click Thaw's icon in the menu bar and choose **Settings…**.
2. Choose **About**.

The version is shown there, with a button that copies it.

## Pick an update channel

Thaw updates itself. The channel decides which updates it offers you.

1. Right-click Thaw's icon in the menu bar and choose **Settings…**.
2. Choose **About**.
3. Pick a channel.

| Channel | You are offered | Where you can pick it |
|---|---|---|
| Stable | Stable releases | Thaw 2 |
| Beta | Stable releases, plus betas and release candidates | Thaw 2 and Thaw 3 |
| Nightly | Stable releases, plus alphas and nightlies. Never betas. | Thaw 3. Thaw 2 calls it Alpha and shows it only on macOS 27. |

Thaw 3 has no Stable option yet, because it has no stable release. Pick Beta or Nightly.

Beta always includes stable releases. That is how the updater works, and it cannot be switched off.

Nightly carries Thaw built for the next macOS, which is a different app line and not a rougher build of the one you have.

## What is only in the beta

The [feature list](../README.md#features) on the home page is Thaw 3's. Thaw 2 has most of it, and some features are only in Thaw 3.

The [changelog](../CHANGELOG.md) lists what each release changed, and [Releases and updates](RELEASES.md) explains how updates reach your Mac.

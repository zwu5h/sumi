# Sumi

A simple manga reader for iPhone and iPad. Requires iOS/iPadOS 17 or later.

## Features

- Browse and search online manga through installable sources.
- Save titles to your library and resume where you left off.
- Read page by page or scroll vertically, with right-to-left support and zoom.
- Import PDFs and read them offline.
- Filter and sort your library and source catalogs.
- Choose a light, dark, or system theme.

Online chapters require an internet connection. No manga or sources are bundled.

## Install

Download **[Sumi.ipa from the latest release](https://github.com/zwu5h/sumi/releases/latest/download/Sumi.ipa)**.
The IPA is unsigned; the tools below sign and install it using your Apple Account.
Sumi runs on your iPhone or iPad; your computer is used for installation.

### Windows and macOS

1. Install [Sideloadly](https://sideloadly.io/) and follow its setup instructions, including any required Apple drivers on Windows.
2. Connect your iPhone or iPad by USB, unlock it, and trust the computer.
3. Open Sideloadly, select your device, and drag in `Sumi.ipa`.
4. Enter your Apple Account, click **Start**, and complete the sign-in prompts.
5. On your device, enable **Settings > Privacy & Security > Developer Mode** if requested. Trust your developer profile under **Settings > General > VPN & Device Management**, then open Sumi.

With a free Apple Account, refresh the app every seven days. See the [Sideloadly FAQ](https://sideloadly.io/faq.html) for automatic refresh and troubleshooting.

### Linux

1. Install [Sideloader](https://github.com/Dadoum/Sideloader#how-to-install) and its `libimobiledevice`, `libplist`, and OpenSSL dependencies as described in its guide.
2. Connect your iPhone or iPad by USB, unlock it, and trust the computer.
3. From the folder containing the downloaded IPA, run:

   ```sh
   sideloader install Sumi.ipa -i
   ```

4. Follow the Apple Account prompts. Enable Developer Mode and trust the developer profile on your device as described above.

Free Apple Account installations need refreshing every seven days; run the install command again with the same account.

## Add sources

Open **Settings > Sources & repositories**, add a repository, and install a source.
See [Sumi extensions](https://github.com/zwu5h/sumi-extensions) for available sources and [source setup](docs/sources.md) for details.

## Build from source

Set up [xtool](https://github.com/xtool-org/xtool) with Swift and an iOS SDK on macOS or Linux. On Windows, use WSL2 with Ubuntu.

```sh
git clone https://github.com/zwu5h/sumi.git
cd sumi
xtool dev build --configuration release --ipa
```

The unsigned IPA is created in `xtool/`.

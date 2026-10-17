# nMapMac

A native macOS (SwiftUI) front end for the [Nmap](https://nmap.org) network scanner, modelled on [Zenmap](https://nmap.org/zenmap/).

## Features

- **Easy targets, no subnet masks** — *Choose…* picks your own network in one click, or scans everything from one address to another. A hint under the Target box explains what you typed ("254 addresses (192.168.1.1 – 192.168.1.254)").
- **Saved commands** — start from a built-in scan type (Quick scan, Intense scan, Ping scan, …), edit the `nmap` command however you like, and *Save Current Command…* to reuse it later.
- **Hosts / Services sidebar** with OS icons and a host filter (`os:linux open:22,80 service:http …`).
- **Nmap Output** — live, syntax-highlighted output with progress.
- **Topology** — radial network map built from traceroute data (zoom, pan, click to select).
- **Host Details** — click a host in the sidebar to see everything about it on one page: a sortable port table, script output, status, addresses, every OS match and class, TCP/IP ID sequences, traceroute and editable comments. In Services mode it lists the hosts offering the selected service.
- **Scans** — every scan in the window; results from several scans are merged per host.
- **Compare Results** (ndiff-style) and **Search Scan Results** over every completed scan.
- Open/save Nmap XML (Zenmap-compatible, including comments and output) or plain `.nmap` text.
- **Run as Administrator** — runs nmap as root via the standard macOS password prompt, for SYN scans, OS detection, etc.

## Requirements

- macOS 14 (Sonoma) or later
- [Nmap](https://nmap.org) — nMapMac is a front end, so Nmap itself must be installed (see below)
- To build from source: Xcode or the Command Line Tools (Swift 5.10+)

## Install

### 1. Install Nmap

Check whether Nmap is already installed by opening **Terminal** and running:

```sh
nmap --version
```

If you see a version number, skip to step 2. If you see `command not found`, install it with [Homebrew](https://brew.sh):

1. If you don't have Homebrew, install it first (it asks for your password, and may ask to install Apple's Command Line Tools):

   ```sh
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

   When it finishes, follow the **Next steps** it prints to add `brew` to your PATH (on Apple silicon Macs this is usually the two `echo … >> ~/.zprofile` and `eval …` lines), then open a new Terminal window.

2. Install Nmap:

   ```sh
   brew install nmap
   ```

3. Confirm it works: `nmap --version`

nMapMac looks for Nmap in `/opt/homebrew/bin` (Apple silicon), `/usr/local/bin` (Intel) and your PATH. If you installed it somewhere else, set the path in **nMapMac → Settings…**. Nmap's official macOS installer from [nmap.org/download](https://nmap.org/download.html#macosx) works too.

### 2. Add nMapMac to Applications

**From the DMG**

1. Double-click `nMapMac.dmg` to open it.
2. Drag the **nMapMac** icon onto the **Applications** folder shortcut in the same window.
3. Eject the disk image (click ⏏ next to "nMapMac" in Finder's sidebar), then delete the DMG if you like.
4. Open nMapMac from **Launchpad**, Spotlight (⌘Space, type "nMapMac") or the Applications folder.

**From source**

Clone this repository (the green **Code** button on GitHub), then in its folder:

```sh
scripts/make-dmg.sh          # creates build/nMapMac.dmg — then follow the steps above
```

Or copy the app straight in: `scripts/build-app.sh && cp -R build/nMapMac.app /Applications/`

To update, quit nMapMac and replace the copy in Applications with the new one. To uninstall, drag it from Applications to the Trash (your saved commands and scan history are in `~/Library/Application Support/nMapMac/`).

### "nMapMac can't be opened" on first launch

The app isn't signed with an Apple Developer ID, so macOS blocks it the first time when it was downloaded from the internet. To allow it once:

- **Right-click** (or Control-click) nMapMac in Applications, choose **Open**, then **Open** again; or
- Try to open it, then go to **System Settings → Privacy & Security** and click **Open Anyway**.

Builds made on your own Mac aren't affected.

### Scans that need administrator access

SYN scans (`-sS`), OS detection (`-O`) and UDP scans (`-sU`) need root; without it, the Intense scans skip OS detection and traceroute. Click the **lock** in the toolbar (or **Scan → Run as Administrator**) and macOS will ask for your password when the scan starts.

## Build and run (development)

```sh
swift build                  # build
swift test                   # run the core tests
swift run nMapMac            # run without bundling
scripts/build-app.sh         # build build/nMapMac.app (release)
scripts/make-dmg.sh          # build build/nMapMac.dmg installer
open build/nMapMac.app
```

Open `Package.swift` in Xcode to work on it there.

## Layout

```
Sources/NMapMacCore/     Model: Nmap XML, command-line options, saved commands,
                         IP ranges, scan execution, search, diff, topology
Sources/NMapMac/         SwiftUI app: windows, tabs, target chooser, compare, search
Tests/NMapMacTests/      Swift Testing suite with XML fixtures
scripts/build-app.sh     Packages the .app bundle (icon, Info.plist, ad-hoc signing)
scripts/make-dmg.sh      Wraps the app in a drag-to-install DMG
scripts/make-icon.swift  Renders Resources/AppIcon.png
```

Your saved commands are stored in `~/Library/Application Support/nMapMac/saved_commands.usp` (Zenmap's profile format), and completed scans in `~/Library/Application Support/nMapMac/scans/`.

## License

The built-in scan types and OS icons come from Zenmap, part of the Nmap project, and are covered by the [Nmap Public Source License](https://nmap.org/npsl/).

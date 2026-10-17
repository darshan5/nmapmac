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

- macOS 14 or later
- Nmap (`brew install nmap`); the path can be set in Settings
- Swift 5.10+ toolchain (Xcode or Command Line Tools)

## Build and run

```sh
swift build                  # build
swift test                   # run the core tests
swift run nMapMac             # run without bundling
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

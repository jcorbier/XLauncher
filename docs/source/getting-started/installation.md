# Installation

## System Requirements

- **Operating System**: macOS 14.0 (Sonoma) or macOS 15.0+ (Sequoia)
- **Architecture**: Apple Silicon (M1/M2/M3/M4) or Intel (x86_64)
- **Simulator**: X-Plane 12

---

## Pre-Built Binaries

1. Download the latest `XLauncher.dmg` from the [GitHub Releases](https://github.com/jcorbier/x-plane-launcher/releases) page.
2. Open `XLauncher.dmg`.
3. Drag **XLauncher.app** into your `/Applications` folder.
4. Eject the disk image.

```{note}
On first launch, macOS Gatekeeper might ask to confirm opening the app. Click **Open**, or allow it in **System Settings > Privacy & Security**.
```

---

## Building from Source

Building from source requires Xcode or the Swift command-line tools:

```bash
xcode-select --install
```

1. Clone the repository:
   ```bash
   git clone https://github.com/jcorbier/x-plane-launcher.git
   cd x-plane-launcher
   ```

2. Run the packaging script:
   ```bash
   ./package.sh
   ```

3. The script compiles the executable in release mode, builds the macOS app bundle structure, copies resources, and signs the bundle.

4. Open `XLauncher.app` or move it to your `/Applications` folder:
   ```bash
   open XLauncher.app
   ```

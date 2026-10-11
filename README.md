<div align="center">

# Fusion Free Space Wiper

**Clean. Check. Recover.** — an honest, self‑contained disk toolkit for older Intel &
Fusion‑Drive Macs.

[![Latest release](https://img.shields.io/github/v/release/ssharaf-dot/fusion-free-space-wiper?label=latest&color=00684A)](https://github.com/ssharaf-dot/fusion-free-space-wiper/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/ssharaf-dot/fusion-free-space-wiper/total?color=00684A)](https://github.com/ssharaf-dot/fusion-free-space-wiper/releases)
[![License: GPL v2+](https://img.shields.io/badge/license-GPLv2+-blue)](LICENSE)
![Platform](https://img.shields.io/badge/macOS-10.15%2B%20·%20Intel-333)

### ⬇︎ [**Download the latest version**](https://github.com/ssharaf-dot/fusion-free-space-wiper/releases/latest)

*Open the `.dmg` → drag the app to **Applications** → right‑click ▸ **Open** on first launch.*

</div>

---

Three tools in one window, in the order you'd actually use them:

1. **Clean** — overwrite the **empty (free) space** on a disk so previously‑deleted files are
   harder to recover, without touching your current files.
2. **Check** — run the bundled **PhotoRec** (read‑only) to see **what's still recoverable**.
3. **Recover** — analyse and recover **partitions** with the bundled **TestDisk**.

Everything is **self‑contained in one DMG** — nothing to install. Built for a Late‑2012
iMac on macOS Catalina, where Apple removed the easy built‑in way to overwrite free space.

> An [Ethos](https://github.com/ssharaf-dot) tool. No network. No telemetry. Local only.
> Bundles **PhotoRec & TestDisk** © CGSecurity (GPL).

---

## ⚠️ Disclaimer — please read

This performs an **accessible free‑space overwrite**. It is **not** a certified, forensic,
or "secure" erase, and it **cannot guarantee** that previously‑deleted data is unrecoverable
— especially on SSD/Fusion storage (wear‑leveling, over‑provisioning, TRIM, and APFS
snapshots put some data out of reach). Provided **as‑is, with no warranty** (see
[LICENSE](LICENSE)). Keep a backup. For a guarantee, use FileVault from the start, or erase
the whole disk. **"No files recovered" is not proof that nothing is recoverable.**

## Which Macs benefit?

| Your drive | Does this help? |
|---|---|
| **Spinning hard drive (HDD)** | ✅ Works well |
| **Fusion Drive (HDD + SSD)** | 🟡 Partly — the HDD portion benefits (the honest sweet spot) |
| **Pure SSD / flash** | ⚠️ Limited value — prefer FileVault or a full erase |

Full machine cheat‑sheet: **[COMPATIBILITY.md](COMPATIBILITY.md)**.

## Install

1. Download from **[Releases](https://github.com/ssharaf-dot/fusion-free-space-wiper/releases/latest)**.
2. Open the `.dmg`, drag **Fusion Free Space Wiper** to **Applications**.
3. First launch: ad‑hoc signed (not notarized), so **right‑click ▸ Open ▸ Open** once.

**Requirements:** macOS 10.15 Catalina or newer, Intel Mac (runs on Apple Silicon under
Rosetta, but those are all‑SSD — see the compatibility note).

## Start with a test

The app opens on **Clean**. Run the **100 MB safety test** first — it exercises the *real*
engine (same writing, flushing, progress, cleanup) but stops after a strict limit, so you can
confirm everything works before a full wipe.

## Build from source

Needs the Xcode Command Line Tools (no full Xcode required).

```bash
./build.sh        # builds build/…app and dist/FusionFreeSpaceWiper-<ver>.dmg (x86_64, 10.15)
./run_tests.sh    # 40 automated tests, incl. a real-engine run on a disposable disk image
```

You can also open the folder in Xcode (it reads `Package.swift`).

## Credits & acknowledgements

Bundles **TestDisk & PhotoRec** by **Christophe Grenier / CGSecurity** — the long‑standing
free, open‑source standard for data recovery.

- Project home: https://www.cgsecurity.org/wiki/TestDisk
- Source & downloads: https://www.cgsecurity.org/wiki/TestDisk_Download
- GitHub mirror: https://github.com/cgsecurity/testdisk

Redistributed **unmodified** under the GPL v2+. See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## License

**GNU GPL v2 or later** ([LICENSE](LICENSE)) © 2026 Sunaz Sharaf. Because this app bundles
PhotoRec/TestDisk (GPL), the combined work is distributed under the GPL. No warranty.

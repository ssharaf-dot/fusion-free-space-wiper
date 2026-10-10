# Fusion Free Space Wiper

A small, honest macOS app that gives you a **full 360° view of your data** on older Macs,
in three tabs:

1. **Fusion — Wipe:** overwrite the **empty (free) space** on a disk so previously‑deleted
   files are harder to recover, without touching your current files.
2. **PhotoRec — Audit:** run the bundled PhotoRec recovery engine (read‑only) to see **what
   is still recoverable** from a disk.
3. **TestDisk — Recover:** analyse and recover **partitions** with the bundled TestDisk.

Built for older **Intel Macs with a hard drive or Fusion Drive** (it was made for a
Late‑2012 iMac on macOS Catalina), where Apple removed the easy built‑in way to do this.
Everything is **self‑contained in one DMG** — nothing to install.

> **An [Ethos](https://github.com/ssharaf-dot) tool. No network. No telemetry. Local only.**
> Bundles **PhotoRec & TestDisk** © CGSecurity (GPL).

---

## ⚠️ Disclaimer — please read

This tool performs an **accessible free‑space overwrite**. It is **not** a certified,
forensic, or "secure" erase, and it **cannot guarantee** that previously‑deleted data is
unrecoverable — especially on SSD or Fusion storage (wear‑leveling, over‑provisioning,
TRIM, and APFS snapshots all put some data out of a normal app's reach).

It is provided **as‑is, with no warranty of any kind** (see [LICENSE](LICENSE)). You are
responsible for having a backup. If you need a guarantee, use full‑disk encryption
(FileVault) from the start, or erase the entire disk before selling your Mac.

**"No files recovered" is not proof that nothing is recoverable.**

---

## What it does

- Fills free space with overwrite data in **app‑owned temporary files**, then deletes them.
- Keeps a **safety reserve** (default max(20 GiB, 10% of capacity), never below 10 GiB) and
  **never fills the disk** — it re‑checks space before every write.
- Only ever writes or deletes **its own** temporary files. It never formats, repartitions,
  resets a Fusion Drive, erases a volume, deletes your files, or removes snapshots.

## Which Macs benefit?

| Your drive | Does this help? |
|---|---|
| **Spinning hard drive (HDD)** | ✅ Works well |
| **Fusion Drive (HDD + SSD)** | 🟡 Partly — the HDD portion benefits (the honest sweet spot) |
| **Pure SSD / flash** | ⚠️ Limited value — prefer FileVault or a full erase |

Full details and a machine cheat‑sheet: **[COMPATIBILITY.md](COMPATIBILITY.md)**.

## Download & install

1. Go to **[Releases](../../releases/latest)** and download the `.dmg`.
2. Open it, drag **Fusion Free Space Wiper** to **Applications**.
3. First launch: the app is ad‑hoc signed (not notarized), so **right‑click the app ▸ Open ▸ Open**
   to get past Gatekeeper once. After that it opens normally.

**Requirements:** macOS 10.15 Catalina or newer, Intel Mac (runs on Apple Silicon under
Rosetta, but those are all‑SSD — see the compatibility note).

## Start with a test

The app opens in **Test Mode**. Run the **100 MB test** first — it exercises the *real*
engine (same writing, flushing, progress, cleanup) but stops after a strict limit, so you
can confirm everything works on your machine before a full wipe.

## Safety by design

- Verifies the target volume's UUID before and during a run; aborts on mismatch.
- Temporary files are created `O_CREAT|O_TRUNC|O_NOFOLLOW`, mode `0600`, inside a marked,
  `0700` session directory with a random id. Cleanup refuses to follow symlinks and is
  verified afterward.
- Handles short writes, `EINTR`, `ENOSPC` and I/O errors with checked 64‑bit arithmetic.
- Keeps the Mac awake during a run via a temporary power assertion (no system settings are
  changed); warns laptop users that closing the lid will interrupt the run.
- Detects and **warns about APFS snapshots** — but never deletes them.

## Build from source

Needs the Xcode Command Line Tools (no full Xcode required).

```bash
./build.sh        # builds build/…app and dist/FusionFreeSpaceWiper-<ver>.dmg (x86_64, 10.15)
./run_tests.sh    # 40 automated tests, incl. a real-engine run on a disposable disk image
```

You can also open the folder in Xcode (it reads `Package.swift`).

## Honest limitations

- Cannot guarantee deleted data is unrecoverable, especially on SSD/Fusion.
- Does not remove APFS snapshots.
- `fsync`/`F_FULLFSYNC` flush buffers; they don't force specific physical SSD cells to be rewritten.
- The result is reported as **completed with limitations**, never a certificate.

## Credits & acknowledgements

This app bundles two tools from the **TestDisk & PhotoRec** project by **Christophe Grenier
/ CGSecurity** — the long-standing, free, open-source standard for data recovery. Huge
thanks to them; this suite would not exist without their work.

- Project home: https://www.cgsecurity.org/wiki/TestDisk
- Source & downloads: https://www.cgsecurity.org/wiki/TestDisk_Download
- GitHub mirror: https://github.com/cgsecurity/testdisk

PhotoRec and TestDisk are redistributed **unmodified** under the GNU GPL v2+. See
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for versions, the pinned checksum, and how
to obtain their corresponding source.

## License

**GNU GPL v2 or later** ([LICENSE](LICENSE)) © 2026 Sunaz Sharaf. Because this app bundles
PhotoRec/TestDisk (GPL), the combined work is distributed under the GPL — see
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). No warranty. Overwriting free space causes
SSD wear and heat and takes time proportional to free space and pass count.

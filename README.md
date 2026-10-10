# Fusion Free Space Wiper

A native macOS (AppKit) utility that overwrites **accessible filesystem free space**
on a selected, writable, mounted volume by creating app‑owned temporary files and
then deleting them. It is built for a **Late‑2012 27″ Intel iMac running macOS
Catalina 10.15.7 with a Fusion Drive**, and it includes a prominent, real‑engine
**Test Mode**.

It **preserves** macOS, installed apps, accounts, settings and all existing files.
It **never** formats, repartitions, resets the Fusion Drive, erases a disk, deletes
user files, removes snapshots, or changes encryption settings.

---

## ⚠️ Honest threat model — read this first

Free‑space overwriting on a Fusion Drive (HDD + SSD) **cannot** guarantee that
previously‑deleted data is unrecoverable. This is a physical/OS reality, not a
limitation of effort:

- SSD **wear‑leveling, over‑provisioning, TRIM and remapped/spare blocks** keep
  copies host writes cannot reach.
- **APFS copy‑on‑write, compression, clones and zero‑block handling** break the
  one‑to‑one mapping between logical writes and physical blocks.
- **APFS snapshots** (including Time Machine local snapshots) can retain extents of
  deleted files. This app detects them (read‑only) and **warns**, but never deletes
  them.
- `fsync` / `F_FULLFSYNC` flush buffers; they do **not** force particular physical
  SSD cells to be rewritten.

This tool therefore reports **"accessible free‑space overwrite completed"** with
explicit caveats. It does **not** claim "permanent", "forensic", "certified", or
"SSD secure erase", and it never issues a certificate of irrecoverability.
**No recovered files ≠ proof of irrecoverability.** Extra passes (3‑pass, and the
deliberately‑omitted 35‑pass Gutmann) add wear and time with **no** guarantee on
SSD/Fusion.

---

## What you get

- `build.sh` — builds `FusionFreeSpaceWiper.app` (x86_64, deployment target 10.15)
  and packages `dist/FusionFreeSpaceWiper-<version>.dmg`, using **only the Command
  Line Tools** (no full Xcode required).
- `Package.swift` — open the folder in Xcode (File ▸ Open) to browse, build and run.
- `run_tests.sh` — compiles and runs the automated test suite, including integration
  tests against a **disposable sparse disk image** (never your startup disk).
- `Sources/…` — all Swift source (engine + AppKit UI).
- `Tests/main.swift` — the test runner.

---

## Build the app + DMG (recommended)

```bash
./build.sh
```

Outputs:

- `build/FusionFreeSpaceWiper.app`
- `dist/FusionFreeSpaceWiper-1.0.0.dmg`

The binary is a real **x86_64** Mach‑O with **`minos 10.15`**, linking AppKit and the
OS‑provided Swift 5 ABI‑stable runtime (present in macOS 10.14.4+), so **no Swift
runtime needs bundling on Catalina**.

### Open in Xcode instead

Open the `FusionFreeSpaceWiper` folder in Xcode (it reads `Package.swift`). You can
Build and Run there. For the distributable Catalina `.app`/`.dmg`, prefer `build.sh`.

---

## Install on the Catalina Intel iMac

1. Copy `FusionFreeSpaceWiper-1.0.0.dmg` to the iMac and open it.
2. Drag **Fusion Free Space Wiper** to **Applications**.
3. First launch: the app is **ad‑hoc signed** (not notarized), so **right‑click the
   app ▸ Open ▸ Open** to bypass Gatekeeper once. (Or System Preferences ▸ Security &
   Privacy ▸ *Open Anyway*.)

No network access, no telemetry, no background agents, no root required for normal
operation.

---

## Recommended first run

1. Launch. The app opens in **TEST MODE** (default).
2. On the **System** tab, confirm the target volume (defaults to the startup volume `/`).
3. Back in **Test Mode**, choose **100 MB — Quick Test** and **Start Test**.
4. Watch the live dashboard (progress, MB written, current speed, elapsed, ETA,
   stage). When it reports **✓ 100 MB TEST PASSED**, you can optionally run the
   **1 GB** then **10 GB** tests.
5. Only after you're satisfied, switch to **FULL FREE‑SPACE WIPE**, complete the
   Preflight acknowledgment, review the reserve, and confirm by typing the volume name.

---

## Test Mode (built‑in)

Test Mode runs the **real** production write engine — same file creation, write
loop, successful‑byte counting, flushing (`F_FULLFSYNC`), progress callbacks,
throughput calculation, cancellation, cleanup and session management — with **one**
difference: a **strict maximum write target** (100 MB / 1 GB / 10 GB, exact decimal
bytes).

The limit is enforced at the **lowest level of the write loop**, not by the UI or a
timer. Before every write:

```
remainingAllowed = testLimitBytes − actualSuccessfullyWrittenBytes
nextWriteSize     = min(normalChunkSize, remainingAllowed)
```

When `actualSuccessfullyWrittenBytes >= testLimitBytes` the engine stops writing
immediately and proceeds to flush → verify → cleanup → verify cleanup. The automated
tests assert the cap is **never exceeded** and is **reached exactly**.

The **same engine** performs a full wipe; production simply passes
`maxWriteBytes = nil` (governed by the safety reserve instead). There is **one**
wiping implementation — `FreeSpaceWiper` — used by both modes.

A **Full‑Wipe safety gate** recommends running at least the 100 MB test first, and
warns more strongly if the last 100 MB test failed. Pre‑wipe test results are shown
on the main screen (informational; a passing test is **not** an absolute guarantee).

---

## Safety design (engine)

- **Volume identity** is re‑verified (UUID + mount path) before and during a run;
  a mismatch aborts with zero bytes written.
- **Safety reserve**: default `max(20 GiB, 10% of capacity)`, hard floor **10 GiB**,
  never below. `statfs` is re‑read **before every chunk**; the engine stops before
  crossing the reserve and never fills to 0 bytes.
- **App‑owned session directory** with an unpredictable name and `0700` permissions,
  plus a `MARKER.json` carrying a random session id, pid and volume UUID.
- All temp files are created with `O_CREAT | O_TRUNC | O_NOFOLLOW`, mode `0600` — the
  engine never follows a symlink at the final component and never appends to an
  existing file.
- **Short writes, `EINTR`, `ENOSPC`, I/O errors** are all handled explicitly with
  checked 64‑bit arithmetic.
- **Cleanup** removes only regular files inside the marked session directory; it
  refuses to follow symlinks and leaves anything suspicious as a reported leftover.
  Cleanup is then **verified** (session directory gone, zero leftovers).
- **Interruption recovery**: on launch the app finds only *its own* stale sessions
  (valid marker + dead pid) and offers safe removal. It never blindly removes
  similarly‑named folders.
- **Honesty on zeros**: it measures physical space consumed via `statfs` deltas and
  flags suspected **zero‑block elision/compression** in the report.

## Recovery testing (honest, privacy‑preserving)

- **Layer A — logical verification (supported):** allocates a bounded sample of new
  files, writes tagged patterns, `fsync`s, reads them back and confirms them. This
  verifies only the **newly allocated** files, not that old physical blocks were
  overwritten.
- **Layer B — deleted‑file recovery (usually unavailable):** the app bundles **no**
  carving engine and downloads nothing. On a live, mounted APFS/Fusion volume it
  reports **"not available on this configuration"** rather than fabricate a scan.
- **Layer C — read‑only diagnostics:** snapshot presence, free‑vs‑available
  discrepancy, encryption state (best effort). Never deletes snapshots.

## Reporting

JSON + human‑readable HTML, with app/OS/volume identifiers (no serials by default),
requested method, actual passes, bytes written, physical space consumed, errors,
reserve breaches, cleanup success + verification, leftover files, snapshot state,
recovery findings and explicit limitations. Status is one of **completed (with
limitations)**, **incomplete**, or **failed** — never a certificate.

---

## Run the tests

```bash
./run_tests.sh            # unit tests + integration on a disposable sparse image
./run_tests.sh --no-image # unit tests only
```

The integration tests create, mount, exercise and destroy a **disposable ~14 GiB
sparse APFS image** (sparse: only the few hundred MB actually written consume host
disk). They assert, against the **real engine**: the strict cap is never exceeded and
is reached exactly, flush completes, cleanup succeeds **and is verified**, a canary
file outside the session directory is byte‑identical afterward, volume‑identity
mismatch aborts, the reserve guard blocks when space is insufficient, and mid‑run
cancellation still cleans up.

> The test harness lowers the reserve floor **only for the disposable image** (the
> shipping app never does this; the production floor stays 10 GiB).

---

## Compatibility notes (verified vs. unverified)

- **Verified here:** compiles and links as **x86_64 / `minos 10.15`**; links only
  against frameworks/dylibs present on Catalina; all **40** automated checks pass;
  the app **launches** (under Rosetta on the dev machine) with no AutoLayout or
  runtime errors.
- **Not verifiable here:** this development machine is Apple Silicon running a newer
  macOS, so the app could not be *executed on real Catalina 10.15.7* from here.
  Please run the **100 MB Test Mode** first on the target iMac — that is exactly what
  Test Mode is for. The deployment target, availability‑gated APIs (nothing newer
  than 10.15 is used), and Catalina‑only framework linkage are all set correctly for
  that target.

## Build environment used

- Apple Swift 6.2.x toolchain (Command Line Tools), building in **Swift 5 language
  mode** with `-target x86_64-apple-macosx10.15`.
- No dependencies. No Apple Silicon / Rosetta / USB / Linux / network requirements
  for the app itself.

## License

See `LICENSE` (MIT). Local utility; no warranty. Overwriting free space causes SSD
wear and heat and takes time proportional to free space and pass count.

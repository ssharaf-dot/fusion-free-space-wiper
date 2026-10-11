# Fusion Free Space Wiper 1.2 — App Flow

A screen-by-screen map of the current interface, for redesign. The app is a **native
macOS AppKit app** (single resizable window, macOS 10.15+, Intel). Everything lives in
**one window** with a **three-tool suite** switched by a segmented control at the top.

```
┌───────────────────────────────────────────────────────────────┐
│  ● ● ●                Fusion Free Space Wiper                   │  macOS title bar
├───────────────────────────────────────────────────────────────┤
│         [ ① Fusion — Wipe | ② PhotoRec — Audit | ③ TestDisk ]  │  SUITE TAB BAR (always)
├───────────────────────────────────────────────────────────────┤
│  [Home]            • Size • Confirm • Run • Result   [Advanced] │  GUIDED BAR (Fusion tab only)
├───────────────────────────────────────────────────────────────┤
│                                                                 │
│                        screen content                          │  swappable area (scrolls)
│                                                                 │
└───────────────────────────────────────────────────────────────┘
```

- **Suite tab bar** is always visible; it switches the whole content area between the three tools.
- **Guided bar** (Home button · step indicator · Advanced) appears **only on the Fusion tab**; it collapses on the other two tabs.
- Menu bar (not shown): , File, Edit, View, Go, Window, Help (standard macOS).

---

## Tool ① — Fusion (Wipe)  ·  the guided flow

Opens here on launch.

### Home (`goHome`)
- **360° banner** card: "① Fusion wipes free space clean · ② PhotoRec audits what's recoverable · ③ TestDisk recovers partitions."
- Heading **"What would you like to do?"** + one-line explanation.
- **Status card:** selected Disk · Free space · Safety-test badge (Not tested / ✓ Passed / ✗ Failed) · "Change disk".
- **Two choice cards:**
  - 🧪 **Run a Safety Test** (green, RECOMMENDED) → Test flow.
  - 🧹 **Wipe Free Space** (red; shows "🔒 Safety test recommended first" until a test passes) → Wipe flow.

### Test flow — steps: **Size → Confirm → Run → Result**
1. **Size** — radio: 100 MB (recommended) / 1 GB / 10 GB, each with a one-line description.
2. **Confirm** — summary card ("will write ~X of temporary data, then auto-delete; your files not modified"). Buttons: Back · **Run <size> Test** (green).
3. **Run** — the **shared dashboard** (see below).
4. **Result** — ✓ PASSED / ⚠ DID NOT COMPLETE / ■ Stopped, with a details card (target vs actual bytes, flush, cleanup verified, avg speed, elapsed). Next-step buttons chain: 100 MB→1 GB→10 GB→"Proceed to Wipe"; plus "Back to Home".

### Wipe flow — steps: **Options → Checklist → Confirm → Run → Result**
- Safety gate before entering: if the 100 MB test hasn't passed, a dialog recommends testing first (Go to Test / Proceed Anyway / Cancel).
1. **Options** — radio: single-pass zeros (default) / single-pass pseudorandom / three-pass (advanced) + **Safety reserve** field (GiB, floor 10, default max(20 GiB,10%)).
2. **Checklist** — 4 acknowledgement checkboxes (backup, power, no disk-heavy task, understand it's not certified).
3. **Confirm** — must **type the disk name**; shows APFS-snapshot warning if detected.
4. **Run** — the shared dashboard.
5. **Result** — "FREE-SPACE OVERWRITE COMPLETE (with limitations)" + details; buttons: Back to Home · View Diagnostics · Save Report.

### Shared **Running dashboard** (the hero screen to improve)
Top→bottom:
1. Big title ("🧪 100 MB TEST" green / "🧹 WIPING FREE SPACE" red).
2. Stage line with spinner ("Writing test data…", "Flushing data…", "Verifying…", "Cleaning up…").
3. **HERO ROW:** giant **% (56pt)** on the left, giant **time-remaining (40pt)** on the right.
4. One-line caption (e.g. "151 GB of ~395 GB overwritten · 287 GB free remaining").
5. **Block map** — grid of tiles = free space; filled = written, hatched amber = reserve kept free. (Honest "scale of work" visual — NOT physical sectors.)
6. Legend.
7. **Three stat cards:** Written · Current speed · Elapsed.
8. Controls: Pause · Resume · Stop (Test shows only "Stop & Clean Up").

### Advanced (Fusion tab → Advanced)
List of cards: Save report · Diagnostics & recovery check · Clean up leftover files · Open Energy settings · About & limitations.

---

## Tool ② — PhotoRec (Audit)

One screen + a result:
- Heading + honest explainer + limits note (SSD-hidden cells; admin password; long scans).
- **Source**: selected disk, or "Audit a disk image…" (file picker).
- **Destination**: "Choose where to save recovered files…" (must NOT be the source disk — enforced).
- **Start Audit** (green). Device scans prompt for the **admin password** (native), run the bundled PhotoRec read-only, recover into the destination.
- **Result**: big count ("N recoverable files found" red, or "No recoverable files found" green) + per-type table + destination/size + honest caveat.

## Tool ③ — TestDisk (Recover)

One screen:
- Heading + explainer.
- **Disk** selector.
- **Analyze partitions (read-only)** → runs `testdisk /list` (admin), shows the partition table in a monospace output area.
- **Open advanced recovery in Terminal…** → launches interactive TestDisk (`sudo testdisk <device>`) for hands-on undelete.

---

## Modals / windows
- **About** (standard macOS About panel): icon, name, version, credits (Sunaz Sharaf; PhotoRec/TestDisk © CGSecurity GPL; no network), © 2026 · GPL v2+.
- **Preferences** (⌘,): default test size, default reserve, "always confirm by typing", finish sound.
- **Help** window (no network): what it does, which Macs benefit, safety, limitations.
- **Laptop/battery warning** before any run (native dialog + "Open Energy Settings…").

---

## Design system (current — replace freely)
- **Colors:** blue `#0A72E8` (primary), green `#1A8A3F` (safe/test), red `#C8362F` (destructive/wipe), amber `#B9842A` (caution/reserve).
- **Font:** system (SF Pro). **Radius:** 10–16px. **Icons:** emoji (SF Symbols are macOS 11+, unavailable on the Catalina target).
- **Components:** card (rounded, subtle shadow), tinted icon chip, filled button (primary/green/red) + ghost button, radio option row, step indicator (dots), block map, stat card.

## What I'd focus a redesign on
1. The **running dashboard** — make it feel like a control-room readout (it's the screen users stare at longest).
2. **Tab clarity** — the three tools could read even more obviously as "Clean → Check → Recover".
3. **Home** — tighten the hierarchy so the one recommended action is unmistakable.
4. Keep the **honesty notes** visible — they're part of the product's integrity, not decoration.
```
When you've redesigned, hand me the new mockups/specs and I'll rebuild the AppKit UI to match.
```

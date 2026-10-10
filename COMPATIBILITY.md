# Which Macs is Fusion Free Space Wiper for?

A plain-language guide to **when this tool genuinely helps, when it helps a little, and
when you should use something else instead.** We'd rather tell you the truth than sell
you a false sense of security.

## What the app does (in one sentence)

It fills the **empty (free) space** on a disk with overwrite data and then deletes it, so
that files you previously deleted are **harder to recover** — without touching any of your
current files, apps, or macOS.

It does **not** erase your disk, and it is **not** a certified or "forensic" erase.

---

## The one thing that decides how well it works: your drive type

| Your drive | Does free-space overwriting help? | Why |
|---|---|---|
| **Spinning hard drive (HDD)** | ✅ **Yes — works well** | Magnetic platters write where you tell them. Overwriting free space genuinely reduces what can be recovered. |
| **Fusion Drive (HDD + small SSD)** | 🟡 **Partly — the honest sweet spot** | The large **HDD portion** benefits like a normal hard drive. The small **SSD portion** can't be fully reached (see below). A sensible best-effort precaution, not a guarantee. |
| **Pure SSD / flash storage** | ⚠️ **Limited value** | SSDs use wear-leveling, over-provisioning and TRIM, so the drive decides where writes land and keeps spare cells you can't address. Overwriting free space can't reach all old data. |

**This tool is at its best on older HDD and Fusion Macs** — which is exactly the kind of
machine (like a Late-2012 iMac with a Fusion Drive) where Apple removed the easy built-in
way to do this and left a gap.

---

## Machine cheat-sheet

**Good fit (HDD or Fusion):**
- iMac (2009–2020) with a hard drive or **Fusion Drive**
- Mac mini (2010–2018) with a hard drive or Fusion Drive
- MacBook / MacBook Pro (2008–2012) with a spinning hard drive
- External **USB / Thunderbolt hard drives**

**Limited value (pure SSD / flash):**
- Any **Apple Silicon** Mac (M1, M2, M3, M4 …) — flash storage, and never had Fusion
- MacBook Air / Pro (≈2016 and newer) — soldered SSD
- iMac / Mac mini / Mac Studio with all-SSD storage
- External **SSD / NVMe** drives

> Not sure what you have? In the app, the **System** info shows your drive and whether a
> Fusion Drive was detected. Or check  → About This Mac → More Info → Storage.

---

## If you have an SSD, do this instead

Overwriting free space isn't the right tool for flash storage. Better options:

1. **Turn on FileVault** (System Settings → Privacy & Security → FileVault). With full-disk
   encryption on from the start, data is unreadable without your password — effectively
   "erased" the moment the key is gone.
2. **Before selling or giving away a Mac**, use Apple's own full erase (Erase All Content &
   Settings, or erase the whole disk from Recovery). That's the reliable way to clear an SSD.

---

## Requirements

- **macOS 10.15 Catalina or newer.** Built and tested for Catalina on Intel.
- **Intel Mac** for best results. It will run on Apple Silicon Macs under Rosetta 2, but
  those are all-SSD, so see the "limited value" note above.
- Enough free space above the safety reserve (the app keeps at least 10 GiB free and never
  fills your disk).

---

## How to use it (the safe way)

1. **Back up first.** Always.
2. Plug into **power** and leave the Mac awake.
3. Open the app → it starts in **Test Mode**. Run the **100 MB test** to confirm everything
   works on your machine. (Optionally 1 GB, then 10 GB.)
4. Switch to **Full Free-Space Wipe**, review the safety reserve, and confirm by typing your
   disk's name.
5. Let it run. On a large or slow drive this can take **hours** — that's normal.
6. When it finishes you'll get a report. It will say **"completed with limitations,"** never
   "certified erase," because that's the honest result.

---

## The honest limitations (always)

- Can't guarantee previously-deleted data is unrecoverable — especially on SSD/Fusion.
- Doesn't remove **APFS snapshots** (it detects and warns about them; it never deletes them).
- "No files recovered" is **not** proof that nothing is recoverable.
- For true peace of mind on an SSD: encrypt (FileVault), or erase the whole disk.

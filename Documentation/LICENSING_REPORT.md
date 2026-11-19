# DualDS licensing report

Status: **draft for the project owner's decision**, written 19 Nov 2026 before any distribution.
This is an engineering analysis, not legal advice. Have a lawyer review it before a paid or public release.

## 1. What we are combining

| Component | Licence | How it is used |
|---|---|---|
| melonDS (core, pinned commit `361ffa95…`) | GPL-3.0-or-later | Compiled from source and statically linked into the app |
| FreeBIOS (inside melonDS) | BSD-style (© Gilead Kutnick) | Compiled in; replaces Nintendo's BIOS |
| teakra (inside melonDS) | MIT | Compiled in (DSi DSP; unused in DS mode but linked) |
| blip-buf (inside melonDS) | LGPL-2.1 | Compiled in (audio resampling) |
| FatFs, xxHash, SHA-1, tiny-AES-c (inside melonDS) | BSD-style / BSD-2 / public domain / Unlicense | Compiled in |
| DualDS frontend, bridge, session layer | GPL-3.0-or-later (our choice, see §2) | Our code |

The exact inventory is regenerated from the submodule by `Scripts/generate-notices.sh` and checked by
`Scripts/verify-licenses.sh`.

## 2. Consequence: the whole app must be GPL-3.0

DualDS links melonDS into a single executable, so the distributed app is a work based on melonDS.
GPL-3.0 §5(c) requires the whole work to be licensed under the GPL when it is conveyed.
**A proprietary or closed-source Swift frontend is not an option** while melonDS is the core,
unless the melonDS copyright holders grant a separate licence. DualDS is therefore licensed
GPL-3.0-or-later from its first commit, and every source file says so.

GPL is compatible with charging money for the app. It is not compatible with stopping anyone else
from building, modifying and redistributing it, including for free.

## 3. Obligations for every build we distribute (TestFlight counts)

1. **Corresponding source** (§6): publish the complete source for that exact build: this repo at a
   tag, the melonDS submodule commit, `project.yml`, scripts and build instructions. Link it from
   About → Source Code (`AppConfiguration.sourceCodeURL`) and from the App Store description.
2. **Licence texts and notices**: GPL-3.0 text, melonDS licence and third-party notices are bundled
   and viewable in About → Licenses (already implemented, covered by unit and UI tests).
3. **No further restrictions** (§10): no added terms that limit copying, modification or redistribution.
4. **Installation information** (§6, "User Products"): iPhones are consumer devices. BUILDING.md must
   explain how anyone can build and install a modified DualDS on their own device with Xcode and a
   free Apple ID. Whether that fully satisfies §6 for an App Store binary is unsettled (see §4).
5. **Modified files**: if we ever patch melonDS, the patches must be clearly marked and dated. Today
   melonDS is used **unmodified**.

## 4. The App Store question

* **Known risk.** The FSF's long-standing position is that the App Store's terms add restrictions
  the GPL forbids. In 2011 Apple removed VLC from the App Store after a VLC copyright holder
  objected. The risk comes from the **melonDS copyright holders**, not from Apple's review.
* **Precedent in practice.** Delta (AGPL-3.0) ships melonDS on the US App Store and has done since
  April 2024. eDuo (GPL-3.0, unmodified melonDS) distributes through TestFlight. Both publish
  their full source. As far as public records show, melonDS's authors have not objected. That
  lowers the risk; it does not remove it.
* **Recommended mitigation.** Before the first public release, email the melonDS team (Arisotura)
  describing DualDS, its GPL-3.0 source repository and the App Store plan, and ask for written
  acknowledgement. Keep the reply with this report.

## 5. Content and trademark constraints

* No ROMs, BIOS, firmware, DSi NAND, keys or Nintendo artwork are bundled. FreeBIOS and melonDS's
  generated firmware are used instead. Enforced by `.gitignore` and `verify-licenses.sh`.
* The only `.nds` file in the repo is DualDS's own test ROM, assembled from source in
  `Tests/Fixtures/testrom/`. It contains no Nintendo code, logo or data.
* **Name risk: "DualDS".** "DS" is a Nintendo trademark. App Review guideline 5.2 (intellectual
  property) and Nintendo trademark complaints are a real risk for an app name built around it.
  Delta and eDuo both avoid "DS" in their store names. **Decision needed** (see §6).
* Use "Nintendo DS" only descriptively ("plays Nintendo DS games you own"), with a non-affiliation
  notice (already in About).

## 6. Decisions for the project owner

1. ✅ Published as GPL-3.0 at https://github.com/bi-creator/DualDS (2026-11-19).
2. Contact the melonDS team before public release? (Recommended.)
3. Keep the name "DualDS" or choose a store name without "DS"? The code name can stay either way.
4. Business model: free, or paid with source published? (Both are GPL-compatible.)

---
name: macos-ocr
type: procedure
description: >
  Extract text from images or scanned PDFs on macOS. Auto-invoke whenever OCR is
  needed — reading a scanned document, pulling a number off a card/receipt/label
  photo, a PDF whose text layer is missing or garbled, or any "read the text out of
  this image" task. Covers where to look for the scan first (card and ID scans are
  often attachments on a password-manager item, not files on disk), choosing between a vision-language model and an OCR engine
  (embossed, handwritten, glare-obscured or low-contrast text needs a VLM — OCR
  engines return zero on it), Apple Vision via Swift as the OCR engine of choice over
  tesseract, diagnosing WHY an attempt failed (tonal depth, resolution, rotation), and
  extracting sensitive values without exposing them.
tags: [ocr, macos, vision, swift, tesseract, pdf, scanning, vlm]
freshness:
  last_refreshed_at: 2026-10-15
  auto_refresh_cadence: quarterly
  additional_refresh_triggers:
    macos_version_change:
      last_verified_version: "15.7.7"
---

# macOS OCR

## Find the scan first

Before searching the filesystem, check whether the scan is an **attachment on the
record it belongs to**, for example the card's item in a password manager. Card,
passport and licence scans are routinely filed there rather than in a folder tree. A
filesystem `find` for `*card*` will not surface these; they are not on disk. With
1Password, for instance:

```bash
op item get "<title>" --vault "<vault>" --format json | python3 -c \
  "import json,sys; [print(f['name'], f['size']) for f in json.load(sys.stdin).get('files',[])]"
op read "op://<vault>/<title>/<attachment-name>" --out-file scan.pdf
```

## Pick the tool by what the text physically IS

This is the decision that matters. Get it wrong and you will burn an hour on an
engine that structurally cannot succeed.

| Text characteristic | Use | Why |
|---|---|---|
| **Embossed / raised / debossed** (credit cards, ID plates, seals) | **Vision-language model** | The glyph is the *same colour* as the background — defined only by highlight/shadow relief. Stroke-detectors have nothing to detect. |
| **Handwriting** | **Vision-language model** | OCR engines garble it. |
| Glare, skew, poor lighting, phone photos | **Vision-language model** | Layout priors and context recover what stroke detection can't. |
| Flat printed text, decent contrast | **Apple Vision** (`visionocr.swift`, this dir) | Fast, scriptable, no model call. |
| Clean high-DPI bitonal scan of printed text | `tesseract` | Fine here; nowhere else. |
| Born-digital PDF | `pdftotext` | Real text layer, no OCR needed. |
| **Scanned** PDF's embedded text layer | **Do not trust it** | On one batch it yielded nothing for two files and a *false Luhn-valid card number* for a third. |

**Measured, 2026-09-08, six card scans, same files through every path:**

| Target | tesseract | Apple Vision | Vision-language model |
|---|---|---|---|
| Chase **embossed** card front | **zero characters** | flat text only; number = noise | read correctly |
| Chase embossed card back (mirrored relief) | almost nothing | flat text ok; number = nonsense | read correctly |
| Home Depot **flat-etched** card | number, but **silently dropped 2 of 5 groups** | all 5 groups correct | read correctly |

Note tesseract's failure mode on the flat card: plausible-looking *partial* output
rather than an error. That is worse than returning nothing.

## Tonal depth beats resolution

Check this before touching an engine. Resolution is usually not your problem.

```bash
pdfimages -list scan.pdf          # width/height/color/bpc/enc/x-ppi
magick page.png -format '%[fx:mean] ' info:   # or measure the histogram
```

**The controlled comparison.** ScanSnap wrote the two pages of the SAME card in
different modes in a single pass, and the *failing* page is the higher-resolution one:

| Page | Source (`pdfimages -list`) | Midtones | Result |
|---|---|---|---|
| front (embossed number) | **600 ppi, 1 bpc, ccitt** — bitonal | 1.1% | **unreadable by every path** |
| back (relief pushes through) | **300 ppi, 8 bpc, jpeg** — grayscale | 75.3% | **read correctly** |

Resolution varied *against* the hypothesis — the readable page has half the dpi.
Bit depth is the cause, so treat this as **Verified**, not merely Observed.

**Embossed lettering exists only as midtone shading.** A bitonal capture does not
degrade it, it *deletes* it: 98.3% of pixels pinned to the extremes leaves the digits
as disconnected specular arcs.

Counter-example that sharpens the rule: a *different* Chase card scanned 600 ppi
bitonal on **both** pages read fine — because that card is a newer style with the
number **flat-printed** on the back. Bitonal is not the problem; bitonal + relief is.

**Confirmed a second time, 2026-09-15**, on another business card of the same issuer: both
pages 600 ppi / 1 bpc / ccitt, and the back still read correctly on all four passes.
The front yielded no recoverable digits at all — 3.9 KB of ink versus the back's
17.5 KB — but on this card style it does not need to, because the number is not
printed there. So: **check where the number physically is before blaming the scan
settings.** A useless front is expected on newer Chase stock, not a scan defect.

**Corollary — the scanner setting depends on the subject:**
- Flat printed documents → 600 dpi **bitonal** is excellent, and beats 300 dpi colour.
- **Embossed cards → never bitonal.** Grayscale or colour, 600 dpi.

Rendering above the source's native resolution adds nothing. Check `x-ppi` before
choosing `pdftoppm -r`.

## Embossed cards: read the BACK

Counter-intuitive and reliable. Embossing pushes through to the reverse face, where it
appears as shaded relief on flat light card stock instead of metallic foil on black.

```bash
magick back.png -flop -resize 400% -sharpen 0x1.5 /tmp/readable.png
```

Flip horizontally (the relief is mirrored), upscale 3–5×. On the test batch the back
was the single most reliable source, and the front — in isolation — only supported a
moderate-confidence read. Confirm front against back and require agreement.

**Keep the mirrored render as a negative control.** On a *flat-printed* back, `-flop`
returns confident-looking garbage (`DET8 2SS8 AZIE DASA`, `AZIV`, `IE\20`). That is
worth having: if the upright render and the mirrored one BOTH yield plausible
16-digit strings, one is a hallucination and neither can be trusted. A mirrored read
that collapses into nonsense is positive evidence the upright read is real glyph
recognition rather than a language-model guess.

## Rotation

Vision-language models tolerate 90° rotation with no accuracy loss (only a slower
first pass). OCR engines degrade measurably. If you must OCR, deskew first;
`tesseract --psm 0` reports detected orientation.

## Delegating to a VLM without exposing the value

When the image holds a card number, SSN or similar, spawn a subagent to look at it so
the value never enters the calling context. Constrain the output hard:

> Your final report MUST NOT contain a full card number or CVV in any form — not
> spaced, hyphenated, split across lines, or spelled out. Report the LAST FOUR DIGITS
> ONLY. If you are about to write more than four consecutive digits, stop.

Ask it for: front/back, issuer/product, cardholder, last-4, expiry, network,
credit-vs-debit (look for the printed word DEBIT), orientation, and legibility. That is
everything needed to file and identify, with nothing sensitive returned.

## Extraction discipline (when scripting, not eyeballing)

**Work per-line, never per-page.** Pooling a page's digits creates false adjacency
across unrelated fields and manufactures matches — a random 16-digit window passes
Luhn about 1 time in 10.

**A line is not a field.** OCR lines concatenate several printed fields (number +
expiry + member-since). The trailing digits of an N-digit line are NOT the value's
last-4 — they are whatever field came last. Only slice the end when line length equals
the expected field length exactly. *(Made this exact error 2026-09-08: read a 23-digit
line, took its final 4 as the card last-4, matched them to a real account, and
misidentified a credit card as a debit card.)*

**Validate structurally:** expected length; a checksum where one exists (Luhn); a
prefix/issuer check; and for tesseract, agreement across ≥2 `--psm` modes (6, 4, 11).
Trailing groups often read correctly while leading digits garble — a correct last-4 is
**not** evidence the whole value is right.

## Apple Vision helper

Needs the Xcode command line tools (`xcode-select --install`) for `swiftc`, and poppler
(`brew install poppler`) for `pdftoppm`.

```bash
swiftc -O -o /tmp/visionocr "${CLAUDE_PLUGIN_ROOT}/skills/macos-ocr/visionocr.swift"
pdftoppm -r 600 -f 2 -l 2 -png scan.pdf /tmp/page     # Vision needs an IMAGE
/tmp/visionocr /tmp/page-2.png
```

`usesLanguageCorrection = false` is mandatory for numbers, codes and IDs — otherwise
Vision "corrects" digit strings into words.

## Privacy

**OCR reads handwritten security codes.** Apple Vision cleanly extracted a
handwritten CVV from a card's signature panel, in plaintext. Assume any card-back scan
piped through OCR puts the security code into your output, shell history and logs.
Filter it deliberately; do not assume handwriting won't OCR.

Keep sensitive text in shell variables and report only derived facts — length,
checksum result, last-4, or a `shasum -a 256` comparison against a known value.

**Clean up derived images.** Rasterized pages sit in the clear on disk. Delete crops
and renders when done; file the originals somewhere appropriate.


## Other tools present

`ocrmypdf` (adds a text layer in place), `pdftotext` / `pdfimages` / `pdftoppm`
(poppler), `magick` / `convert` (grayscale, resize, sharpen, threshold, `-flop`),
`shortcuts` (another route to Vision without compiling).

Preprocessing with `magick` gave no measurable gain over feeding Vision the native
render — try Vision directly before building a pipeline. The exception is embossed
relief, where `-flop` + upscale genuinely helps.

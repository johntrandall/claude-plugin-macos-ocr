# macos-ocr: a Claude Code plugin

One skill that teaches Claude how to get text out of images and scanned PDFs on a Mac, and
when not to bother with an OCR engine at all.

What it covers:

- **Which tool for which text.** Embossed, handwritten, glare-obscured or low-contrast text
  needs a vision-language model (that is, Claude looking at the image); OCR engines return
  nothing or, worse, plausible partial output. Flat printed text goes to Apple Vision. Clean
  bitonal scans of print can go to `tesseract`. Born-digital PDFs just need `pdftotext`.
- **Apple Vision from the shell.** `skills/macos-ocr/visionocr.swift` is a 24-line helper that
  prints recognised text one line per observation, with language correction off so digit
  strings stay digits. Build with `swiftc`, run on an image.
- **Why a scan fails.** Bit depth, not resolution: an embossed card scanned as 1-bit bitonal
  loses its digits entirely, while a 300 dpi grayscale scan of the same card reads fine
  (measured). Read embossed cards from the back, mirrored.
- **Extraction without exposure.** Per-line not per-page, structural validation (length,
  Luhn, issuer prefix), delegating to a subagent that reports only the last four digits, and
  cleaning up rasterised pages afterwards.

## Install

```
/plugin marketplace add johntrandall/claude-plugins
/plugin install macos-ocr@johntrandall-plugins
```

## Requirements

macOS. Xcode command line tools for `swiftc` (`xcode-select --install`); poppler
(`brew install poppler`) for `pdftoppm`, `pdfimages`, `pdftotext`; ImageMagick
(`brew install imagemagick`) for the flip-and-upscale preprocessing; `tesseract` and
`ocrmypdf` only if you want those paths.

## Licence

MIT, see [LICENSE](LICENSE).

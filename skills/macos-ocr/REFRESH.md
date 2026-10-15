# Refresh Procedure for macos-ocr

## On cadence
1. Confirm the helper still builds: `swiftc -O -o /tmp/visionocr skills/macos-ocr/visionocr.swift` (from the plugin root).
   A build failure usually means a Vision API change — check `VNRecognizeTextRequest`
   in current Apple docs and update the source.
2. Re-verify the tool inventory is still installed:
   `for t in swiftc tesseract ocrmypdf pdftotext pdfimages pdftoppm magick; do command -v $t; done`
3. Confirm `VNRecognizeTextRequest` has not gained a materially better recognition
   level or a replacement API worth adopting.

## On macos_version_change
1. Rebuild and run the helper against a known sample image; confirm output is
   unchanged in shape (one line per observation).
2. Check whether the OS ships a newer Vision revision
   (`VNRecognizeTextRequestRevision*`) that should be pinned explicitly.
3. Update `last_verified_version` in SKILL.md frontmatter.

## Verification checklist
- [ ] visionocr.swift compiles clean
- [ ] Listed CLI tools still resolve on PATH
- [ ] Resolution-diagnosis guidance still matches `pdfimages -list` output format
- [ ] Frontmatter updated (last_refreshed_at, macos last_verified_version)

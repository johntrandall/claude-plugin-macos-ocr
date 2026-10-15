// SPDX-License-Identifier: MIT
// Copyright (c) 2026 John Randall
// Apple Vision OCR — prints recognized text, one observation per line.
// Build:  swiftc -O -o visionocr visionocr.swift
// Run:    ./visionocr /path/to/image.png
// Vision works on IMAGES, not PDFs — rasterize first (see SKILL.md).
import Vision
import AppKit

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("usage: visionocr <image>\n".data(using: .utf8)!); exit(64)
}
let path = CommandLine.arguments[1]
guard let img = NSImage(contentsOfFile: path),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("could not load image: \(path)\n".data(using: .utf8)!); exit(1)
}
let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate        // .fast is markedly worse on small text
req.usesLanguageCorrection = false      // MUST be false for codes/IDs/numbers
req.recognitionLanguages = ["en-US"]
do { try VNImageRequestHandler(cgImage: cg, options: [:]).perform([req]) }
catch { FileHandle.standardError.write("vision failed: \(error)\n".data(using: .utf8)!); exit(2) }
for obs in (req.results ?? []) {
    if let best = obs.topCandidates(1).first { print(best.string) }
}

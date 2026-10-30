// Proposes card framings (Paul 2026-10-30: the Christmas portraits came with too much sky above the hats). For each source image it
// finds the subject with Apple Vision (objectness saliency for the whole animal, hat included; attention saliency and face rectangles
// for where to centre) and proposes:
//   hero   - the 2:3 crop for the hero and thumb: the whole subject at ~85% of the height (zoom at most 1.5x), a little headroom
//   square - the square crop for the Christmas board: head, hat and shoulders (at least 62% of the source width)
// as {cx, cy, zoom} (crop centre as a fraction of the source; zoom = source width / crop width). Existing entries in
// tools/card-frames.json are kept, so Paul's tuned frames (holo-lab/framing.html) are never overwritten; --redo-auto recomputes
// the entries that are still automatic proposals (marked "auto").
// Run from web/: swift tools/propose-frames.swift
import Foundation
import Vision
import AppKit

let sources = ["seasons/christmas/cards"].flatMap { dir -> [String] in
    let url = URL(fileURLWithPath: "../source/art/\(dir)")
    let files = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
    return files.filter { $0.hasSuffix(".jpg") || $0.hasSuffix(".png") }.sorted().map { "\(dir)/\($0)" }
} + ["poly/poly-christmas.png"]

let framesURL = URL(fileURLWithPath: "tools/card-frames.json")
var frames = (try? JSONSerialization.jsonObject(with: Data(contentsOf: framesURL))) as? [String: Any] ?? [:]
frames["_doc"] = "Card framings (holo-lab/framing.html, tools/propose-frames.swift). Key: path under source/art. hero: 2:3 crop for the hero and thumb; square: the Christmas board's square crop. cx, cy: crop centre (0-1 of the source); zoom: source width / crop width (1 = full width)."

func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }
func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }

for path in sources {
    if let f = frames[path] as? [String: Any], !(CommandLine.arguments.contains("--redo-auto") && f["auto"] != nil) { print("keep    \(path)"); continue }
    guard let image = NSImage(contentsOfFile: "../source/art/\(path)"),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("skip    \(path) (can't read)"); continue }
    let W = Double(cg.width), H = Double(cg.height)
    let saliency = VNGenerateAttentionBasedSaliencyImageRequest(), objects = VNGenerateObjectnessBasedSaliencyImageRequest(), faces = VNDetectFaceRectanglesRequest()
    try? VNImageRequestHandler(cgImage: cg).perform([saliency, objects, faces])
    // Vision boxes are normalised with the origin at the bottom left; turn them into top-left pixel boxes.
    func box(_ r: CGRect) -> (x0: Double, y0: Double, x1: Double, y1: Double) {
        (Double(r.minX) * W, (1 - Double(r.maxY)) * H, Double(r.maxX) * W, (1 - Double(r.minY)) * H)
    }
    func union(_ r: [VNRectangleObservation]?) -> (x0: Double, y0: Double, x1: Double, y1: Double)? {
        let b = (r ?? []).map { box($0.boundingBox) }
        guard var u = b.first else { return nil }
        for x in b.dropFirst() { u = (min(u.x0, x.x0), min(u.y0, x.y0), max(u.x1, x.x1), max(u.y1, x.y1)) }
        return u
    }
    let focus = union(saliency.results?.first?.salientObjects) ?? (0, 0, W, H)
    // The whole subject: objectness, widened to take in the attention box too (it sometimes misses a hat tip).
    var s = union(objects.results?.first?.salientObjects) ?? focus
    s = (min(s.x0, focus.x0), min(s.y0, focus.y0), max(s.x1, focus.x1), max(s.y1, focus.y1))
    let face = (faces.results ?? []).max { $0.boundingBox.width < $1.boundingBox.width }.map { box($0.boundingBox) }
    let subjectH = s.y1 - s.y0, subjectCx = face.map { ($0.x0 + $0.x1) / 2 } ?? (focus.x0 + focus.x1) / 2

    // Hero 2:3: the subject fills ~80% of the crop height (but never zoom past 1.8x), the subject's top ~6% below the crop's top.
    let heroH = clamp(subjectH / 0.85, H / 1.5, H), heroW = heroH * W / H
    let heroTop = clamp(s.y0 - heroH * 0.04, 0, H - heroH), heroLeft = clamp(subjectCx - heroW / 2, 0, W - heroW)
    // Square: head and shoulders. With a face, a square ~2.6 face-widths wide with the eyes on the upper third; without one, the
    // top ~60% of the subject.
    var side: Double, sqTop: Double
    // Head, hat and shoulders: from just above the subject's top down past the face (the attention box), at least 62% of the width.
    side = clamp(max((focus.y1 - s.y0) * 1.25, (focus.x1 - focus.x0) * 1.2), W * 0.62, W)
    sqTop = s.y0 - side * 0.04
    sqTop = clamp(sqTop, 0, H - side)
    let sqLeft = clamp(subjectCx - side / 2, 0, W - side)
    frames[path] = [
        "hero": ["cx": round3((heroLeft + heroW / 2) / W), "cy": round3((heroTop + heroH / 2) / H), "zoom": round3(W / heroW)],
        "square": ["cx": round3((sqLeft + side / 2) / W), "cy": round3((sqTop + side / 2) / H), "zoom": round3(W / side)],
        "auto": face != nil ? "saliency+face" : "saliency",
    ]
    print("propose \(path)  subject \(Int(s.x0)),\(Int(s.y0))-\(Int(s.x1)),\(Int(s.y1))\(face != nil ? "  face" : "")")
}
let data = try JSONSerialization.data(withJSONObject: frames, options: [.prettyPrinted, .sortedKeys])
try data.write(to: framesURL)
print("wrote tools/card-frames.json")

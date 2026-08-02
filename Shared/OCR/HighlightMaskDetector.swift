import Foundation
#if canImport(UIKit)
import UIKit
import CoreGraphics
#endif

/// OpenCV-style highlighter mask: HSV inRange → morphology close → blob filter.
///
/// Implemented with CoreGraphics pixel walk (no opencv2 binary) so Share/Action
/// extensions stay under size limits. Same pipeline can later call native OpenCV
/// on Android / a heavier iOS target without changing `ImageOCRService` callers.
enum HighlightMaskDetector {
    struct Mask: Sendable {
        let width: Int
        let height: Int
        /// Row-major, 1 = highlight, 0 = background.
        let bytes: [UInt8]

        func isOn(x: Int, y: Int) -> Bool {
            guard x >= 0, y >= 0, x < width, y < height else { return false }
            return bytes[y * width + x] != 0
        }

        /// `normalizedBox` uses Vision coordinates (origin bottom-left, unit square).
        /// Note: glyph centers often land on black ink, so callers should NOT require
        /// the geometric center to be on the highlight mask.
        func highlightCoverage(ofNormalizedBox box: CGRect) -> Double {
            let samples = samplePoints(in: box)
            guard !samples.isEmpty else { return 0 }
            let hits = samples.reduce(0) { partial, point in
                partial + (isOn(x: point.x, y: point.y) ? 1 : 0)
            }
            return Double(hits) / Double(samples.count)
        }

        private func samplePoints(in box: CGRect) -> [(x: Int, y: Int)] {
            // Prefer mid-band of the glyph box (highlight sits behind text strokes).
            let xs = [0.30, 0.50, 0.70].map { box.minX + box.width * $0 }
            let ys = [0.40, 0.50, 0.60].map { box.minY + box.height * $0 }
            var points: [(Int, Int)] = []
            for nx in xs {
                for ny in ys {
                    let x = Int((nx * CGFloat(width)).rounded())
                    // Vision Y is bottom-up; mask is top-down.
                    let y = Int(((1 - ny) * CGFloat(height)).rounded())
                    points.append((
                        min(max(x, 0), width - 1),
                        min(max(y, 0), height - 1)
                    ))
                }
            }
            return points
        }
    }

    #if canImport(UIKit)
    static func makeMask(from cgImage: CGImage, maxDimension: Int = 720) -> Mask? {
        guard let scaled = downscaled(cgImage, maxDimension: maxDimension) else { return nil }
        let width = scaled.width
        let height = scaled.height
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(scaled, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        var raw = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let r = Double(ptr[i]) / 255
                let g = Double(ptr[i + 1]) / 255
                let b = Double(ptr[i + 2]) / 255
                if looksLikeHighlighter(r: r, g: g, b: b) {
                    raw[y * width + x] = 1
                }
            }
        }

        // Small radius: close pinholes without flooding into neighbor glyphs.
        let closed = morphClose(raw, width: width, height: height, radius: 1)
        let filtered = filterSmallBlobs(closed, width: width, height: height, minArea: 80)
        return Mask(width: width, height: height, bytes: filtered)
    }

    private static func downscaled(_ image: CGImage, maxDimension: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maxDimension else { return image }
        let scale = CGFloat(maxDimension) / CGFloat(longest)
        let size = CGSize(
            width: max(1, (CGFloat(image.width) * scale).rounded()),
            height: max(1, (CGFloat(image.height) * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let ui = renderer.image { _ in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
        }
        return ui.cgImage
    }

    /// OpenCV `cvtColor(BGR2HSV)` + multi-range `inRange` for common marker inks.
    /// Slightly looser than the zero-hit pass so real marker pixels fill glyph boxes (~0.44+).
    private static func looksLikeHighlighter(r: Double, g: Double, b: Double) -> Bool {
        let hsv = rgbToHSV(r: r, g: g, b: b)
        guard hsv.s >= 0.18, hsv.v >= 0.35, hsv.v <= 0.97 else { return false }

        let h = hsv.h
        let yellowChroma = ((r + g) * 0.5) - b
        let yellow = h >= 36 && h <= 74 && hsv.s >= 0.22 && yellowChroma >= 0.06
        // Skip teal/cyan — App accent + tab chrome false-positive as highlighter on screenshots.
        let green = h >= 72 && h <= 150 && hsv.s >= 0.22
        let pink = (h >= 300 || h <= 20) && hsv.s >= 0.22
        let orange = h >= 15 && h <= 40 && hsv.s >= 0.26 && yellowChroma >= 0.06
        return yellow || green || pink || orange
    }

    private static func rgbToHSV(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC
        let v = maxC
        let s = maxC == 0 ? 0 : delta / maxC
        guard delta > 1e-6 else { return (0, s, v) }

        let hPrime: Double
        if maxC == r {
            hPrime = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxC == g {
            hPrime = (b - r) / delta + 2
        } else {
            hPrime = (r - g) / delta + 4
        }
        var h = hPrime * 60
        if h < 0 { h += 360 }
        return (h, s, v)
    }

    /// Dilate then erode (morphological close), OpenCV `morphologyEx(MORPH_CLOSE)`.
    private static func morphClose(_ src: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        let dilated = dilate(src, width: width, height: height, radius: radius)
        return erode(dilated, width: width, height: height, radius: radius)
    }

    private static func dilate(_ src: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        var dst = [UInt8](repeating: 0, count: src.count)
        for y in 0..<height {
            for x in 0..<width {
                var on: UInt8 = 0
                let y0 = max(0, y - radius)
                let y1 = min(height - 1, y + radius)
                let x0 = max(0, x - radius)
                let x1 = min(width - 1, x + radius)
                outer: for yy in y0...y1 {
                    for xx in x0...x1 where src[yy * width + xx] != 0 {
                        on = 1
                        break outer
                    }
                }
                dst[y * width + x] = on
            }
        }
        return dst
    }

    private static func erode(_ src: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        var dst = [UInt8](repeating: 0, count: src.count)
        for y in 0..<height {
            for x in 0..<width {
                var on: UInt8 = 1
                let y0 = max(0, y - radius)
                let y1 = min(height - 1, y + radius)
                let x0 = max(0, x - radius)
                let x1 = min(width - 1, x + radius)
                outer: for yy in y0...y1 {
                    for xx in x0...x1 where src[yy * width + xx] == 0 {
                        on = 0
                        break outer
                    }
                }
                dst[y * width + x] = on
            }
        }
        return dst
    }

    private static func filterSmallBlobs(_ src: [UInt8], width: Int, height: Int, minArea: Int) -> [UInt8] {
        var labels = [Int](repeating: 0, count: src.count)
        var areas: [Int] = [0]
        var nextLabel = 1
        var queue = [Int]()

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                guard src[idx] != 0, labels[idx] == 0 else { continue }
                let label = nextLabel
                nextLabel += 1
                var area = 0
                queue.removeAll(keepingCapacity: true)
                queue.append(idx)
                labels[idx] = label

                var head = 0
                while head < queue.count {
                    let cur = queue[head]
                    head += 1
                    area += 1
                    let cy = cur / width
                    let cx = cur % width
                    for dy in -1...1 {
                        for dx in -1...1 {
                            if dx == 0, dy == 0 { continue }
                            let nx = cx + dx
                            let ny = cy + dy
                            guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                            let nidx = ny * width + nx
                            guard src[nidx] != 0, labels[nidx] == 0 else { continue }
                            labels[nidx] = label
                            queue.append(nidx)
                        }
                    }
                }
                areas.append(area)
            }
        }

        var dst = [UInt8](repeating: 0, count: src.count)
        for i in 0..<labels.count {
            let label = labels[i]
            guard label > 0, areas[label] >= minArea else { continue }
            dst[i] = 1
        }
        return dst
    }
    #endif
}

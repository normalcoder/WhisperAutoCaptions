import Foundation
import MetalKit

struct Vertex {
    var pos: simd_float2
    var uv: simd_float2
}

final class GlyphAtlas {
    private let cell: CGSize
    func lineHeight(scale: CGFloat) -> CGFloat { cell.height * scale * 1.2 }

    func wrap(text: String, maxWidth: CGFloat, scale: CGFloat) -> [String] {
        let spaceW = (charMap[" "] ?? .zero).width * scale
        var lines: [String] = []
        var cur = ""
        var curW: CGFloat = 0

        // honour \n, split first
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            for word in rawLine.split(separator: " ") {
                let wWidth = word.reduce(CGFloat(0)) { $0 + (charMap[$1]!.width * scale) }

                if curW > 0, curW + spaceW + wWidth > maxWidth {
                    lines.append(cur)
                    cur  = String(word)
                    curW = wWidth
                } else {
                    if !cur.isEmpty { cur += " "; curW += spaceW }
                    cur += word
                    curW += wWidth
                }
            }
            lines.append(cur)
            cur = ""
            curW = 0
        }
        if !cur.isEmpty { lines.append(cur) }
        return lines
    }

    let texture: MTLTexture
    private let charMap: [Character: CGRect]

    /// Builds atals ASCII-chars 32…126 in grid 16×6
    init(fontName: String,
         size: CGFloat,
         device: MTLDevice,
         cols: Int = 16,
         rows: Int = 6,
         cell: CGSize = .init(width: 64, height: 64)) throws
    {
        self.cell = cell
        // 1. Create Metal-texture BGRA8
        let texWidth  = cols * Int(cell.width)
        let texHeight = rows * Int(cell.height)

        let texDesc   = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width:  texWidth,
            height: texHeight,
            mipmapped: false)
        texDesc.usage = [.shaderRead]

        guard let mtlTex = device.makeTexture(descriptor: texDesc) else {
            throw NSError(domain: "GlyphAtlas.Texture", code: -1)
        }

        // 2. Draw all chars in UIImage (scale = 1)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: texWidth, height: texHeight), format: fmt)

        var map: [Character: CGRect] = [:]

        let img = renderer.image { ctx in
            UIColor.clear.setFill()
            ctx.fill(.init(x: 0, y: 0,
                           width: texWidth, height: texHeight))

            let font = UIFont(name: fontName, size: size)
                        ?? .systemFont(ofSize: size, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white
            ]

            for ascii in 32...126 {
                let index = ascii - 32
                let row   = index / cols
                let col   = index % cols

                // 1. Char
                let ch = Character(UnicodeScalar(ascii)!)
                let str = String(ch)

                // 2. Replace size of glyph
                let sz  = str.size(withAttributes: attrs)

                // 3. Base cell in atlas (64 × 64 or differend how it's set in `cell`)
                let cellRect = CGRect(x: col * Int(cell.width),
                                      y: row * Int(cell.height),
                                      width: Int(cell.width),
                                      height: Int(cell.height))

                // 4. Align glyph by center of cell
                let drawRect = CGRect(
                    x: cellRect.midX - sz.width  / 2,
                    y: cellRect.midY - sz.height / 2,
                    width:  sz.width,
                    height: sz.height)

                // 5. Draw
                str.draw(in: drawRect, withAttributes: attrs)

                // 6. Save precise border of glyph but not the whole cell
                //    it fixes space between letters
                map[ch] = CGRect(
                    x: Int(drawRect.minX),
                    y: Int(drawRect.minY),
                    width: Int(drawRect.width),
                    height: Int(drawRect.height))
            }
        }

        // 3. Conver UIImage to RGBA-memory with correct bytesPerRow
        guard let cgImg = img.cgImage else {
            throw NSError(domain: "GlyphAtlas.CGImage", code: -2)
        }

        let width = cgImg.width
        let height = cgImg.height
        let bytesPerPixel = 4
        let rowBytes = width * bytesPerPixel
        var rawData = [UInt8](repeating: 0, count: height * rowBytes)

        guard let ctx = CGContext(data: &rawData,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: rowBytes,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                             | CGBitmapInfo.byteOrder32Big.rawValue)
        else { throw NSError(domain: "GlyphAtlas.CGBitmap", code: -3) }

        ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 4. Copy to Metal-texture
        mtlTex.replace(region: MTLRegionMake2D(0, 0, width, height),
                       mipmapLevel: 0,
                       withBytes: &rawData,
                       bytesPerRow: rowBytes)

        self.texture  = mtlTex
        self.charMap  = map
    }

    /// Create mesh for any string
    /// - `scale` — scale related to initial cell(1 = 64 × 64).
    /// alignment: .left (default), .center, .right
    func meshes(
        for text: String,
        in viewSize: CGSize,
        y baseline: CGFloat,
        scale: CGFloat = 0.5,
        alignment: NSTextAlignment = .left
    ) -> [Vertex] {

        // 1. Calc real width of string
        let textWidth = text.reduce(CGFloat.zero) { sum, ch in
            guard let r = charMap[ch] else { return sum }
            return sum + r.width * scale
        }

        // 2. Initial position of pen
        var penX: CGFloat = 0
        switch alignment {
        case .center:
            penX = (viewSize.width - textWidth) / 2
        case .right:
            penX = viewSize.width - textWidth
        default: // .left
            penX = 0
        }

        // 3. Create verticies
        var verts: [Vertex] = []
        for ch in text {
            guard let r = charMap[ch] else { continue }

            let gw = r.width  * scale
            let gh = r.height * scale

            let x0 = penX
            let y0 = baseline - gh
            let x1 = penX + gw
            let y1 = baseline

            let u0 = Float(r.minX / CGFloat(texture.width))
            let v0 = Float(r.minY / CGFloat(texture.height))
            let u1 = Float(r.maxX / CGFloat(texture.width))
            let v1 = Float(r.maxY / CGFloat(texture.height))

            verts.append(contentsOf: [
                Vertex(pos: .init(Float(x0), Float(y0)), uv: .init(u0, v0)),
                Vertex(pos: .init(Float(x1), Float(y0)), uv: .init(u1, v0)),
                Vertex(pos: .init(Float(x0), Float(y1)), uv: .init(u0, v1)),
                Vertex(pos: .init(Float(x0), Float(y1)), uv: .init(u0, v1)),
                Vertex(pos: .init(Float(x1), Float(y0)), uv: .init(u1, v0)),
                Vertex(pos: .init(Float(x1), Float(y1)), uv: .init(u1, v1))
            ])

            penX += gw
        }
        return verts
    }
}

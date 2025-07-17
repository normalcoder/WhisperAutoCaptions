import Foundation
import AVFoundation
import MetalKit

final class SubtitleCompositor: NSObject, AVVideoCompositing {
    static let share = SubtitleCompositor()
    private override init() {}
    private static var device: MTLDevice!
    private static let ciContext = CIContext(mtlDevice: device)
    private static var preferredTransform: CGAffineTransform = .identity

    private static var queue: MTLCommandQueue!
    private static var pipeline: MTLRenderPipelineState!
    private static var atlas: GlyphAtlas!
    private static var style: SubtitleStyle!
    private static var segs: [CaptionSegment] = []
    static func configure(
        device: MTLDevice,
        queue: MTLCommandQueue,
        library: MTLLibrary,
        atlas: GlyphAtlas,
        style: SubtitleStyle,
        segments: [CaptionSegment],
        transform: CGAffineTransform
    ) {
        Self.device=device
        Self.queue=queue
        Self.atlas=atlas
        Self.style=style
        Self.segs=segments
        Self.preferredTransform = transform
        
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "subtitle_vertex")
        desc.fragmentFunction = library.makeFunction(name: "subtitle_fragment")
        

        let vDesc = MTLVertexDescriptor()
        vDesc.attributes[0].format       = .float2
        vDesc.attributes[0].offset       = 0
        vDesc.attributes[0].bufferIndex  = 0

        vDesc.attributes[1].format       = .float2
        vDesc.attributes[1].offset       = MemoryLayout<SIMD2<Float>>.size
        vDesc.attributes[1].bufferIndex  = 0

        vDesc.layouts[0].stride          = MemoryLayout<Vertex>.stride
        desc.vertexDescriptor            = vDesc

        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].rgbBlendOperation = .add
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        
        pipeline = try! device.makeRenderPipelineState(descriptor: desc)
        
        let sampDesc = MTLSamplerDescriptor()
        sampDesc.minFilter = .linear
        sampDesc.magFilter = .linear
        Self.sampler = device.makeSamplerState(descriptor: sampDesc)

    }
    private static var sampler: MTLSamplerState!
    // Pixel formats
    var sourcePixelBufferAttributes: [String : Any]? = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    var requiredPixelBufferAttributesForRenderContext: [String : Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
    func startRequest(_ req: AVAsynchronousVideoCompositionRequest) {
        autoreleasepool {
            guard let dst = req.renderContext.newPixelBuffer(),
                  let src = req.sourceFrame(byTrackID: req.sourceTrackIDs[0].int32Value)
            else {
                req.finish(with: NSError(domain: "buf", code: -1))
                return
            }
            
            let ciSrc   = CIImage(cvPixelBuffer: src)
                .transformed(by: Self.preferredTransform)   // та самая матрица

            Self.ciContext.render(ciSrc, to: dst)
            
            // draw subs
            let t = req.compositionTime
            if let seg = Self.segs.first(where: { t >= $0.start && t < $0.end }) {
                draw(text: seg.text, on: dst)
            }
            CVPixelBufferUnlockBaseAddress(dst, [])
            req.finish(withComposedVideoFrame: dst)
        }
    }
    
    private func draw(text: String, on buf: CVPixelBuffer) {
        let frameW = CVPixelBufferGetWidth(buf)
        let frameH = CVPixelBufferGetHeight(buf)

        let scale: CGFloat = CGFloat(frameH + 960) / 2880 // 0.25
        let sideMargin: CGFloat = 16
        let maxLineWidth = CGFloat(frameW) - sideMargin * 2

        let lines = Self.atlas.wrap(text: text,
                                    maxWidth: maxLineWidth,
                                    scale: scale)

        let lineHeight = Self.atlas.lineHeight(scale: scale)

        // Collect verticies bottom up
        var verts: [Vertex] = []
        var baseline = CGFloat(frameH) - Self.style.fontSize * 0.8 - (CGFloat(frameH) * 5.0/76.0 - 500.0/19.0)
        

        for line in lines.reversed() {
            verts += Self.atlas.meshes(
                for: line,
                in: CGSize(width: frameW, height: frameH),
                y: baseline,
                scale: scale,
                alignment: .center
            )
            baseline -= lineHeight
        }

        // Setup render pass
        let rpDesc = MTLRenderPassDescriptor()
        let tex = CVMetalTextureCacheHelper.texture(from: buf, device: Self.device)
        rpDesc.colorAttachments[0].texture     = tex
        rpDesc.colorAttachments[0].loadAction  = .load
        rpDesc.colorAttachments[0].storeAction = .store

        let cmd  = Self.queue.makeCommandBuffer()!
        let enc  = cmd.makeRenderCommandEncoder(descriptor: rpDesc)!
        enc.setRenderPipelineState(Self.pipeline)

        // small uniforms (viewport + colour)
        var viewport = simd_float2(Float(frameW), Float(frameH))
        enc.setVertexBytes(&viewport,
                           length: MemoryLayout<simd_float2>.size,
                           index: 1)

        enc.setFragmentTexture(Self.atlas.texture, index: 0)
        var color = Self.style.textColor.vec
        enc.setFragmentBytes(&color,
                             length: MemoryLayout<simd_float4>.size,
                             index: 0)
        enc.setFragmentSamplerState(Self.sampler, index: 0)

        // draw by chunks =< 4096 bytes
        let vertsPerGlyph = 6 // 2 triangles
        let maxVertsPerChunk = 252 // 4096 / 16, multiple of 6
        var start = 0

        while start < verts.count {
            let remain       = verts.count - start
            let glyphsInChunk = min(maxVertsPerChunk, remain) / vertsPerGlyph
            let vCount       = glyphsInChunk * vertsPerGlyph

            verts.withUnsafeBytes { raw in
                let ptr = raw.baseAddress!.advanced(by: start * MemoryLayout<Vertex>.stride)
                enc.setVertexBytes(ptr,
                                   length: vCount * MemoryLayout<Vertex>.stride,
                                   index: 0)
            }
            enc.drawPrimitives(type: .triangle,
                               vertexStart: 0,
                               vertexCount: vCount)
            start += vCount
        }

        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
    }
}

// MARK: PixelBuffer, Metal texture helper

fileprivate enum CVMetalTextureCacheHelper {
    static var cache: CVMetalTextureCache = {
        var c: CVMetalTextureCache!
        CVMetalTextureCacheCreate(nil, nil, MTLCreateSystemDefaultDevice()!, nil, &c)
        return c
    }()
    static func texture(from pb: CVPixelBuffer, device: MTLDevice) -> MTLTexture {
        var texRef: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil, .bgra8Unorm, CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb), 0, &texRef)
        return CVMetalTextureGetTexture(texRef!)!
    }
}

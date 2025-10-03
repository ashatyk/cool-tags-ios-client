import SwiftUI
import MetalKit
import simd

@main
struct ShaderPlaygroundApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct MetalView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal unavailable") }
        view.device = device
        view.colorPixelFormat = .bgra8Unorm       // с альфой
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0) // прозрачный
        
        view.isOpaque = false
        view.backgroundColor = .clear
        (view.layer as? CAMetalLayer)?.isOpaque = false
            
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.contentScaleFactor = 1.0
        view.autoResizeDrawable = false

        context.coordinator.configure(view: view)
        return view
    }
    func updateUIView(_ uiView: MTKView, context: Context) {}
    func makeCoordinator() -> Renderer { Renderer() }
}

final class Renderer: NSObject, MTKViewDelegate {
    
    struct Uniforms {
        var uResolution: SIMD2<Float> = .init(900, 1200)
        var uTime: Float = 0
        var _pad: SIMD3<Float> = .zero
    }
    struct EffectUniforms {
        var uEdgeFeatherPx: Float = 0.5
        var uCenterTranslation: Float = 0
        var uColor0: SIMD4<Float> = .init(1.0,0.0,0.0,1.0)
        var uColor1: SIMD4<Float> = .init(0.0,1.0,1.0,1.0)
        var uColor2: SIMD4<Float> = .init(1.0,0.0,0.6,1.0)
        var uRayStrength3: SIMD3<Float> = .init(1.0,1.0,1.0)
        var uRayLengthPx3: SIMD3<Float> = .init(300.0,200.0,400.0)
        var uRaySharpness3: SIMD3<Float> = .init(1.0,1.0,1.0)
        var uRayDensity3: SIMD3<Float> = .init(0.45,0.2,0.2)
        var uRaySpeed3: SIMD3<Float> = .init(1.0,1.0,1.0)
        var uRayFalloff3: SIMD3<Float> = .init(0.02,0.02,0.01)
        var uRayStartSoftPx3: SIMD3<Float> = .init(1.0,1.0,1.0)
        var uJoinSoftness3: SIMD3<Float> = .init(0.1,1.0,1.0)
    }
    struct PolyUniforms {
        var uPointAABB: SIMD4<Float> = .init(0.48, 0.67, 0.62, 0.92) // [minX,minY,maxX,maxY]
        var uPointTexelCount: Int32 = 14
        var uPointTextureDim: SIMD2<Float> = .init(4, 4)
        var _pad: Int32 = 0
    }

    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var pipeline: MTLRenderPipelineState!
    private var texLoader: MTKTextureLoader!

    private var uniforms = Uniforms()
    private var effect   = EffectUniforms()
    private var poly     = PolyUniforms()

    private var uBuffer: MTLBuffer!
    private var eBuffer: MTLBuffer!
    private var pBuffer: MTLBuffer!

    private var pointTex: MTLTexture!
    private var pointSamp: MTLSamplerState!

    private var t0: CFTimeInterval = CACurrentMediaTime()

    func configure(view: MTKView) {
        device = view.device
        queue = device.makeCommandQueue()
        
        texLoader = MTKTextureLoader(device: device)

        let lib = try! device.makeDefaultLibrary(bundle: .main)
        let desc = MTLRenderPipelineDescriptor()
        
        desc.vertexFunction = lib.makeFunction(name: "vert")
        desc.fragmentFunction = lib.makeFunction(name: "frag")
        
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        
        pipeline = try! device.makeRenderPipelineState(descriptor: desc)

        uBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.stride, options: [])
        eBuffer = device.makeBuffer(length: MemoryLayout<EffectUniforms>.stride, options: [])
        pBuffer = device.makeBuffer(length: MemoryLayout<PolyUniforms>.stride, options: [])

        let b64 = "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAUElEQVR4AQBEALv/AoGsAP9+rQD/fq4A/32vAP8C+wcAAP49AAD+PQAAAzwAAAIeOAAAIQEAACL9AAAdwgAAAgHBAAD3wAAAYhgAAWNTAAEAAAD//9KQmDAAAAAGSURBVAMADCQSjSgNtaQAAAAASUVORK5CYII="
        
        if let data = Data(base64Encoded: b64) {
            pointTex = try? texLoader.newTexture(data: data, options: [.SRGB: false,.generateMipmaps: false])
            if let t = pointTex { poly.uPointTextureDim = .init(Float(t.width), Float(t.height)) }
        }

        view.delegate = self
    }

    func draw(in view: MTKView) {
        guard let rpd = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        uniforms.uTime = Float(CACurrentMediaTime() - t0)
        
        memcpy(uBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)
        memcpy(eBuffer.contents(), &effect,   MemoryLayout<EffectUniforms>.stride)
        memcpy(pBuffer.contents(), &poly,     MemoryLayout<PolyUniforms>.stride)

        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBuffer(uBuffer, offset: 0, index: 0)
        enc.setFragmentBuffer(eBuffer, offset: 0, index: 1)
        enc.setFragmentBuffer(pBuffer, offset: 0, index: 2)
        
        if let pointTex { enc.setFragmentTexture(pointTex, index: 0) }

        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
}

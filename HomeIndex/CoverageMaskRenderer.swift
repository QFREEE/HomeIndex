//
//  CoverageMaskRenderer.swift
//  HomeIndex
//
//  CPU-based triangle rasterizer for coverage mask generation.
//  Projects LiDAR mesh triangles to screen space and rasterizes them
//  into a low-resolution mask for "unscanned area" visualization.
//
//  PORTRAIT ONLY - orientation is hardcoded.
//

internal import ARKit
import CoreGraphics
import UIKit
import simd

class CoverageMaskRenderer {
    // Mask dimensions (portrait 9:16 aspect ratio)
    let maskW: Int = 270
    let maskH: Int = 480

    // Pixel buffer: 0 = uncovered, 255 = covered
    private var mask: [UInt8]

    // Throttling
    private var lastUpdateTime: CFAbsoluteTime = 0
    private let minUpdateInterval: CFAbsoluteTime = 0.1 // 10 FPS max

    // Debug stats
    private(set) var lastUpdateDurationMs: Double = 0
    private(set) var trianglesProcessed: Int = 0

    init() {
        mask = [UInt8](repeating: 0, count: maskW * maskH)
    }

    // MARK: - Main Update

    /// Updates the coverage mask by projecting mesh triangles to screen space.
    /// Returns true if the mask was updated, false if throttled.
    /// - Parameter maxRange: Maximum distance in meters to include geometry (default 5.0m)
    func update(frame: ARFrame, viewportSize: CGSize, meshAnchors: [ARMeshAnchor], maxRange: Float = 5.0) -> Bool {
        // Throttle check
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastUpdateTime >= minUpdateInterval else {
            return false
        }
        lastUpdateTime = now

        let startTime = CFAbsoluteTimeGetCurrent()

        // Clear mask
        mask = [UInt8](repeating: 0, count: maskW * maskH)
        trianglesProcessed = 0

        // Get camera matrices (PORTRAIT ONLY)
        let orientation: UIInterfaceOrientation = .portrait
        let viewMatrix = frame.camera.viewMatrix(for: orientation)
        let projMatrix = frame.camera.projectionMatrix(
            for: orientation,
            viewportSize: viewportSize,
            zNear: 0.001,
            zFar: 100.0
        )

        // Combined view-projection matrix
        let viewProj = projMatrix * viewMatrix

        // Extract camera position from view matrix (inverse of view matrix's translation)
        let cameraPosition = frame.camera.transform.columns.3

        // Process each mesh anchor
        for meshAnchor in meshAnchors {
            processMeshAnchor(
                meshAnchor,
                viewProj: viewProj,
                viewportSize: viewportSize,
                cameraPosition: SIMD3<Float>(cameraPosition.x, cameraPosition.y, cameraPosition.z),
                maxRange: maxRange
            )
        }

        lastUpdateDurationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        return true
    }

    // MARK: - Mesh Processing

    private func processMeshAnchor(
        _ meshAnchor: ARMeshAnchor,
        viewProj: simd_float4x4,
        viewportSize: CGSize,
        cameraPosition: SIMD3<Float>,
        maxRange: Float
    ) {
        let geometry = meshAnchor.geometry
        let worldTransform = meshAnchor.transform

        // Extract vertices
        let vertices = geometry.vertices
        let vertexStride = vertices.stride / MemoryLayout<Float>.size
        let vertexPointer = vertices.buffer.contents().bindMemory(
            to: Float.self,
            capacity: vertices.count * vertexStride
        )

        // Extract faces
        let faces = geometry.faces
        guard faces.indexCountPerPrimitive == 3 else { return } // Only triangles

        let facePointer = faces.buffer.contents().bindMemory(
            to: UInt32.self,
            capacity: faces.count * 3
        )

        // Project all vertices to screen space first (cache for reuse)
        var projectedVertices: [(x: Int, y: Int, valid: Bool)] = []
        projectedVertices.reserveCapacity(vertices.count)

        let maxRangeSquared = maxRange * maxRange

        for i in 0..<vertices.count {
            let base = i * vertexStride
            let localPos = SIMD3<Float>(
                vertexPointer[base],
                vertexPointer[base + 1],
                vertexPointer[base + 2]
            )

            // Local to world
            let worldPos4 = worldTransform * SIMD4<Float>(localPos, 1)
            let worldPos = SIMD3<Float>(worldPos4.x, worldPos4.y, worldPos4.z)

            // Distance check (squared for performance)
            let delta = worldPos - cameraPosition
            let distanceSquared = delta.x * delta.x + delta.y * delta.y + delta.z * delta.z
            guard distanceSquared <= maxRangeSquared else {
                projectedVertices.append((x: 0, y: 0, valid: false))
                continue
            }

            // World to clip
            let clipPos = viewProj * worldPos4

            // Behind camera check
            guard clipPos.w > 0.001 else {
                projectedVertices.append((x: 0, y: 0, valid: false))
                continue
            }

            // Clip to NDC
            let ndcX = clipPos.x / clipPos.w
            let ndcY = clipPos.y / clipPos.w

            // NDC to screen (portrait)
            let screenX = (ndcX + 1) * 0.5 * Float(viewportSize.width)
            let screenY = (1 - ndcY) * 0.5 * Float(viewportSize.height) // Y inverted for UIKit

            // Screen to mask coords
            let mx = Int(screenX / Float(viewportSize.width) * Float(maskW))
            let my = Int(screenY / Float(viewportSize.height) * Float(maskH))

            projectedVertices.append((x: mx, y: my, valid: true))
        }

        // Rasterize each triangle
        for i in 0..<faces.count {
            let offset = i * 3
            let i0 = Int(facePointer[offset])
            let i1 = Int(facePointer[offset + 1])
            let i2 = Int(facePointer[offset + 2])

            let p0 = projectedVertices[i0]
            let p1 = projectedVertices[i1]
            let p2 = projectedVertices[i2]

            // Skip if any vertex is invalid (behind camera)
            guard p0.valid && p1.valid && p2.valid else { continue }

            rasterizeTriangle(
                p0: (p0.x, p0.y),
                p1: (p1.x, p1.y),
                p2: (p2.x, p2.y)
            )
            trianglesProcessed += 1
        }
    }

    // MARK: - Triangle Rasterization

    private func rasterizeTriangle(p0: (Int, Int), p1: (Int, Int), p2: (Int, Int)) {
        // Compute bounding box
        let minX = max(0, min(p0.0, min(p1.0, p2.0)))
        let maxX = min(maskW - 1, max(p0.0, max(p1.0, p2.0)))
        let minY = max(0, min(p0.1, min(p1.1, p2.1)))
        let maxY = min(maskH - 1, max(p0.1, max(p1.1, p2.1)))

        // Skip degenerate or off-screen triangles
        guard minX <= maxX && minY <= maxY else { return }

        // Edge function for point-in-triangle test
        @inline(__always)
        func edgeFunction(_ a: (Int, Int), _ b: (Int, Int), _ c: (Int, Int)) -> Int {
            (c.0 - a.0) * (b.1 - a.1) - (c.1 - a.1) * (b.0 - a.0)
        }

        // Rasterize
        for y in minY...maxY {
            for x in minX...maxX {
                let w0 = edgeFunction(p1, p2, (x, y))
                let w1 = edgeFunction(p2, p0, (x, y))
                let w2 = edgeFunction(p0, p1, (x, y))

                // Check if all same sign (inside triangle)
                if (w0 >= 0 && w1 >= 0 && w2 >= 0) || (w0 <= 0 && w1 <= 0 && w2 <= 0) {
                    mask[y * maskW + x] = 255
                }
            }
        }
    }

    // MARK: - CGImage Generation

    /// Returns grayscale CGImage where covered=255, uncovered=0
    func makeMaskCGImage() -> CGImage? {
        // Use CFData to properly retain the pixel buffer
        guard let cfData = CFDataCreate(nil, mask, mask.count) else { return nil }
        guard let provider = CGDataProvider(data: cfData) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceGray()

        return CGImage(
            width: maskW,
            height: maskH,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: maskW,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Returns inverted grayscale CGImage where uncovered=255 (white), covered=0 (black)
    /// Use this for masking stripes overlay (white areas show stripes)
    func makeInvertedMaskCGImage() -> CGImage? {
        // Invert: uncovered (0) -> 255, covered (255) -> 0
        let inverted = mask.map { 255 - $0 }

        // Use CFData to properly retain the pixel buffer
        guard let cfData = CFDataCreate(nil, inverted, inverted.count) else { return nil }
        guard let provider = CGDataProvider(data: cfData) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceGray()

        return CGImage(
            width: maskW,
            height: maskH,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: maskW,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

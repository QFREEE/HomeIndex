//
//  ARSessionManager.swift
//  HomeIndex
//
//  Created by Claude on 1/5/26.
//

internal import ARKit
import RealityKit
import simd
import Combine

@MainActor
@Observable
class ARSessionManager: NSObject {
    var arView: ARView?
    var mappingStatus: ARFrame.WorldMappingStatus = .notAvailable
    var relocalizationState: RelocalizationState = .relocalizing
    
    // Mesh Visualization
    var isMeshVisualizationEnabled: Bool = true {
        didSet {
            updateMeshVisibility()
        }
    }

    // LiDAR Range (meters) - filters mesh data beyond this distance
    // Range: 0.5m to 5.0m (iPhone LiDAR max ~5m)
    var lidarRange: Float = 5.0

    // Exposed metric for UI
    var meshAnchorsCount: Int = 0

    // RealityKit visualization entities
    private(set) var meshAnchors: [UUID: AnchorEntity] = [:]

    // Raw ARMeshAnchor storage for CPU projection (coverage mask)
    private(set) var rawMeshAnchors: [UUID: ARMeshAnchor] = [:]

    /// Returns current mesh anchors for coverage mask rendering
    func currentMeshAnchors() -> [ARMeshAnchor] {
        Array(rawMeshAnchors.values)
    }
    
    // Scanner-style material: Unlit, Cyan, Translucent
    private let meshMaterial = UnlitMaterial(color: UIColor.cyan.withAlphaComponent(0.5))
    
    // Internal state for heuristic checks
    private var stableFramesCount: Int = 0

    private let requiredStableFrames = 15
    private var targetAnchorName: String?
    private var foundTargetAnchor: ARAnchor?
    
    // Visual marker reference
    private var markerAnchor: AnchorEntity?
    
    // MARK: - Session Control
    
    func startScanning() {
        guard let arView = arView else { return }
        
        // Reset state
        relocalizationState = .ready
        stableFramesCount = 0
        targetAnchorName = nil
        foundTargetAnchor = nil
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        
        arView.session.delegate = self
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        removeMarker()
        resetMesh()
    }
    
    func startFinding(worldMap: ARWorldMap, expectingAnchorName name: String) {
        guard let arView = arView else { return }
        
        // Reset state
        relocalizationState = .relocalizing
        stableFramesCount = 0
        targetAnchorName = name
        foundTargetAnchor = nil
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.initialWorldMap = worldMap
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        
        arView.session.delegate = self
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        removeMarker()
        resetMesh()
        
        // Timeout check
        Task {
            try? await Task.sleep(nanoseconds: 10 * 1_000_000_000) // 10 seconds
            if case .relocalizing = relocalizationState {
                 relocalizationState = .failed("Marker not restored. Please rescan.")
            }
        }
    }

    private func attemptTransitionToReady() {
        guard targetAnchorName != nil else { return }
        if case .ready = relocalizationState { return }
        if case .failed = relocalizationState { return }
        
        if stableFramesCount >= requiredStableFrames, let anchor = foundTargetAnchor {
            relocalizationState = .ready
            addVisualMarker(at: anchor.transform)
        }
    }

    
    func stopSession() {
        arView?.session.pause()
        removeMarker()
    }
    
    // MARK: - Anchor Management
    
    func addNamedAnchor(transform: simd_float4x4, name: String) {
        let anchor = ARAnchor(name: name, transform: transform)
        arView?.session.add(anchor: anchor)
        
        // For visual feedback in Scan Mode, we also want to see it immediately
        // Note: in Scan Mode we add the entity manually. In Find Mode we wait for the anchor to be restored.
        addVisualMarker(at: transform)
    }
    
    // Helper to add the sphere entity
    private func addVisualMarker(at transform: simd_float4x4) {
        guard let arView = arView else { return }
        
        // Remove existing if any
        removeMarker()
        
        let anchorEntity = AnchorEntity(world: transform)
        
        let sphere = MeshResource.generateSphere(radius: 0.05)
        let material = SimpleMaterial(color: .systemBlue, isMetallic: false)
        let model = ModelEntity(mesh: sphere, materials: [material])
        
        anchorEntity.addChild(model)
        arView.scene.addAnchor(anchorEntity)
        
        markerAnchor = anchorEntity
    }
    
    // Deprecated: use addNamedAnchor in Scan Mode
    func placeMarkerAtScreenCenter() -> simd_float4x4? {
        guard let arView = arView else { return nil }
        
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        let results = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .any)
        
        guard let firstResult = results.first else { return nil }
        
        let transform = firstResult.worldTransform
        
        // Remove existing marker
        removeMarker()
        
        // Just return transform, let caller invoke addNamedAnchor
        return transform
    }

    private func removeMarker() {
        if let anchor = markerAnchor {
            arView?.scene.removeAnchor(anchor)
            markerAnchor = nil
        }
    }
    
    // MARK: - World Map Capture
    
    func captureWorldMap(completion: @escaping (Result<ARWorldMap, Error>) -> Void) {
        guard let arView = arView else {
            completion(.failure(ARSessionError.noSession))
            return
        }
        
        arView.session.getCurrentWorldMap { worldMap, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else if let worldMap = worldMap {
                    completion(.success(worldMap))
                } else {
                    completion(.failure(ARSessionError.worldMapCaptureFailed))
                }
            }
        }
    }
    
    // MARK: - Snapshot
    
    func snapshotPreview(completion: @escaping (UIImage?) -> Void) {
        guard let arView = arView else {
            completion(nil)
            return
        }
        arView.snapshot(saveToHDR: false) { image in
            completion(image)
        }
    }


    // MARK: - Mesh Visualization

    func resetMesh() {
        // Since we are using AnchorEntity(anchor:), we don't strictly need to manually maintain a list
        // if we trust ARView to clean up, BUT RealityKit doesn't auto-add mesh anchors.
        // We do manage them.
        for anchor in meshAnchors.values {
            arView?.scene.removeAnchor(anchor)
        }
        meshAnchors.removeAll()
        rawMeshAnchors.removeAll()
        meshAnchorsCount = 0
    }

    private func updateMeshVisibility() {
        for anchor in meshAnchors.values {
            anchor.isEnabled = isMeshVisualizationEnabled
        }
    }

    private func updateMesh(for meshAnchor: ARMeshAnchor) {
        guard let arView = arView else { return }

        // 1. Check if we already have an entity for this anchor
        if let existingAnchorEntity = meshAnchors[meshAnchor.identifier] {
            // Because we used AnchorEntity(anchor:), the TRANSFORM is updated automatically by RealityKit.
            // We only need to check if the GEOMETRY (mesh) changed.
            // ARMeshAnchor usually regenerates geometry identifier or we can just update every time.
            // For performance, we'll just regenerate the mesh resource.
            
            if let modelEntity = existingAnchorEntity.children.first as? ModelEntity {
                // Regenerate mesh
                if let newMesh = generateWireframeMesh(from: meshAnchor.geometry) {
                    modelEntity.model?.mesh = newMesh
                }
            }
        } else {
            // 2. Create new AnchorEntity tied to the ARAnchor
            // This ensures tight tracking (no lag/drift relative to camera feed)
            let anchorEntity = AnchorEntity(anchor: meshAnchor)
            
            // Generate wireframe mesh
            if let meshResource = generateWireframeMesh(from: meshAnchor.geometry) {
                // Use Unlit material for "Scanner" look (bright cyan/green)
                // Using .cyan for high techness
                let material = UnlitMaterial(color: .cyan)
                let model = ModelEntity(mesh: meshResource, materials: [material])
                
                anchorEntity.addChild(model)
                anchorEntity.isEnabled = isMeshVisualizationEnabled
                
                arView.scene.addAnchor(anchorEntity)
                meshAnchors[meshAnchor.identifier] = anchorEntity
                self.meshAnchorsCount = self.meshAnchors.count
            }
        }
    }
    
    private func generateWireframeMesh(from geometry: ARMeshGeometry) -> MeshResource? {
        var desc = MeshDescriptor()

        // 1. Extract Vertices (positions)
        let vertices = geometry.vertices
        let vertexStride = vertices.stride / MemoryLayout<Float>.size
        let vertexPointer = vertices.buffer.contents().bindMemory(to: Float.self, capacity: vertices.count * vertexStride)

        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(vertices.count)
        for i in 0..<vertices.count {
            let base = i * vertexStride
            let x = vertexPointer[base]
            let y = vertexPointer[base + 1]
            let z = vertexPointer[base + 2]
            positions.append(SIMD3<Float>(x, y, z))
        }
        desc.positions = MeshBuffers.Positions(positions)

        // 2. Extract triangle indices directly from ARMeshGeometry
        let faces = geometry.faces
        let indexCountPerPrimitive = faces.indexCountPerPrimitive // should be 3 for triangles
        guard indexCountPerPrimitive == 3 else {
            // Fallback: if not triangles, we cannot build a mesh here
            return try? MeshResource.generate(from: [desc])
        }

        let facePointer = faces.buffer.contents().bindMemory(to: UInt32.self, capacity: faces.count * indexCountPerPrimitive)

        var triangleIndices: [UInt32] = []
        triangleIndices.reserveCapacity(faces.count * 3)
        for i in 0..<faces.count {
            let offset = i * indexCountPerPrimitive
            let i0 = facePointer[offset]
            let i1 = facePointer[offset + 1]
            let i2 = facePointer[offset + 2]
            triangleIndices.append(i0)
            triangleIndices.append(i1)
            triangleIndices.append(i2)
        }

        // 3. Configure primitives as triangles
        desc.primitives = .triangles(triangleIndices)

        return try? MeshResource.generate(from: [desc])
    }
}



// MARK: - Relocalization State
enum RelocalizationState {
    case relocalizing
    case ready
    case failed(String)
}

// MARK: - ARSessionDelegate

extension ARSessionManager: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            self.mappingStatus = frame.worldMappingStatus
            
            // Only enforce gating logic if we are "Finding"
            guard targetAnchorName != nil else { return }
            
            // If already ready or failed, do nothing
            if case .ready = relocalizationState { return }
            if case .failed = relocalizationState { return }
            
            let isTrackingNormal = frame.camera.trackingState == .normal
            let isMappedOrExtending = (frame.worldMappingStatus == .mapped || frame.worldMappingStatus == .extending)
            
            if isTrackingNormal && isMappedOrExtending {
                stableFramesCount += 1
            } else {
                stableFramesCount = 0
            }
            
            attemptTransitionToReady()
        }
    }
    
    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Task { @MainActor in
            // Handle Mesh Anchors
            for anchor in anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    // Store raw anchor for coverage mask projection
                    self.rawMeshAnchors[meshAnchor.identifier] = meshAnchor
                    self.updateMesh(for: meshAnchor)
                    continue
                }
            }

            self.meshAnchorsCount = self.rawMeshAnchors.count

            guard let targetName = targetAnchorName else { return }

            for anchor in anchors {
                if anchor.name == targetName {
                    foundTargetAnchor = anchor
                    attemptTransitionToReady()
                }
            }
        }
    }
    
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
         Task { @MainActor in
             for anchor in anchors {
                 if let meshAnchor = anchor as? ARMeshAnchor {
                     // Update raw anchor for coverage mask projection
                     self.rawMeshAnchors[meshAnchor.identifier] = meshAnchor
                     self.updateMesh(for: meshAnchor)
                 }

                 // Also check if our marker moved (unlikely for ARAnchor but possible during relocalization correction)
                 if let found = foundTargetAnchor, found.identifier == anchor.identifier {
                      // Update visual marker position if needed?
                      // Actually RealityKit AnchorEntity(world: transform) is static unless updated.
                      // But AnchorEntity(anchor: anchor) would follow automatically.
                      // We used AnchorEntity(world:).

                      // Ideally we should update the visual marker if the anchor shifts.
                      // Let's defer this specific fix for now to focus on mesh, but valid point.
                 }
             }
         }
    }
    
    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    // Remove raw anchor
                    self.rawMeshAnchors.removeValue(forKey: meshAnchor.identifier)

                    // Remove RealityKit entity
                    if let entity = self.meshAnchors[meshAnchor.identifier] {
                        self.arView?.scene.removeAnchor(entity)
                        self.meshAnchors.removeValue(forKey: meshAnchor.identifier)
                    }

                    self.meshAnchorsCount = self.rawMeshAnchors.count
                }
            }
        }
    }
    
    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        // We handle tracking state in didUpdate
    }
}

// MARK: - Errors

enum ARSessionError: LocalizedError {
    case noSession
    case worldMapCaptureFailed

    var errorDescription: String? {
        switch self {
        case .noSession:
            return "AR session not available"
        case .worldMapCaptureFailed:
            return "Failed to capture world map"
        }
    }
}


//
//  ARScanView.swift
//  HomeIndex
//
//  Created by Claude on 1/5/26.
//

import SwiftUI
import simd
internal import ARKit
import RealityKit

struct ARScanView: View {
    @Environment(SpaceStore.self) var store
    @Environment(ARSessionManager.self) var sessionManager
    @Environment(\.dismiss) var dismiss

    let space: SpaceRecord
    
    // Scanner State Machine
    enum ScannerState {
        case idle
        case recording
        case processing
        case saved
    }
    
    @State private var scannerState: ScannerState = .idle
    @State private var markerPlaced = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var navigateToDetail = false
    @State private var savedSpace: SpaceRecord?

    // Coverage mask state
    @State private var coverageMaskRenderer = CoverageMaskRenderer()
    @State private var coverageMaskImage: CGImage?
    @State private var maskUpdateTimer: Timer?
    @State private var maskUpdateFPS: Double = 0

    // Coverage computation
    private var coverageLevel: String {
        let count = sessionManager.meshAnchorsCount
        if count < 5 { return "Low" }
        if count < 15 { return "Medium" }
        return "High"
    }

    var body: some View {
        ZStack {
            // Full-screen AR
            ARViewContainer(sessionManager: sessionManager)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    // Hide keyboard/menus if any
                }

            // Coverage stripes overlay (shows unscanned areas)
            ScannerStripesOverlay(
                maskImage: coverageMaskImage,
                isVisible: scannerState == .recording
            )
            .edgesIgnoringSafeArea(.all)

            // --- CENTER OVERLAY ---
            if scannerState != .processing {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .thin))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // --- TOP OVERLAY ---
            VStack {
                ZStack(alignment: .top) {
                    // Back Button (Left)
                    HStack {
                        Button {
                            if scannerState == .recording {
                                // Confirm cancel? sticking to simple dismiss for now
                                sessionManager.stopSession()
                            }
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    // Status Label (Center)
                    Text(statusLabelText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    
                    // Mode Pill (Right) - Toggle
                    HStack {
                        Spacer()
                        Button(action: {
                            sessionManager.isMeshVisualizationEnabled.toggle()
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: sessionManager.isMeshVisualizationEnabled ? "eye" : "eye.slash")
                                Text("Mesh (LiDAR)")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(sessionManager.isMeshVisualizationEnabled ? Color.cyan.opacity(0.5) : Color.black.opacity(0.4))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 50)
                
                Spacer()
                
                // --- BOTTOM OVERLAY ---
                VStack(spacing: 20) {
                    // Coverage Indicator + Debug HUD
                    if scannerState == .recording {
                        HStack(spacing: 12) {
                            Text("Coverage: \(coverageLevel)")
                            Text("M:\(sessionManager.meshAnchorsCount)")
                            Text("T:\(coverageMaskRenderer.trianglesProcessed)")
                            Text("\(String(format: "%.0f", maskUpdateFPS))fps")
                        }
                        .font(.caption2.monospaced())
                        .foregroundColor(.white)
                        .padding(6)
                        .background(.black.opacity(0.4))
                        .cornerRadius(4)

                        // LiDAR Range Slider
                        VStack(spacing: 4) {
                            Text("Range: \(String(format: "%.1f", sessionManager.lidarRange))m")
                                .font(.caption.monospaced())
                                .foregroundColor(.white)

                            HStack(spacing: 8) {
                                Text("0.5m")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.6))
                                Slider(value: Binding(
                                    get: { Double(sessionManager.lidarRange) },
                                    set: { sessionManager.lidarRange = Float($0) }
                                ), in: 0.5...5.0, step: 0.1)
                                .tint(.cyan)
                                Text("5m")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.4))
                        .cornerRadius(8)
                    }
                    
                    HStack(alignment: .center) {
                         // Spacer to balance layout
                        Color.clear.frame(width: 80, height: 1)
                        
                        Spacer()
                        
                        // Record Button
                        if scannerState == .processing {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                        } else {
                            Button(action: handleRecordTap) {
                                ZStack {
                                    Circle()
                                        .stroke(.white, lineWidth: 4)
                                        .frame(width: 72, height: 72)
                                    
                                    RoundedRectangle(cornerRadius: scannerState == .recording ? 8 : 36)
                                        .fill(Color.red)
                                        .frame(width: scannerState == .recording ? 32 : 56,
                                               height: scannerState == .recording ? 32 : 56)
                                        .animation(.spring(response: 0.3), value: scannerState)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Place Marker Button (Right side)
                        if scannerState == .recording {
                            Button(action: placeMarker) {
                                VStack(spacing: 4) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .font(.title2)
                                    Text("Marker")
                                        .font(.caption2)
                                }
                                .foregroundColor(markerPlaced ? .green : .white)
                                .padding(12)
                                .background(.black.opacity(0.4))
                                .clipShape(Circle())
                            }
                            .frame(width: 80)
                        } else {
                            Color.clear.frame(width: 80, height: 1)
                        }
                    }
                    .padding(.bottom, 40)
                    .padding(.horizontal, 30)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            sessionManager.startScanning()
            startMaskUpdateTimer()
        }
        .onDisappear {
            sessionManager.stopSession()
            stopMaskUpdateTimer()
        }
        .alert("Place Marker", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .navigationDestination(isPresented: $navigateToDetail) {
            if let saved = savedSpace {
                SpaceDetailView(space: saved)
            }
        }
    }

    private var statusLabelText: String {
        switch scannerState {
        case .idle: return "READY TO SCAN"
        case .recording: return "SCANNING"
        case .processing: return "PROCESSING..."
        case .saved: return "SAVED"
        }
    }

    private func handleRecordTap() {
        switch scannerState {
        case .idle:
            scannerState = .recording
        case .recording:
            // User requested STOP
            if !markerPlaced {
                errorMessage = "Place a marker first."
                showError = true
            } else {
                finishScan()
            }
        default: break
        }
    }
    
    private func placeMarker() {
        if let transform = sessionManager.placeMarkerAtScreenCenter() {
            sessionManager.addNamedAnchor(transform: transform, name: "homeindex.marker.\(space.id.uuidString)")
            markerPlaced = true
            markerTransform = transform
            
            // Haptic feedback (optional but good for UX)
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        } else {
            // Optional: show toast "Point at surface"
        }
    }
    
    // Stored transform to persist
    @State private var markerTransform: simd_float4x4?
    
    private func finishScan() {
        scannerState = .processing
        
        // Slight delay to fake processing UX (and let UI update)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            sessionManager.captureWorldMap { result in
                switch result {
                case .success(let worldMap):
                    sessionManager.snapshotPreview { previewImage in
                        saveData(worldMap: worldMap, image: previewImage)
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showError = true
                    scannerState = .recording // Revert
                }
            }
        }
    }
    
    private func saveData(worldMap: ARWorldMap, image: UIImage?) {
        guard let transform = markerTransform else {
            errorMessage = "Internal Error: No marker structure"
            showError = true
            return
        }
        
        let imageToSave = image ?? UIImage()
        
        do {
             let mapPath = try store.saveWorldMap(spaceId: space.id, worldMap: worldMap)
             let previewPath = store.savePreviewImage(spaceId: space.id, image: imageToSave)
             
             var updated = space
             updated.worldMapPath = mapPath
             updated.anchorTransform = SpaceRecord.encode(transform)
             updated.previewImagePath = previewPath
             updated.updatedAt = Date()
             
             DispatchQueue.main.async {
                 store.updateSpace(updated)
                 savedSpace = updated
                 scannerState = .saved
                 navigateToDetail = true
             }
        } catch {
            DispatchQueue.main.async {
                errorMessage = error.localizedDescription
                showError = true
                scannerState = .recording
            }
        }
    }

    // MARK: - Coverage Mask Timer

    private func startMaskUpdateTimer() {
        maskUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] _ in
            updateCoverageMask()
        }
    }

    private func stopMaskUpdateTimer() {
        maskUpdateTimer?.invalidate()
        maskUpdateTimer = nil
    }

    private func updateCoverageMask() {
        guard let arView = sessionManager.arView,
              let frame = arView.session.currentFrame else { return }

        let meshAnchors = sessionManager.currentMeshAnchors()
        let startTime = CFAbsoluteTimeGetCurrent()

        if coverageMaskRenderer.update(
            frame: frame,
            viewportSize: arView.bounds.size,
            meshAnchors: meshAnchors,
            maxRange: sessionManager.lidarRange
        ) {
            coverageMaskImage = coverageMaskRenderer.makeInvertedMaskCGImage()
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            if duration > 0 {
                maskUpdateFPS = 1.0 / duration
            }
        }
    }
}

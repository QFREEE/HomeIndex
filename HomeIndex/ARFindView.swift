//
//  ARFindView.swift
//  HomeIndex
//
//  Created by Claude on 1/5/26.
//

import SwiftUI
internal import ARKit
import RealityKit

struct ARFindView: View {
    @Environment(SpaceStore.self) var store
    @Environment(ARSessionManager.self) var sessionManager
    @Environment(\.dismiss) var dismiss

    let space: SpaceRecord
    @State private var errorMessage: String?
    @State private var showError = false

    // Coverage mask state
    @State private var coverageMaskRenderer = CoverageMaskRenderer()
    @State private var coverageMaskImage: CGImage?
    @State private var maskUpdateTimer: Timer?

    /// Stripes visible during relocalization, fade out when ready
    private var stripesVisible: Bool {
        if case .relocalizing = sessionManager.relocalizationState {
            return true
        }
        return false
    }

    var body: some View {
        ZStack {
            // Full-screen AR
            ARViewContainer(sessionManager: sessionManager)
                .edgesIgnoringSafeArea(.all)

            // Coverage stripes overlay (shows unscanned areas, fades when ready)
            ScannerStripesOverlay(
                maskImage: coverageMaskImage,
                isVisible: stripesVisible
            )
            .edgesIgnoringSafeArea(.all)

            // --- TOP OVERLAY ---
            VStack {
                ZStack(alignment: .top) {
                    // Back Button (Left)
                    HStack {
                        Button {
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
                        .background(statusBackgroundStyle)
                        .clipShape(Capsule())
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
                                Text("Mesh")
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
                
                // Debug / Info line
                HStack(spacing: 12) {
                     Text("M: \(sessionManager.meshAnchorsCount)")
                     Text("T: \(sessionManager.arView?.session.currentFrame?.camera.trackingState.presentationString ?? "-")")
                     Text("W: \(sessionManager.mappingStatus.presentationString)")
                }
                .font(.caption2)
                .fontDesign(.monospaced)
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 8)
                
                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadAndStart()
            startMaskUpdateTimer()
        }
        .onDisappear {
            sessionManager.stopSession()
            stopMaskUpdateTimer()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { dismiss() }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }
    
    private var statusLabelText: String {
        switch sessionManager.relocalizationState {
        case .relocalizing: return "RELOCALIZING..."
        case .ready: return "LOCATION FOUND"
        case .failed: return "FAILED"
        }
    }
    
    private var statusBackgroundStyle: some ShapeStyle {
        switch sessionManager.relocalizationState {
        case .relocalizing:
            return AnyShapeStyle(.ultraThinMaterial)
        case .ready:
            return AnyShapeStyle(Color.green.opacity(0.8))
        case .failed:
            return AnyShapeStyle(Color.red.opacity(0.8))
        }
    }

    private func loadAndStart() {
        do {
            let worldMap = try store.loadWorldMap(path: space.worldMapPath)
            sessionManager.startFinding(worldMap: worldMap, expectingAnchorName: "homeindex.marker.\(space.id.uuidString)")
        } catch {
            errorMessage = "Could not load room. Please rescan."
            showError = true
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

        if coverageMaskRenderer.update(
            frame: frame,
            viewportSize: arView.bounds.size,
            meshAnchors: meshAnchors,
            maxRange: sessionManager.lidarRange
        ) {
            coverageMaskImage = coverageMaskRenderer.makeInvertedMaskCGImage()
        }
    }
}

extension ARCamera.TrackingState {
    var presentationString: String {
        switch self {
        case .notAvailable:
            return "Not Available"
        case .limited(let reason):
            switch reason {
            case .initializing: return "Limited (Init)"
            case .relocalizing: return "Limited (Reloc)"
            case .excessiveMotion: return "Limited (Motion)"
            case .insufficientFeatures: return "Limited (Low Light)"
            @unknown default: return "Limited"
            }
        case .normal:
            return "Normal"
        }
    }
}

extension ARFrame.WorldMappingStatus {
    var presentationString: String {
        switch self {
        case .notAvailable: return "Not Available"
        case .limited: return "Limited"
        case .extending: return "Extending"
        case .mapped: return "Mapped"
        @unknown default: return "Unknown"
        }
    }
}


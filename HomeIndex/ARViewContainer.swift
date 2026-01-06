//
//  ARViewContainer.swift
//  HomeIndex
//
//  Created by Claude on 1/5/26.
//

import SwiftUI
import RealityKit

struct ARViewContainer: UIViewRepresentable {
    let sessionManager: ARSessionManager

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        sessionManager.arView = arView
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // No updates needed
    }
}

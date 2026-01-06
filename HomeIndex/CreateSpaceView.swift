//
//  CreateSpaceView.swift
//  HomeIndex
//
//  Created by Claude on 1/5/26.
//

import SwiftUI

struct CreateSpaceView: View {
    @Environment(SpaceStore.self) var store
    @Environment(\.dismiss) var dismiss
    @State private var spaceName = ""
    @State private var navigateToScan = false
    @State private var createdSpace: SpaceRecord?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            TextField("Space Name", text: $spaceName)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .padding(.horizontal, 32)

            Button(action: startScan) {
                Text("Start Scan")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(spaceName.isEmpty ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(spaceName.isEmpty)
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
        .navigationTitle("Create Space")
        .navigationDestination(isPresented: $navigateToScan) {
            if let space = createdSpace {
                ARScanView(space: space)
            }
        }
    }

    private func startScan() {
        createdSpace = store.createSpace(name: spaceName)
        navigateToScan = true
    }
}

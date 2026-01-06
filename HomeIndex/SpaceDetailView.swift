//
//  SpaceDetailView.swift
//  HomeIndex
//
//  Created by Claude on 1/5/26.
//

import SwiftUI

struct SpaceDetailView: View {
    @Environment(SpaceStore.self) var store
    let space: SpaceRecord

    var body: some View {
        VStack(spacing: 24) {
            // Large preview image
            if let image = store.loadPreviewImage(path: space.previewImagePath) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
            }

            // Action buttons
            VStack(spacing: 12) {
                NavigationLink(destination: ARFindView(space: space)) {
                    Label("Find Marker", systemImage: "location.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                NavigationLink(destination: ARScanView(space: space)) {
                    Label("Rescan Room", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .navigationTitle(space.name)
    }
}

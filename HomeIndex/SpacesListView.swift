//
//  SpacesListView.swift
//  HomeIndex
//
//  Created by Claude on 1/5/26.
//

import SwiftUI

struct SpacesListView: View {
    @Environment(SpaceStore.self) var store

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.spaces) { space in
                    NavigationLink(destination: SpaceDetailView(space: space)) {
                        HStack(spacing: 12) {
                            // Preview thumbnail (60x60)
                            if let image = store.loadPreviewImage(path: space.previewImagePath) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 60, height: 60)
                                    .overlay {
                                        Image(systemName: "cube.transparent")
                                            .foregroundStyle(.secondary)
                                    }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(space.name)
                                    .font(.headline)
                                Text("Last scanned: \(space.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete(perform: deleteSpaces)
            }
            .navigationTitle("HomeIndex AR")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(destination: CreateSpaceView()) {
                        Image(systemName: "plus")
                    }
                }
            }
            .overlay {
                if store.spaces.isEmpty {
                    ContentUnavailableView(
                        "No Spaces",
                        systemImage: "cube.transparent",
                        description: Text("Tap + to scan your first room")
                    )
                }
            }
        }
    }

    private func deleteSpaces(at offsets: IndexSet) {
        for index in offsets {
            let space = store.spaces[index]
            store.deleteSpace(space)
        }
    }
}

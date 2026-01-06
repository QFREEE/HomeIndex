//
//  SpaceStore.swift
//  HomeIndex
//
//  Created by Claude on 1/5/26.
//

import Foundation
internal import ARKit
import UIKit

@Observable
class SpaceStore {
    var spaces: [SpaceRecord] = []

    private let fileManager = FileManager.default

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var spacesFileURL: URL {
        documentsDirectory.appendingPathComponent("spaces.json")
    }

    private var worldMapsDirectory: URL {
        documentsDirectory.appendingPathComponent("WorldMaps")
    }

    private var previewsDirectory: URL {
        documentsDirectory.appendingPathComponent("Previews")
    }

    init() {
        createDirectoriesIfNeeded()
        loadSpaces()
    }

    // MARK: - Directory Setup

    private func createDirectoriesIfNeeded() {
        try? fileManager.createDirectory(at: worldMapsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: previewsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - CRUD Operations

    func listSpaces() -> [SpaceRecord] {
        spaces
    }

    func createSpace(name: String) -> SpaceRecord {
        let space = SpaceRecord(name: name)
        spaces.append(space)
        saveSpaces()
        return space
    }

    func updateSpace(_ space: SpaceRecord) {
        if let index = spaces.firstIndex(where: { $0.id == space.id }) {
            spaces[index] = space
            saveSpaces()
        }
    }

    func deleteSpace(_ space: SpaceRecord) {
        // Remove files
        if !space.worldMapPath.isEmpty {
            try? fileManager.removeItem(atPath: space.worldMapPath)
        }
        if !space.previewImagePath.isEmpty {
            try? fileManager.removeItem(atPath: space.previewImagePath)
        }

        // Remove from array
        spaces.removeAll { $0.id == space.id }
        saveSpaces()
    }

    // MARK: - World Map Persistence

    func saveWorldMap(spaceId: UUID, worldMap: ARWorldMap) throws -> String {
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: worldMap,
            requiringSecureCoding: true
        )

        let fileURL = worldMapsDirectory.appendingPathComponent("\(spaceId.uuidString).worldmap")
        try data.write(to: fileURL)

        return fileURL.path
    }

    func loadWorldMap(path: String) throws -> ARWorldMap {
        let fileURL = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: fileURL)

        guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: ARWorldMap.self,
            from: data
        ) else {
            throw SpaceStoreError.worldMapDecodingFailed
        }

        return worldMap
    }

    // MARK: - Preview Image Persistence

    func savePreviewImage(spaceId: UUID, image: UIImage) -> String {
        let fileURL = previewsDirectory.appendingPathComponent("\(spaceId.uuidString).jpg")

        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: fileURL)
        }

        return fileURL.path
    }

    func loadPreviewImage(path: String) -> UIImage? {
        guard !path.isEmpty else { return nil }
        return UIImage(contentsOfFile: path)
    }

    // MARK: - Spaces JSON Persistence

    private func loadSpaces() {
        guard fileManager.fileExists(atPath: spacesFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: spacesFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            spaces = try decoder.decode([SpaceRecord].self, from: data)
        } catch {
            print("Failed to load spaces: \(error)")
        }
    }

    private func saveSpaces() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(spaces)
            try data.write(to: spacesFileURL)
        } catch {
            print("Failed to save spaces: \(error)")
        }
    }
}

// MARK: - Errors

enum SpaceStoreError: LocalizedError {
    case worldMapDecodingFailed

    var errorDescription: String? {
        switch self {
        case .worldMapDecodingFailed:
            return "Failed to decode world map data"
        }
    }
}

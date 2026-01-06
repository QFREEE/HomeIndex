//
//  SpaceRecord.swift
//  HomeIndex
//
//  Created by Claude on 1/5/26.
//

import Foundation
import simd

struct SpaceRecord: Identifiable, Codable {
    let id: UUID
    var name: String
    var worldMapPath: String
    var anchorTransform: [Float]  // 16 floats, column-major
    var previewImagePath: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.worldMapPath = ""
        self.anchorTransform = Array(repeating: 0, count: 16)
        self.previewImagePath = ""
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - simd_float4x4 Encoding/Decoding

extension SpaceRecord {
    /// Encode a 4x4 matrix to a 16-element array in column-major order
    static func encode(_ m: simd_float4x4) -> [Float] {
        print("DEBUG: Encoding transform. Translation: x=\(m.columns.3.x), y=\(m.columns.3.y), z=\(m.columns.3.z)")
        return [
            m.columns.0.x, m.columns.0.y, m.columns.0.z, m.columns.0.w,
            m.columns.1.x, m.columns.1.y, m.columns.1.z, m.columns.1.w,
            m.columns.2.x, m.columns.2.y, m.columns.2.z, m.columns.2.w,
            m.columns.3.x, m.columns.3.y, m.columns.3.z, m.columns.3.w
        ]
    }

    /// Decode a 16-element array (column-major) to a 4x4 matrix
    static func decode(_ array: [Float]) -> simd_float4x4 {
        guard array.count == 16 else {
            return matrix_identity_float4x4
        }
        
        print("DEBUG: Decoding transform. Translation: x=\(array[12]), y=\(array[13]), z=\(array[14])")

        return simd_float4x4(
            SIMD4<Float>(array[0], array[1], array[2], array[3]),
            SIMD4<Float>(array[4], array[5], array[6], array[7]),
            SIMD4<Float>(array[8], array[9], array[10], array[11]),
            SIMD4<Float>(array[12], array[13], array[14], array[15])
        )
    }
}

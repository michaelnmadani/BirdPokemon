import Foundation
import UIKit
import FirebaseStorage

struct PhotoUploader {
    struct Result {
        let downloadURL: URL
        let storagePath: String
    }

    enum UploadError: Error {
        case encodingFailed
        case notSignedIn
    }

    func upload(image: UIImage, uid: String, sightingId: String? = nil) async throws -> Result {
        guard let data = image.jpegData(compressionQuality: 0.82) else {
            throw UploadError.encodingFailed
        }
        let fileId = sightingId ?? UUID().uuidString
        let path = "users/\(uid)/sightings/\(fileId).jpg"
        let ref = FirebaseService.storage.reference(withPath: path)

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()
        return Result(downloadURL: url, storagePath: path)
    }
}

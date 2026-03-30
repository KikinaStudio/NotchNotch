import Foundation

struct Attachment: Identifiable {
    let id: UUID
    let fileName: String
    let fileType: String
    let textContent: String
    let fileURL: URL?

    init(
        id: UUID = UUID(),
        fileName: String,
        fileType: String,
        textContent: String,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.fileType = fileType
        self.textContent = textContent
        self.fileURL = fileURL
    }
}

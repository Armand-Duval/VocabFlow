import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var apkg: UTType {
        UTType(filenameExtension: "apkg", conformingTo: .zip)
            ?? UTType(filenameExtension: "apkg")
            ?? .zip
    }
}

struct ApkgDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.apkg] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

//
//  PhotoPickerItemExtension.swift
//  Cognitive-Work
//
//  Created by Jonas Fernando Nascimento Melo on 04/09/26.
//

import _PhotosUI_SwiftUI
import CloudKit

extension PhotosPickerItem {
    
    /// Converts a PhotosPickerItem into a CloudKit CKAsset by caching it locally
    func createCKAsset() async throws -> CKAsset? {
        //Load the raw binary data from the picker item
        guard let data = try await self.loadTransferable(type: Data.self) else {
            return nil
        }
        
        //Define a unique file URL in the app's temporary directory
        let uniqueFilename = UUID().uuidString + ".jpg"
        let tempDirectoryURL = FileManager.default.temporaryDirectory
        let fileURL = tempDirectoryURL.appendingPathComponent(uniqueFilename)
        
        //Write the data to disk
        try data.write(to: fileURL, options: .atomic)
        
        //Initialize and return the CKAsset pointing to the local file
        return CKAsset(fileURL: fileURL)
    }
}

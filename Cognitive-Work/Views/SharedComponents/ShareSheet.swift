//
//  ShareSheet.swift
//  Cognitive-Work
//
//  Created by Carolina Sun on 25/08/26.
//

import SwiftUI
import UIKit

/// The iOS share sheet ("Compartilhar"), for using from SwiftUI.
struct ShareSheet: UIViewControllerRepresentable {
    /// What is being shared.
    let items: [Any]
    
    /// Shares a link (for example, the house invite).
    init(url: URL) {
        self.items = [url]
    }
    
    /// Shares plain text, e.g. a Pix "copia e cola" code.
    init(text: String) {
        self.items = [text]
    }
    
    /// Creates the system share sheet.
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    /// Nothing to update: the items are fixed.
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}


#Preview {
    ShareSheet(url: URL(string: "https://www.icloud.com/share/exemplo")!)
}

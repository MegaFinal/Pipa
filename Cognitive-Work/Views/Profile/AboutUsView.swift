//
//  AboutUsView.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 21/10/26.
//

import SwiftUI

/// "Sobre nós" screen, opened from the profile tab. 
struct AboutUsView: View {
    var body: some View {
        Text("Em breve")
            .foregroundStyle(.secondary)
            .navigationTitle("Sobre nós")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { AboutUsView() }
}

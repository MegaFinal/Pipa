//
//  DisclosureButton.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 21/10/26.
//

import SwiftUI

/// A settings row that runs an action (open a sheet, show a confirmation) and looks like a
/// `NavigationLink`: black title, optional value on the right and a chevron.
///
/// Use it inside a `List`.
struct DisclosureButton: View {
    /// The row's title.
    let title: LocalizedStringKey
    /// The current value, shown in gray before the chevron.
    let value: String?
    /// Runs when the row is tapped.
    let action: () -> Void
    
    init(_ title: LocalizedStringKey, value: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.value = value
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let value {
                    Text(value).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        // A Button in a List draws its label in the accent color; this keeps the text black.
        .tint(.primary)
    }
}

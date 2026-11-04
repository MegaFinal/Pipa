//
//  ChoreTagPicker.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 28/08/26.
//

import SwiftUI
import CloudKit

/// A tag that opens a menu to change one of the chore's attributes (priority, frequency or duration).
struct ChoreTagPicker: View {
    
    /// The chore being edited.
    @Binding var chore: ChoreDTO
    
    /// Which attribute this picker changes.
    var type: TagPickerType
    
    /// The house's rooms. Not used by the current tag types.
    var availableRooms: [RoomModel] = []
    
    /// The chore's room. Not used by the current tag types.
    @State private var currentRoom: RoomModel? = nil
    
    var body: some View {
        Menu {
            // MARK: - Menu options for the chosen attribute
            switch type {
            case .priority:
                Picker("Prioridade", selection: $chore.priorityTag) {
                    ForEach(PriorityTag.allCases.filter { $0 != .undefined }, id: \.self) { tag in
                        ColorIconTagLabel(title: tag.displayName, color: tag.color)
                            .tag(tag)
                    }
                }
                
            case .frequency:
                Picker("Frequência", selection: $chore.frequency) {
                    ForEach(Recurrence.allCases.filter { $0 != .undefined }, id: \.self) { freq in
                        ColorIconTagLabel(title: freq.displayName, color: freq.color)
                            .tag(freq)
                    }
                }
                
            case .duration:
                Picker("Duração", selection: durationTierBinding) {
                    ForEach(ChoreDurationTier.allCases.filter { $0 != .undefined }, id: \.self) { tier in
                        ColorIconTagLabel(title: tier.displayText, color: tier.color)
                            .tag(tier)
                    }
                }
            }
        } label: {
            // MARK: - Label: the current value as a tag, with a chevron
            HStack {
                CapsuleTag(
                    tagName: type.labelName(for: chore, currentRoom: currentRoom),
                    tagColor: type.labelColor(for: chore, currentRoom: currentRoom),
                    textColor: type.labelTextColor(for: chore),
                    horizontalPadding: 10.0,
                    verticalPadding: 1.5
                )
                
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundColor(.black)
                    .imageScale(.small)
            }
            .fixedSize()
        }
        // MARK: - Accessibility and room sync
        // "Prioridade, média, pop-up button"
        .voiceOverLabel(accessibilityTitle)
        .voiceOverValue(type.labelName(for: chore, currentRoom: currentRoom))
        // Voice Control: the title shown beside the menu, then the value shown on the tag.
        .voiceControlNames([accessibilityTitle, type.labelName(for: chore, currentRoom: currentRoom)])
        .id(type.labelName(for: chore, currentRoom: currentRoom))
        .onChange(of: currentRoom) { _, newRoom in
            if let recordID = newRoom?.recordID {
                chore.roomReference = CKRecord.Reference(recordID: recordID, action: .none)
            } else {
                chore.room = nil
            }
        }
    }
    
    /// What this picker edits, spoken before its current value.
    private var accessibilityTitle: String {
        switch type {
        case .priority: return L10n.tr("Prioridade")
        case .frequency: return L10n.tr("Frequência")
        case .duration: return L10n.tr("Duração")
        }
    }
    
    /// Reads and writes the chore's duration as a duration group (the menu offers groups, not minutes).
    private var durationTierBinding: Binding<ChoreDurationTier> {
        Binding(
            get: { ChoreDurationTier.from(minutes: chore.duration) },
            set: { newTier in chore.duration = newTier.minutes }
        )
    }
}

/// A UI label paired with a custom-rendered colored circular icon.
///
/// Used inside the picker menus to represent tagged properties visually.
private struct ColorIconTagLabel: View {
    
    /// The string to be displayed next to the icon.
    let title: String
    
    /// The background color for the circular icon shape.
    let color: Color
    
    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(uiImage: .coloredCircle(color: color))
                .renderingMode(.original)
        }
    }
}

extension UIImage {
    /// Dynamically constructs an image rendering a colored circle for icon substitution.
    static func coloredCircle(color: Color) -> UIImage {
        let uiColor = UIColor(color)
        let size = CGSize(width: 24, height: 24)
        
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        uiColor.setFill()
        let rect = CGRect(x: 5, y: 5, width: 14, height: 14)
        UIBezierPath(ovalIn: rect).fill()
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image ?? UIImage()
    }
}

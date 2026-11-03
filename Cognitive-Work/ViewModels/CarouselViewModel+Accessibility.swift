//
//  CarouselViewModel+Accessibility.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 09/10/26.
//

import SwiftUI
import CloudKit

extension CarouselViewModel {

    // MARK: - Responsible users

    /// Who is responsible for `chore` on this occurrence. Mirrors the avatars shown on the
    /// list card and the details card: the occurrence's own users first, then the chore's
    /// rotation list, then its current responsible.
    func accessibilityResponsibleUsers(for chore: ChoreModel, assignment: RecurrentAssignmentModel?) -> [UserModel] {
        let target = assignment ?? getAssignments(for: chore, on: nextDate(for: chore)).first

        if let refs = target?.userReferences {
            let ids = Set(refs.map(\.recordID))
            guard !ids.isEmpty else { return [] }
            return userModels.filter { $0.recordID.map { ids.contains($0) } ?? false }
        }

        var ids = Set<CKRecord.ID>()
        if let refs = chore.allResponsibleUsersReference, !refs.isEmpty {
            ids.formUnion(refs.map(\.recordID))
        } else if let currentID = chore.currentResponsibleReference?.recordID {
            ids.insert(currentID)
        }
        guard !ids.isEmpty else { return [] }
        return userModels.filter { $0.recordID.map { ids.contains($0) } ?? false }
    }

    /// "Responsável: Ana", "Responsáveis: Ana e Bia" or "Sem responsável".
    func accessibilityResponsibleText(for users: [UserModel]) -> String {
        let names = users.map(\.name).filter { !$0.isEmpty }
        switch names.count {
        case 0:
            return L10n.tr("Sem responsável")
        case 1:
            return L10n.tr("Responsável: \(names[0])")
        default:
            return L10n.tr("Responsáveis: \(names.formatted(.list(type: .and).locale(L10n.locale)))")
        }
    }

    // MARK: - Chore summary

    /// "Prioridade média, duração curta, frequência semanal".
    func accessibilityTagsText(for chore: ChoreModel) -> String {
        [
            L10n.tr("Frequência \(chore.frequency.displayName)"),
            L10n.tr("Prioridade \(chore.priorityTag.displayName)"),
            L10n.tr("Duração \(ChoreDurationTier.from(minutes: chore.duration).displayText)")
        ].joined(separator: ", ")
    }

    /// The room's display name, or "Sem cômodo".
    func accessibilityRoomName(for chore: ChoreModel) -> String {
        getRoom(for: chore)?.name.localizedDefault ?? L10n.tr("Sem cômodo")
    }

    /// A long, spoken-friendly date: "sexta-feira, 25 de setembro".
    static func accessibilityDateText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(L10n.locale))
    }

    /// One sentence describing a chore card: name, room, status, responsible people, tags and,
    /// optionally, its date.
    func accessibilitySummary(
        for chore: ChoreModel,
        assignment: RecurrentAssignmentModel?,
        includeDate: Bool = false
    ) -> String {
        var parts: [String] = [
            chore.localizedName,
            accessibilityRoomName(for: chore),
            isDone(for: chore, assignment: assignment) ? L10n.tr("Concluída") : L10n.tr("Pendente"),
            accessibilityResponsibleText(for: accessibilityResponsibleUsers(for: chore, assignment: assignment)),
            accessibilityTagsText(for: chore)
        ]

        if includeDate, let day = assignment?.day ?? nextDate(for: chore) {
            parts.append(Self.accessibilityDateText(day))
        }

        return parts.joined(separator: ", ")
    }

    // MARK: - Carousel navigation

    /// The chore at the carousel's centre, if any.
    var accessibilityActiveChore: ChoreModel? {
        visibleChores.indices.contains(activeIndex) ? visibleChores[activeIndex] : nil
    }

    /// Spoken value of the carousel: the centred chore plus its position ("2 de 5").
    var accessibilityCarouselValue: String {
        guard let chore = accessibilityActiveChore else { return "" }
        let summary = accessibilitySummary(
            for: chore,
            assignment: getAssignmentsForActiveContext(for: chore).first
        )
        let position = L10n.tr("\(activeIndex + 1) de \(visibleChores.count)")
        return "\(summary). \(position)"
    }

    // MARK: - Voice Control

    /// Names Voice Control accepts for the closed carousel: the centred chore's visible name
    /// first ("Toque em Lavar louça" opens it), then the carousel's own name.
    var voiceControlCarouselInputLabels: [String] {
        var labels: [String] = []
        if let chore = accessibilityActiveChore, !chore.localizedName.isEmpty {
            labels.append(chore.localizedName)
        }
        labels.append(L10n.tr("Tarefas do dia"))
        labels.append(L10n.tr("Carrossel"))
        return labels
    }

    /// Short names for a chore card: the name shown on the card first.
    func voiceControlInputLabels(for chore: ChoreModel) -> [String] {
        let name = chore.localizedName
        return name.isEmpty ? [L10n.tr("Tarefa")] : [name, L10n.tr("Tarefa \(name)")]
    }

    /// Moves the carousel one card forward (`step` = 1) or back (`step` = -1), the same way a
    /// swipe does, so VoiceOver users can browse it with the adjustable gesture.
    func accessibilityMoveCarousel(by step: Int) {
        guard !visibleChores.isEmpty else { return }
        clearFocus()

        let count = visibleChores.count
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            draggingItem = (snappedItem + Double(step))
                .rounded()
                .remainder(dividingBy: Double(count))
            snappedItem = draggingItem

            let rounded = Int(draggingItem)
            activeIndex = rounded >= 0 ? rounded : count + rounded
        }
    }
}

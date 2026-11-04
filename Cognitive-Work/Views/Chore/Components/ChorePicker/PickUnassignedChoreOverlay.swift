//
//  PickUnassignedChoreOverlay.swift
//  Cognitive-Work
//
//  Created by Dayô Araújo on 26/10/26.
//

import SwiftUI

/// The "pick the day" popup over a dark background, shown while a chore is waiting for its date.
struct PickUnassignedChoreOverlay: View {
    @Bindable var carouselViewModel: CarouselViewModel
    
    var body: some View {
        if let item = carouselViewModel.itemAwaitingDate {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { }
                    .transition(.opacity)
                    .accessibilityHidden(true)
                
                PickUnassignedChoreCard(item: item, carouselViewModel: carouselViewModel)
                    .transition(.scale)
            }
        }
    }
}

//
//  StringCapitalizationTests.swift
//  Cognitive-WorkTests
//
//  Created by Dayô Araújo on 06/11/26.
//

import Testing
import Foundation
@testable import Cognitive_Work

/// Names the AI writes for the shopping list start with a capital letter, like typed ones.
struct StringCapitalizationTests {

    private let portuguese = Locale(identifier: "pt_BR")

    @Test func capitalizesOnlyTheFirstLetter() {
        #expect("arroz integral".capitalizingFirstLetter(locale: portuguese) == "Arroz integral")
        #expect("água com gás".capitalizingFirstLetter(locale: portuguese) == "Água com gás")
        // The rest stays as written.
        #expect("leite UHT".capitalizingFirstLetter(locale: portuguese) == "Leite UHT")
        #expect("Café".capitalizingFirstLetter(locale: portuguese) == "Café")
    }

    @Test func leavesTextWithoutCaseAlone() {
        #expect("".capitalizingFirstLetter(locale: portuguese) == "")
        #expect("咖啡".capitalizingFirstLetter(locale: portuguese) == "咖啡")
        #expect("2 litros de leite".capitalizingFirstLetter(locale: portuguese) == "2 litros de leite")
    }
}

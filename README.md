<div align="center">

<img src="Cognitive-Work/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="130" alt="Pipa app icon" style="border-radius: 28px;"/>

# Pipa: Para Partilhar

### Share the house, not the stress. 🪁

Pipa is a native iOS app for young people who share a home. It splits household chores
fairly and automatically, based on how much free time each person has and how heavy each
task is, and turns the invisible mental load of running a house into cards everyone can see.

<br/>

[![Download on the App Store](https://img.shields.io/badge/Download_on_the-App_Store-0D96F6?style=for-the-badge&logo=apple&logoColor=white)](https://apps.apple.com/br/app/pipa-para-partilhar/id6799178383)
[![Platform](https://img.shields.io/badge/iOS-26.2+-000000?style=for-the-badge&logo=apple&logoColor=white)](https://www.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5-FA7343?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-0052CC?style=for-the-badge&logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![CloudKit](https://img.shields.io/badge/CloudKit-3693F3?style=for-the-badge&logo=icloud&logoColor=white)](https://developer.apple.com/icloud/cloudkit/)
[![Apple Intelligence](https://img.shields.io/badge/Apple_Intelligence-000000?style=for-the-badge&logo=apple&logoColor=white)](https://developer.apple.com/documentation/foundationmodels)

</div>

---

## 📑 Table of Contents

- [About](#-about)
- [Screenshots](#-screenshots)
- [Features](#-features)
- [How It Works](#-how-it-works)
- [Tech Stack](#-tech-stack)
- [Project Structure](#-project-structure)
- [Getting Started](#-getting-started)
- [Authors](#-authors)

---

## 📖 About

Living with roommates usually means one person ends up remembering everything: whose turn
it is to take out the trash, what's missing from the fridge, who still owes money for the
groceries. **Pipa** (*"para partilhar"*, "for sharing") takes that weight off a single person.

Everyone in the house tells Pipa how much free time they have during the week. Pipa then
builds a **fortnightly division** of chores that respects each person's availability and
the effort of each task, rotates recurring chores, and shows the result as interactive
cards. At the end of every cycle, the house runs a short **retrospective**, earns coins for
the work done, and can spend them on coupons that skip a chore in the next division.

Pipa is **live on the App Store**: [download it here](https://apps.apple.com/br/app/pipa-para-partilhar/id6799178383).

---

## 📸 Screenshots

<div align="center">

<img src="https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/5f/ae/b6/5faeb6de-df69-f39d-c59c-557187994bc8/1.png/460x1022bb.png" width="16%" alt="Pipa screenshot 1"/>
<img src="https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/58/ed/97/58ed97f9-80fb-8b84-2eaa-eefc3cf9a042/2.png/460x1022bb.png" width="16%" alt="Pipa screenshot 2"/>
<img src="https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/14/0f/62/140f62eb-28a9-4ba5-ca93-5bcc5ba9bcce/5.png/460x1022bb.png" width="16%" alt="Pipa screenshot 3"/>
<img src="https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/08/76/0f/08760f28-4a78-928f-4aa8-2b496f2d0df0/6.png/460x1022bb.png" width="16%" alt="Pipa screenshot 4"/>
<img src="https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/c6/1e/2d/c61e2d05-335a-0e80-b6a5-970b76784865/7.png/460x1022bb.png" width="16%" alt="Pipa screenshot 5"/>
<img src="https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/5a/c7/f5/5ac7f593-001e-57f1-bb21-2ac9160dd99a/8.png/460x1022bb.png" width="16%" alt="Pipa screenshot 6"/>

</div>

---

## 🚀 Features

- **🏠 Shared houses** — create a house, set up its rooms, and invite roommates through iCloud sharing; everyone sees the same data in real time.
- **⚖️ Fair, automatic division** — a scheduling algorithm distributes chores over a two-week cycle based on each member's weekly free time and each chore's duration, and rotates recurring chores between people.
- **🃏 Chore cards** — your tasks for the day as an interactive carousel; swipe to mark a chore as done.
- **🔁 Retrospectives** — when a cycle ends, the house looks back on how it went before starting the next division.
- **🪙 Points, ranks and coupons** — completed chores earn points; at the end of the cycle the rank pays out coins, which buy coupons that exempt you from a chore in the next division.
- **🛒 Shared shopping list** — build the house's list together, track who's buying what in the *Pendências* tab, and see who owes whom.
- **✨ Apple Intelligence** — on-device suggestions for the shopping list (missing complements and duplicate detection) with the Foundation Models framework, plus voice input to add items by speaking.
- **📅 Calendar sync** — your pending chores appear in a dedicated *Pipa* calendar in the Apple Calendar app.
- **📟 E-paper companion** — an ESP32 device with an e-paper screen shows the day's chores and the fortnight chart, paired with the app over the local network.
- **🌍 Accessible and bilingual** — VoiceOver support across the main screens, haptics, and full Portuguese and English localization.

---

## ⚙️ How It Works

1. **Create or join a house** — the creator sets up the rooms and invites roommates with an iCloud share link.
2. **Tell Pipa your free time** — each member fills in their weekly availability.
3. **Get the division** — once everyone has answered, the algorithm assigns every chore to a day and a person for the next two weeks, balancing the load against each person's capacity.
4. **Do the chores** — swipe the cards to complete them and earn points.
5. **Close the cycle** — run the retrospective, collect your coins, buy coupons, and start a new division.

Under the hood, all house data lives in a **shared CloudKit database** (`CKShare`). Points,
coin payouts and coupon purchases go through an `AtomicRecordStore` that always applies changes
to the server's current value and retries on conflicts, so two roommates acting at the same
time never overwrite each other. Background refresh and silent CloudKit pushes keep the
e-paper device up to date.

---

## 🛠️ Tech Stack

| Area | Tech |
|------|------|
| UI | SwiftUI · UIKit · Swift Charts |
| Persistence & sync | CloudKit (shared database, `CKShare`, subscriptions) |
| On-device AI | Foundation Models (Apple Intelligence) · Speech |
| System integrations | EventKit · UserNotifications · BackgroundTasks · PhotosUI |
| Hardware | ESP32 + e-paper display over HTTP on the local network |
| Accessibility | VoiceOver · Haptics · String Catalogs (pt-BR / en) |
| Testing | Swift Testing · XCTest (200+ tests) |
| Architecture | MVVM with protocol-based services |

---

## 📂 Project Structure

```
Cognitive-Work/
├── App/                  # App entry, AppDelegate and SceneDelegate (CloudKit share acceptance)
├── Models/               # House, Room, Chore, User, assignments, shopping list, hardware and AI models
├── ViewModels/           # One view model per screen (+ Accessibility extensions)
├── Views/                # Onboarding, Dashboard, Chores, Algorithm, Retrospective, Profile, Hardware…
├── Manager/              # CloudKit, gamification, Apple Intelligence, calendar, hardware, scores
├── Utilities/            # Scheduling algorithm, protocols, extensions, accessibility helpers
├── Enums/                # Recurrence, priorities, tiers, rooms, errors…
└── Resources/            # Fonts and assets
Cognitive-WorkTests/      # Unit tests (algorithm, models, view models, gamification, CloudKit)
Cognitive-WorkUITests/    # UI tests
```

---

## 🎯 Getting Started

### Requirements

- Xcode 26+
- iOS 26.2+
- An Apple Developer account (CloudKit and iCloud sharing need real capabilities)
- An Apple Intelligence–capable device for the shopping list suggestions

### Run

```bash
git clone https://github.com/MegaFinal/Cognitive-Work.git
cd Cognitive-Work
open Cognitive-Work.xcodeproj
```

Then set your own **Signing Team** and **Bundle Identifier**, and point the CloudKit
container to one your team owns. Sharing a house is best tested with **two iCloud accounts
on two devices**.

---

## 👥 Authors

Built at the **Apple Developer Academy | Mackenzie**.

<table width="100%">
  <tr>
    <td align="center" width="16%">
      <a href="https://github.com/Anshushu000"><img src="https://github.com/Anshushu000.png" width="80" alt="Anshu Li"/></a>
      <br/><sub><b>Anshu Li</b></sub><br/>
      <a href="https://github.com/Anshushu000"><img src="https://skillicons.dev/icons?i=github" alt="GitHub"/></a>
      <a href="https://www.linkedin.com/in/anshu-li/"><img src="https://skillicons.dev/icons?i=linkedin" alt="LinkedIn"/></a>
    </td>
    <td align="center" width="16%">
      <a href="https://github.com/camilatoniato"><img src="https://github.com/camilatoniato.png" width="80" alt="Camila Toniato"/></a>
      <br/><sub><b>Camila Toniato</b></sub><br/>
      <a href="https://github.com/camilatoniato"><img src="https://skillicons.dev/icons?i=github" alt="GitHub"/></a>
      <a href="https://www.linkedin.com/in/camilatoniato/"><img src="https://skillicons.dev/icons?i=linkedin" alt="LinkedIn"/></a>
    </td>
    <td align="center" width="16%">
      <a href="https://github.com/carolssun"><img src="https://github.com/carolssun.png" width="80" alt="Carolina Sun"/></a>
      <br/><sub><b>Carolina Sun</b></sub><br/>
      <a href="https://github.com/carolssun"><img src="https://skillicons.dev/icons?i=github" alt="GitHub"/></a>
      <a href="https://www.linkedin.com/in/carolina-sun/"><img src="https://skillicons.dev/icons?i=linkedin" alt="LinkedIn"/></a>
    </td>
    <td align="center" width="16%">
      <a href="https://github.com/dayoleal"><img src="https://github.com/dayoleal.png" width="80" alt="Dayô Araújo"/></a>
      <br/><sub><b>Dayô Araújo</b></sub><br/>
      <a href="https://github.com/dayoleal"><img src="https://skillicons.dev/icons?i=github" alt="GitHub"/></a>
      <a href="https://www.linkedin.com/in/dayo-araujo/"><img src="https://skillicons.dev/icons?i=linkedin" alt="LinkedIn"/></a>
    </td>
    <td align="center" width="16%">
      <a href="https://github.com/hissapinto"><img src="https://github.com/hissapinto.png" width="80" alt="Isabela Hissa"/></a>
      <br/><sub><b>Isabela Hissa</b></sub><br/>
      <a href="https://github.com/hissapinto"><img src="https://skillicons.dev/icons?i=github" alt="GitHub"/></a>
      <a href="https://www.linkedin.com/in/hissapinto/"><img src="https://skillicons.dev/icons?i=linkedin" alt="LinkedIn"/></a>
    </td>
    <td align="center" width="16%">
      <a href="https://github.com/JonasFNMelo"><img src="https://github.com/JonasFNMelo.png" width="80" alt="Jonas Melo"/></a>
      <br/><sub><b>Jonas Melo</b></sub><br/>
      <a href="https://github.com/JonasFNMelo"><img src="https://skillicons.dev/icons?i=github" alt="GitHub"/></a>
      <a href="https://www.linkedin.com/in/jonas-melo-/"><img src="https://skillicons.dev/icons?i=linkedin" alt="LinkedIn"/></a>
    </td>
  </tr>
</table>

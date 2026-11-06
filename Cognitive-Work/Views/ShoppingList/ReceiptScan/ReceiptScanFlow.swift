//
//  ReceiptScanFlow.swift
//  Cognitive-Work
//
//  Created by anshu Li on 05/11/26.
//

import SwiftUI
import PhotosUI

// MARK: - Starting a scan

/// Where a receipt's photos come from.
enum ReceiptSource {
    /// The document scanner.
    case camera
    /// Photos already in the library.
    case library
}

/// The menu that starts a receipt scan: the camera (where there is a document scanner) or
/// photos already taken. What happens next is ``View/receiptScan(request:shopList:)``.
struct ReceiptScanMenu<MenuLabel: View>: View {
    /// Called with the source the person picked.
    let onSelect: (ReceiptSource) -> Void
    @ViewBuilder let label: () -> MenuLabel

    var body: some View {
        Menu {
            // The simulator has no document scanner.
            if ReceiptScannerView.isSupported {
                Button {
                    HapticsManager.selection()
                    onSelect(.camera)
                } label: {
                    Label("Escanear com a câmera", systemImage: "camera")
                }
            }
            Button {
                HapticsManager.selection()
                onSelect(.library)
            } label: {
                Label("Escolher da galeria", systemImage: "photo.on.rectangle")
            }
        } label: {
            label()
        }
        .voiceOverLabel(L10n.tr("Escanear nota"))
        .voiceControlNames([L10n.tr("Escanear nota"), L10n.tr("Escanear")])
    }
}

// MARK: - The scan

/// Everything after the menu: the scanner or the photo picker, then the review of the products
/// read (``ReceiptReviewView``), which links them to the shopping list. "Escanear de novo" goes
/// back to the same source. A save error shows once the review is gone.
private struct ReceiptScanFlow: ViewModifier {
    /// Set by the menu; the flow starts and clears it.
    @Binding var request: ReceiptSource?
    /// The list the receipt goes to.
    let shopList: ShopListViewModel

    /// Opens the document scanner.
    @State private var isScanning = false
    /// Opens the photo picker: chosen in the menu, or where the scanner doesn't exist (the
    /// simulator).
    @State private var isPickingPhotos = false
    /// Where the last receipt came from, so "Escanear de novo" goes back there.
    @State private var source: ReceiptSource = .camera
    @State private var photoItems: [PhotosPickerItem] = []
    /// The receipt being reviewed, or `nil`.
    @State private var scannedReceipt: ScannedReceipt?
    /// Set by "Escanear de novo": the scanner opens once the review sheet is gone.
    @State private var scanAgainAfterReview = false
    /// Shows the list's error after the review closed with one.
    @State private var isShowingError = false

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, newValue in
                guard let newValue else { return }
                request = nil
                start(from: newValue)
            }
            .fullScreenCover(isPresented: $isScanning) {
                ReceiptScannerView(
                    onFinish: { pages in
                        isScanning = false
                        showReview(of: pages)
                    },
                    onCancel: { isScanning = false }
                )
                .ignoresSafeArea()
            }
            .photosPicker(
                isPresented: $isPickingPhotos,
                selection: $photoItems,
                maxSelectionCount: 5,
                matching: .images
            )
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    var pages: [UIImage] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                            pages.append(image)
                        }
                    }
                    photoItems = []
                    showReview(of: pages)
                }
            }
            .sheet(item: $scannedReceipt, onDismiss: {
                if scanAgainAfterReview {
                    scanAgainAfterReview = false
                    start(from: source)
                } else if shopList.errorMessage != nil {
                    isShowingError = true
                }
            }) { receipt in
                ReceiptReviewView(pages: receipt.pages, shopList: shopList) {
                    scanAgainAfterReview = true
                    scannedReceipt = nil
                }
            }
            .alert("Não foi possível concluir", isPresented: $isShowingError) {
                Button("OK", role: .cancel) { shopList.clearError() }
            } message: {
                Text(shopList.errorMessage ?? "")
            }
    }

    /// Opens the scanner or the photo picker (also where there is no scanner).
    private func start(from newSource: ReceiptSource) {
        source = newSource
        if newSource == .camera, ReceiptScannerView.isSupported {
            isScanning = true
        } else {
            isPickingPhotos = true
        }
    }

    /// Opens the review of `pages` once the scanner has finished closing (presenting a sheet
    /// while a full-screen cover is still going away is dropped by SwiftUI).
    private func showReview(of pages: [UIImage]) {
        guard !pages.isEmpty else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            scannedReceipt = ScannedReceipt(pages: pages)
        }
    }
}

/// The pages of one scanned receipt, for `.sheet(item:)`.
private struct ScannedReceipt: Identifiable {
    let id = UUID()
    let pages: [UIImage]
}

extension View {
    /// Runs a receipt scan into `shopList` whenever `request` is set (by a
    /// ``ReceiptScanMenu``).
    func receiptScan(request: Binding<ReceiptSource?>, shopList: ShopListViewModel) -> some View {
        modifier(ReceiptScanFlow(request: request, shopList: shopList))
    }
}

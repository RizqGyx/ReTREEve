//  PhotoImportView.swift
//  Screen: read a page from a photo the reader already has.
//
//  ── WHY THIS EXISTS ALONGSIDE THE SCANNER ──────────────────────────────────
//
//  The scanner and this screen are peers, not a feature and its fallback. They
//  end in exactly the same place — a `CapturedPage`, read by the same recognizer,
//  handed to the same selection screen — so everything downstream, the marked
//  passage detector included, cannot tell them apart.
//
//  Three things it is good for, in order of how often they will matter:
//
//    1. The page was photographed hours ago, in better light, without the app.
//    2. The camera is unavailable, restricted, or misbehaving. Acquisition then
//       has a second route that shares none of the camera's machinery.
//    3. Testing. A detector can be pointed at a known photo and give a
//       repeatable answer, which a live camera can never do.
//
//  `PHPickerViewController` runs out of process and reads only what the reader
//  picks, so this screen needs no photo library permission and never sees the
//  rest of the library.

import SwiftUI
import PhotosUI
import UIKit

struct PhotoImportView: View {
    /// Called once a photo has been chosen AND read. Same contract as the scanner.
    var onPageCaptured: (CapturedPage) -> Void
    var onCancel: () -> Void

    private let recognizer: any TextRecognizing = VisionTextRecognizer()

    /// Named states rather than a pile of booleans, so "picked but unreadable"
    /// cannot be confused with "still picking".
    private enum Stage: Equatable {
        case picking
        case reading
        case failed(String)
    }

    @State private var stage: Stage = .picking

    var body: some View {
        Group {
            switch stage {
            case .picking:
                PhotoPickerRepresentable(
                    onPicked: { image in
                        guard let image else { onCancel(); return }
                        Task { await read(image) }
                    }
                )
                .ignoresSafeArea()

            case .reading:
                status {
                    ProgressView()
                    Text("Reading the page…")
                        .font(.grimoire(.subhead))
                        .foregroundStyle(Grimoire.textSecondary)
                }

            case .failed(let message):
                status {
                    Image("Squirrel").resizable().scaledToFit().frame(width: 88).accessibilityHidden(true)
                    Text(message)
                        .font(.grimoire(.subhead))
                        .foregroundStyle(Grimoire.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Pick Another Photo") { stage = .picking }
                        .buttonStyle(GrimoirePrimaryButton())
                    Button("Cancel", action: onCancel)
                        .font(.grimoire(.subhead))
                        .foregroundStyle(Grimoire.textSecondary)
                }
            }
        }
        .background(Grimoire.background)
    }

    private func status<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 14) {
            content()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Grimoire.background)
    }

    /// The same recognizer the scanner uses, on an image that arrived by a
    /// different route. Failure is a named message and another try, never a
    /// dead end.
    private func read(_ image: UIImage) async {
        stage = .reading
        do {
            onPageCaptured(try await recognizer.recognizePage(in: image))
        } catch let error as TextRecognitionError {
            stage = .failed([error.errorDescription, error.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " "))
        } catch {
            stage = .failed("That photo couldn't be read. Try another one.")
        }
    }
}

/// The system photo picker, which runs out of process and hands back one image.
/// `nil` means the reader cancelled — an outcome, not an error.
private struct PhotoPickerRepresentable: UIViewControllerRepresentable {
    let onPicked: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        // The full-size asset: the detector letterboxes to 832 itself, and a
        // picker-downscaled image would quietly change what the model sees.
        configuration.preferredAssetRepresentationMode = .current

        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPicked: (UIImage?) -> Void
        init(onPicked: @escaping (UIImage?) -> Void) { self.onPicked = onPicked }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else {
                onPicked(nil)
                return
            }

            provider.loadObject(ofClass: UIImage.self) { object, _ in
                let image = object as? UIImage
                Task { @MainActor in self.onPicked(image) }
            }
        }
    }
}

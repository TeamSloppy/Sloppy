import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI
import UniformTypeIdentifiers
#if canImport(PhotosUI) && !os(macOS)
import PhotosUI
#endif
#if os(iOS)
import UIKit
#endif

#if canImport(PhotosUI) && !os(macOS)
@MainActor
struct ChatPhotoAttachmentPickerModifier: ViewModifier {
    @State var viewModel: ChatScreenViewModel
    @State private var photoItems: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $viewModel.isPhotoPickerShown,
                selection: $photoItems,
                maxSelectionCount: 10,
                matching: .images
            )
            .onChange(of: photoItems) { _, items in
                Task { @MainActor in
                    let urls = await attachmentURLs(from: items)
                    viewModel.attachFileURLs(urls)
                    photoItems = []
                }
            }
    }

    private func attachmentURLs(from items: [PhotosPickerItem]) async -> [URL] {
        var urls: [URL] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                continue
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("sloppy-photo-\(UUID().uuidString)")
                .appendingPathExtension("jpg")
            guard (try? data.write(to: url, options: .atomic)) != nil else {
                continue
            }
            urls.append(url)
        }
        return urls
    }
}
#endif

#if os(iOS)
@MainActor
struct ChatCameraAttachmentPickerModifier: ViewModifier {
    let viewModel: ChatScreenViewModel

    func body(content: Content) -> some View {
        @Bindable var viewModel = viewModel
        return content.fullScreenCover(isPresented: $viewModel.isCameraPickerShown) {
            CameraAttachmentPicker { url in
                viewModel.isCameraPickerShown = false
                if let url {
                    viewModel.attachFileURLs([url])
                }
            }
            .ignoresSafeArea()
        }
    }
}

struct CameraAttachmentPicker: UIViewControllerRepresentable {
    let onComplete: @MainActor (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onComplete: @MainActor (URL?) -> Void

        init(onComplete: @escaping @MainActor (URL?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let url: URL? = {
                guard let image = info[.originalImage] as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.9) else {
                    return nil
                }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("sloppy-camera-\(UUID().uuidString)")
                    .appendingPathExtension("jpg")
                return (try? data.write(to: url, options: .atomic)) == nil ? nil : url
            }()
            Task { @MainActor in onComplete(url) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            Task { @MainActor in onComplete(nil) }
        }
    }
}
#endif

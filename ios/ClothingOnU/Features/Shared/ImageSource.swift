import PhotosUI
import SwiftUI
import UIKit

/// "Take photo / Choose from library" for any view. Camera permission is requested only
/// when the user taps "Take photo" (contextual ask), and the library uses PhotosPicker,
/// which needs no permission at all.
struct ImageSourceModifier: ViewModifier {
    @Binding var isPresented: Bool
    var title: String
    var allowsCamera: Bool
    var onImage: (UIImage) -> Void

    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var item: PhotosPickerItem?

    private var cameraAvailable: Bool { allowsCamera && UIImagePickerController.isSourceTypeAvailable(.camera) }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) {
                if cameraAvailable {
                    Button("Take photo") { showCamera = true }
                }
                Button(cameraAvailable ? "Choose from library" : "Choose a photo") { showLibrary = true }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $showLibrary, selection: $item, matching: .images, preferredItemEncoding: .current)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    showCamera = false
                    if let image { onImage(image) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: item) { _, newItem in
                guard let newItem else { return }
                item = nil
                Task {
                    // Load the original bytes and downsample with ImageIO: cheap on memory even for 48 MP photos.
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = ImageProcessing.downsampled(data, longEdge: 2400) {
                        onImage(image)
                    }
                }
            }
    }
}

extension View {
    func imageSource(isPresented: Binding<Bool>, title: String, allowsCamera: Bool = true, onImage: @escaping (UIImage) -> Void) -> some View {
        modifier(ImageSourceModifier(isPresented: isPresented, title: title, allowsCamera: allowsCamera, onImage: onImage))
    }
}

/// System camera. UIImagePickerController is still the most reliable full-screen capture UI
/// and includes the timer the user needs for solo full-body shots.
struct CameraPicker: UIViewControllerRepresentable {
    var onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}

import AVFoundation
import SwiftUI
import VisionKit

enum ScanSource {
    case camera, manual
}

/// Live camera scanning with a light, plus "snap a photo" and typed-UPC fallbacks.
struct ScannerPanel: View {
    var paused = false
    let onDetected: (String, ScanSource) -> Void

    @State private var manual = ""
    @State private var showCamera = false
    @State private var decoding = false
    @State private var torchOn = false
    @State private var noBarcodeAlert = false
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @FocusState private var manualFocused: Bool

    private var liveSupported: Bool {
        DataScannerViewController.isSupported
    }

    /// Two list sections: the camera, then the photo and typed-UPC fallbacks. Place it inside a List or Form.
    var body: some View {
        Group {
            Section {
                liveArea
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                Button {
                    showCamera = true
                } label: {
                    HStack {
                        Label("Scan from a Photo", systemImage: "camera")
                        if decoding { Spacer(); ProgressView() }
                    }
                }
                .disabled(decoding)
                HStack {
                    TextField("Type a UPC", text: $manual)
                        .keyboardType(.numberPad)
                        .focused($manualFocused)
                    Button("Look Up", action: submitManual)
                        .disabled(UPC.fromTyped(manual) == nil)
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(source: .camera) { image in
                Task { await decode(image) }
            }
            .ignoresSafeArea()
        }
        .alert("No Barcode Found", isPresented: $noBarcodeAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try again closer, with the barcode flat and in focus.")
        }
        .task {
            if cameraStatus == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
        .onChange(of: paused) { if paused { torchOn = false } }
    }

    @ViewBuilder private var liveArea: some View {
        if !liveSupported {
            ContentUnavailableView("Camera Scanning Unavailable", systemImage: "barcode.viewfinder",
                                   description: Text("Scan from a photo or type the UPC instead."))
        } else if cameraStatus == .denied || cameraStatus == .restricted {
            ContentUnavailableView {
                Label("Camera Access Is Off", systemImage: "camera.badge.ellipsis")
            } description: {
                Text("Allow camera access in Settings to scan barcodes.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        } else if cameraStatus == .authorized {
            ZStack(alignment: .bottomTrailing) {
                LiveScanner(paused: paused || manualFocused) { code in
                    onDetected(code, .camera)
                }
                if Torch.isAvailable {
                    Button {
                        torchOn.toggle()
                        Torch.set(torchOn)
                    } label: {
                        Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel(torchOn ? "Turn Light Off" : "Turn Light On")
                    .padding(12)
                }
            }
        } else {
            Color.black
        }
    }

    private func submitManual() {
        guard let code = UPC.fromTyped(manual) else { return }
        manual = ""
        manualFocused = false
        onDetected(code, .manual)
    }

    private func decode(_ image: UIImage) async {
        decoding = true
        defer { decoding = false }
        if let code = await Photos.barcode(in: image) {
            onDetected(code, .manual)
        } else {
            noBarcodeAlert = true
        }
    }
}

/// VisionKit's live barcode scanner.
struct LiveScanner: UIViewControllerRepresentable {
    var paused: Bool
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.upce, .ean13, .ean8, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        if paused {
            if vc.isScanning { vc.stopScanning() }
        } else if !vc.isScanning {
            try? vc.startScanning()
        }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
        Torch.set(false)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        private let haptic = UINotificationFeedbackGenerator()

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            report([item])
        }

        private func report(_ items: [RecognizedItem]) {
            for case let .barcode(barcode) in items {
                guard let payload = barcode.payloadStringValue else { continue }
                let code = barcode.observation.symbology == .upce ? UPC.expandUPCE(payload) : payload
                haptic.notificationOccurred(.success)
                onCode(code)
                return
            }
        }
    }
}

enum Torch {
    static var isAvailable: Bool {
        AVCaptureDevice.default(for: .video)?.hasTorch ?? false
    }

    static func set(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        guard (device.torchMode == .on) != on else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {}
    }
}

/// The system camera (or photo library when there's no camera, as in the Simulator).
struct ImagePicker: UIViewControllerRepresentable {
    enum Source { case camera, library }
    let source: Source
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = source == .camera && UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

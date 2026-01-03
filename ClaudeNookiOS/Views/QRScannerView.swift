//
//  QRScannerView.swift
//  ClaudeNookiOS
//
//  QR code scanner for easy pairing with Mac.
//

import AVFoundation
import SwiftUI

struct QRScannerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var connectionVM: ConnectionViewModel

    @State private var scannedCode: String?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isProcessing = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                // Camera preview
                QRScannerRepresentable(
                    scannedCode: $scannedCode,
                    onError: { error in
                        errorMessage = error
                        showError = true
                    }
                )
                .ignoresSafeArea()

                // Overlay with scanning frame
                VStack {
                    Spacer()

                    // Scanning frame
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.nookAccent, lineWidth: 3)
                        .frame(width: 250, height: 250)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.black.opacity(0.3))
                        )

                    Spacer()

                    // Instructions
                    VStack(spacing: 12) {
                        Text("Scan QR Code")
                            .font(.title2.bold())
                            .foregroundStyle(.white)

                        Text("Open Claude Nook on your Mac and click\n\"Show QR Code\" in Remote Access settings")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .padding(.bottom, 40)
                }

                // Processing overlay
                if isProcessing {
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)

                        Text("Connecting...")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .onChange(of: scannedCode) { newValue in
                if let code = newValue {
                    handleScannedCode(code)
                }
            }
            .alert("Scan Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func handleScannedCode(_ code: String) {
        guard !isProcessing else { return }

        // Parse the URL: claudenook://connect?host=...&port=...&token=...
        guard let url = URL(string: code),
              url.scheme == "claudenook",
              url.host == "connect",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            errorMessage = "Invalid QR code. Please scan a Claude Nook QR code."
            showError = true
            scannedCode = nil
            return
        }

        var host: String?
        var port: Int = 4851
        var token: String?

        for item in queryItems {
            switch item.name {
            case "host":
                host = item.value
            case "port":
                port = Int(item.value ?? "") ?? 4851
            case "token":
                token = item.value
            default:
                break
            }
        }

        guard let host = host, !host.isEmpty else {
            errorMessage = "QR code missing host address."
            showError = true
            scannedCode = nil
            return
        }

        guard let token = token, !token.isEmpty else {
            errorMessage = "QR code missing authentication token."
            showError = true
            scannedCode = nil
            return
        }

        // Connect with the scanned credentials
        isProcessing = true
        connectionVM.connectManually(host: host, port: port, token: token)

        // Dismiss after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            dismiss()
        }
    }
}

// MARK: - QR Scanner UIKit Bridge

struct QRScannerRepresentable: UIViewControllerRepresentable {
    @Binding var scannedCode: String?
    var onError: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, QRScannerViewControllerDelegate {
        let parent: QRScannerRepresentable

        init(_ parent: QRScannerRepresentable) {
            self.parent = parent
        }

        func didScanCode(_ code: String) {
            parent.scannedCode = code
        }

        func didFailWithError(_ error: String) {
            parent.onError(error)
        }
    }
}

// MARK: - QR Scanner View Controller

protocol QRScannerViewControllerDelegate: AnyObject {
    func didScanCode(_ code: String)
    func didFailWithError(_ error: String)
}

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: QRScannerViewControllerDelegate?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startScanning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScanning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func setupCamera() {
        let session = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            delegate?.didFailWithError("Camera not available")
            return
        }

        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            delegate?.didFailWithError("Could not access camera: \(error.localizedDescription)")
            return
        }

        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        } else {
            delegate?.didFailWithError("Could not add camera input")
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            delegate?.didFailWithError("Could not add metadata output")
            return
        }

        captureSession = session

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer
    }

    private func startScanning() {
        hasScanned = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    private func stopScanning() {
        captureSession?.stopRunning()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasScanned else { return }

        if let metadataObject = metadataObjects.first,
           let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
           let stringValue = readableObject.stringValue {

            hasScanned = true
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            delegate?.didScanCode(stringValue)
        }
    }
}

#Preview {
    QRScannerView()
        .environmentObject(ConnectionViewModel())
}

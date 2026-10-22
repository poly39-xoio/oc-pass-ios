import SwiftUI
import AVFoundation
import AudioToolbox

/// QR 掃描器(2026-10-22 修正)
/// - 明確請求相機權限,拒絕/無相機時給文字提示,不再是一片黑
/// - preview layer 在 viewDidLayoutSubviews 才設定 frame(原本在 viewDidLoad 取到 0x0 → 黑畫面)
/// - 右上「取消」可關閉;掃到就自動關
struct ScannerView: View {
    @Environment(\.dismiss) private var dismiss
    var onCode: (String) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScannerRepresentable(onCode: { code in
                onCode(code)
                dismiss()
            }, onCancel: { dismiss() })
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(16)
            }
        }
    }
}

struct ScannerRepresentable: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onCode = onCode
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerVC, context: Context) {}
}

final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private let hint = UILabel()
    private var configured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        hint.textColor = .white
        hint.font = .systemFont(ofSize: 15, weight: .medium)
        hint.numberOfLines = 0
        hint.textAlignment = .center
        hint.text = "正在開啟相機…"
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hint.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])

        requestCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    private func requestCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.configure() }
                    else { self?.show("沒有相機權限。請到 iPhone 設定 → OC Pass → 相機 開啟，或改用手動貼 token。") }
                }
            }
        default:
            show("沒有相機權限。請到 iPhone 設定 → OC Pass → 相機 開啟，或改用手動貼 token。")
        }
    }

    private func configure() {
        guard !configured else { return }
        configured = true

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            show("這台裝置沒有可用的相機。")
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            show("相機初始化失敗，請改用手動貼 token。")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = output.availableMetadataObjectTypes.contains(.qr) ? [.qr] : output.availableMetadataObjectTypes

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.frame = view.bounds
        layer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(layer, at: 0)
        preview = layer

        hint.text = "把 QR 對準鏡頭"

        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }

    private func show(_ text: String) {
        hint.text = text
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }
        AudioServicesPlaySystemSound(1057)
        if session.isRunning { session.stopRunning() }
        onCode?(value)
    }
}

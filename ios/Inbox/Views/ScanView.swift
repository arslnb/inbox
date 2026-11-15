import AVFoundation
import SwiftUI
import UIKit

// The camera reading QR codes. Its session starts and stops off the main thread; what it reads comes back on it.
@MainActor
final class Camera: NSObject, AVCaptureMetadataOutputObjectsDelegate {
  nonisolated(unsafe) let session = AVCaptureSession()  // set up on the main thread before it first runs, then only run and stopped on `queue`
  private let queue = DispatchQueue(label: "dev.inbox.ios.camera")
  var read: (String) -> Void = { _ in }
  var done = false  // a desk's link was read: every later frame is ignored, since each trade burns the code
  var last = ""

  // False when this device has no camera to read with.
  func start() -> Bool {
    if session.inputs.isEmpty {
      guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
        let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input)
      else { return false }
      let output = AVCaptureMetadataOutput()
      guard session.canAddOutput(output) else { return false }
      session.addInput(input)
      session.addOutput(output)
      guard output.availableMetadataObjectTypes.contains(.qr) else { return false }
      output.metadataObjectTypes = [.qr]
      output.setMetadataObjectsDelegate(self, queue: .main)
    }
    queue.async { [self] in if !session.isRunning { session.startRunning() } }
    return true
  }

  func stop() {
    queue.async { [self] in if session.isRunning { session.stopRunning() } }
  }

  nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
    guard let text = objects.lazy.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
    MainActor.assumeIsolated { read(text) }
  }
}

private struct Viewfinder: UIViewRepresentable {
  let session: AVCaptureSession

  final class Preview: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
  }

  func makeUIView(context: Context) -> Preview {
    let view = Preview()
    if let layer = view.layer as? AVCaptureVideoPreviewLayer {
      layer.session = session
      layer.videoGravity = .resizeAspectFill
    }
    return view
  }

  func updateUIView(_ view: Preview, context: Context) {}
}

// Scans the QR that Pair a device shows on the desk's computer, and hands its link to the connect screen. Anything
// else it reads goes nowhere.
struct ScanView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  let found: (String) -> Void
  @State private var camera = Camera()
  @State private var state = Seeing.asking
  @State private var wrong: String?

  private enum Seeing { case asking, looking, refused, none }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SheetHead(title: "Scan the code")
      switch state {
      case .refused:
        Text("Inbox isn't allowed to use the camera. Allow it in the phone's Settings → Inbox → Camera, or type the address and code.")
          .sans(15).foregroundStyle(Theme.ink2).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        Button("Open Settings") {
          if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
        .buttonStyle(PlainAct())
      case .none:
        Text(ScanView.noCamera).sans(15).foregroundStyle(Theme.ink2).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
      case .asking, .looking:
        Text("Point it at the QR that Pair a device shows on the desk's computer.")
          .sans(15).foregroundStyle(Theme.pencil).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        Viewfinder(session: camera.session)
          .aspectRatio(1, contentMode: .fit)
          .frame(maxWidth: .infinity)
          .background(Theme.wash)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.ruleStrong, lineWidth: 1))
          .accessibilityLabel("The camera's view")
        if let wrong {
          Text(wrong).sans(14).foregroundStyle(Theme.red).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Theme.pad)
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .presentationDetents(state == .refused || state == .none ? [.medium] : [.large])
    .presentationBackground(Theme.paper)
    .task {
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized: look()
      case .notDetermined:
        if await AVCaptureDevice.requestAccess(for: .video) { look() } else { state = .refused }
      default: state = .refused
      }
    }
    .onDisappear { camera.stop() }
  }

  static let noCamera = "This device has no camera: type or paste the link instead."

  private func look() {
    camera.read = read
    state = camera.start() ? .looking : .none
  }

  // The camera reads the same code many times a second: a desk's link is taken once, and a code that isn't one is
  // said once, until it reads a different one.
  private func read(_ text: String) {
    guard !camera.done, text != camera.last else { return }
    camera.last = text
    switch DeskAddress.scanned(text) {
    case .success(let link):
      camera.done = true
      camera.stop()
      dismiss()
      found(link)
    case .failure(let why):
      wrong = why.words
    }
  }
}

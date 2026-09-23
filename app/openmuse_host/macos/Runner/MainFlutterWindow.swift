import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    disableImpellerForDesktop()
    sanitizeWorkingDirectory()
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 1100, height: 650)
    if windowFrame.width < 1100 || windowFrame.height < 650 {
      let visible = self.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
      let targetWidth = min(1280, visible?.width ?? 1280)
      let targetHeight = min(760, visible?.height ?? 760)
      self.setContentSize(NSSize(width: targetWidth, height: targetHeight))
      self.center()
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    let workspaceChannel = FlutterMethodChannel(
      name: "com.openmuse.host/workspace",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    workspaceChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "chooseDirectory":
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        result(panel.runModal() == .OK ? panel.url?.path : nil)
      case "reveal":
        guard
          let values = call.arguments as? [String: Any],
          let path = values["path"] as? String
        else {
          result(FlutterError(code: "invalid-arguments", message: "Missing path", details: nil))
          return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}

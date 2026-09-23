import Cocoa
import FlutterMacOS

public final class OpenMuseNativeTextPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(OpenMuseNativeTextFactory(), withId: "com.openmuse.native-text")
  }
}

final class OpenMuseNativeTextFactory: NSObject, FlutterPlatformViewFactory {
  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.autohidesScrollers = true
    scroll.borderType = .noBorder

    let textView = NSTextView()
    textView.isRichText = false
    textView.isEditable = true
    textView.isSelectable = true
    textView.allowsUndo = true
    textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
    textView.textContainerInset = NSSize(width: 16, height: 16)
    if let values = args as? [String: Any], let text = values["text"] as? String {
      textView.string = text
    }
    scroll.documentView = textView
    return scroll
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

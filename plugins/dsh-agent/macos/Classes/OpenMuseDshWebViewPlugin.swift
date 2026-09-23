import Cocoa
import FlutterMacOS
import WebKit

public final class OpenMuseDshWebViewPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(DshWebViewFactory(messenger: registrar.messenger), withId: "com.openmuse.dsh/webview")
  }
}

final class DshWebViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .default()
    guard
      let values = args as? [String: Any],
      let raw = values["url"] as? String,
      let url = URL(string: raw),
      url.scheme == "http",
      url.host == "127.0.0.1" || url.host == "localhost",
      let port = url.port
    else {
      let webView = WKWebView(frame: .zero, configuration: configuration)
      webView.loadHTMLString("<p>Invalid DSH loopback URL</p>", baseURL: nil)
      return webView
    }
    let channel = FlutterMethodChannel(
      name: "com.openmuse.dsh/webview/\(viewId)",
      binaryMessenger: messenger
    )
    let handler = DshResourceMessageHandler(channel: channel, port: port)
    configuration.userContentController.add(handler, name: "MuseHostResource")
    configuration.userContentController.addUserScript(WKUserScript(
      source: "window.MuseHostResource = { postMessage: function(raw) { window.webkit.messageHandlers.MuseHostResource.postMessage(raw); } };",
      injectionTime: .atDocumentStart,
      forMainFrameOnly: true
    ))
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.setValue(false, forKey: "drawsBackground")
    channel.setMethodCallHandler { [weak webView] call, result in
      guard call.method == "reload" else {
        result(FlutterMethodNotImplemented)
        return
      }
      webView?.reload()
      result(nil)
    }
    webView.load(URLRequest(url: url))
    return webView
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class DshResourceMessageHandler: NSObject, WKScriptMessageHandler {
  private let channel: FlutterMethodChannel
  private let port: Int

  init(channel: FlutterMethodChannel, port: Int) {
    self.channel = channel
    self.port = port
  }

  func userContentController(_ userContentController: WKUserContentController,
                             didReceive message: WKScriptMessage) {
    let origin = message.frameInfo.securityOrigin
    guard message.frameInfo.isMainFrame,
          origin.`protocol` == "http",
          (origin.host == "127.0.0.1" || origin.host == "localhost"),
          origin.port == port,
          let payload = message.body as? String,
          payload.utf8.count <= 16_384 else { return }
    channel.invokeMethod("resourceOpen", arguments: payload)
  }
}

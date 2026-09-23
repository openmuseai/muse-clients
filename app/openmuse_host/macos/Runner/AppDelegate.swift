import Cocoa
import FlutterMacOS

/// Desktop `flutter run --no-enable-impeller` sets FLUTTER_ENGINE_SWITCH_* in
/// the process environment. `open .app` does not, and FLTEnableImpeller in
/// Info.plist is not read on macOS — Impeller then blanks the window
/// (WKWebView platform views / newer macOS). Apply the same switch here
/// before the engine starts.
func disableImpellerForDesktop() {
  setenv("FLUTTER_ENGINE_SWITCHES", "1", 1)
  setenv("FLUTTER_ENGINE_SWITCH_1", "enable-impeller=false", 1)
}

/// `open .app` starts with cwd `/`. Anything that lists Directory.current
/// then hangs on automounts / TCC-protected folders.
func sanitizeWorkingDirectory() {
  let cwd = FileManager.default.currentDirectoryPath
  if cwd == "/" {
    FileManager.default.changeCurrentDirectoryPath(
      FileManager.default.homeDirectoryForCurrentUser.path
    )
  }
}

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationWillFinishLaunching(_ notification: Notification) {
    disableImpellerForDesktop()
    sanitizeWorkingDirectory()
    super.applicationWillFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}


#ifndef FLUTTER_PLUGIN_OPENMUSE_NATIVE_TEXT_GATE_PLUGIN_H_
#define FLUTTER_PLUGIN_OPENMUSE_NATIVE_TEXT_GATE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

class OpenMuseNativeTextGatePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);
  explicit OpenMuseNativeTextGatePlugin(flutter::PluginRegistrarWindows* registrar);
  ~OpenMuseNativeTextGatePlugin() override;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND native_text_view_ = nullptr;
};

#endif

#include "openmuse_native_text_gate_plugin.h"

#include <algorithm>
#include <flutter/standard_method_codec.h>

void OpenMuseNativeTextGatePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<OpenMuseNativeTextGatePlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

OpenMuseNativeTextGatePlugin::OpenMuseNativeTextGatePlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "com.openmuse.native_text_gate/view",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

OpenMuseNativeTextGatePlugin::~OpenMuseNativeTextGatePlugin() {
  if (native_text_view_ != nullptr) DestroyWindow(native_text_view_);
}

void OpenMuseNativeTextGatePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "hide") {
    if (native_text_view_ != nullptr) ShowWindow(native_text_view_, SW_HIDE);
    result->Success();
    return;
  }
  if (call.method_name() != "show") {
    result->NotImplemented();
    return;
  }
  const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
  if (arguments == nullptr) {
    result->Error("invalid-arguments", "Expected a bounds map");
    return;
  }
  const auto number = [arguments](const char* key) -> double {
    const auto found = arguments->find(flutter::EncodableValue(key));
    if (found == arguments->end()) return 0.0;
    if (const auto* value = std::get_if<double>(&found->second)) return *value;
    if (const auto* value = std::get_if<int32_t>(&found->second)) return *value;
    if (const auto* value = std::get_if<int64_t>(&found->second)) {
      return static_cast<double>(*value);
    }
    return 0.0;
  };
  if (native_text_view_ == nullptr) {
    native_text_view_ = CreateWindowExW(
        WS_EX_CLIENTEDGE, L"EDIT",
        L"OpenMuse native HWND plugin.\r\n\r\nTest CJK IME, focus, selection, clipboard and resize.",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_VSCROLL | ES_LEFT |
            ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN,
        0, 0, 1, 1, registrar_->GetView()->GetNativeWindow(), nullptr,
        GetModuleHandle(nullptr), nullptr);
    SendMessage(native_text_view_, WM_SETFONT,
                reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
  }
  // Windows headers define min/max as macros, so std::max cannot be spelled
  // here; use explicit comparisons and keep a one-pixel minimum extent.
  const auto atLeastOne = [](double value) -> int {
    const auto rounded = static_cast<int>(value);
    return rounded < 1 ? 1 : rounded;
  };
  SetWindowPos(native_text_view_, HWND_TOP, static_cast<int>(number("x")),
               static_cast<int>(number("y")), atLeastOne(number("width")),
               atLeastOne(number("height")),
               SWP_SHOWWINDOW | SWP_NOACTIVATE);
  result->Success();
}

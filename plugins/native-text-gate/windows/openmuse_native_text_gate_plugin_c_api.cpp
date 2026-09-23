#include "include/openmuse_native_text_gate/openmuse_native_text_gate_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "openmuse_native_text_gate_plugin.h"

void OpenmuseNativeTextGatePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  OpenMuseNativeTextGatePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

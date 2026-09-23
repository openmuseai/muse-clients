library;

import 'package:openmuse_dsh_plugin/openmuse_dsh_plugin.dart';
import 'package:openmuse_file_viewer/openmuse_file_viewer.dart';
import 'package:openmuse_helix_plugin/openmuse_helix_plugin.dart';
import 'package:openmuse_native_text_gate/openmuse_native_text_gate.dart';
import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';

export 'src/demo_workspace.dart';

List<OpenMusePlugin> createOpenMuseBuiltInPlugins() => [
  OpenMuseHelixPlugin(),
  OpenMuseFileViewerPlugin(),
  OpenMuseDshPlugin(),
  OpenMuseNativeTextGatePlugin(),
];

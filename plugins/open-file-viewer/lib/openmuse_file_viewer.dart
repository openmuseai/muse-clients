library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';

final class OpenMuseFileViewerPlugin implements OpenMusePlugin {
  @override
  final descriptor = const OpenMusePluginDescriptor(
    id: 'com.openmuse.open-file-viewer',
    name: 'Open File Viewer',
    version: '0.1.0',
    runtime: OpenMusePluginRuntime.webView,
    activationEvents: ['onFileType:image', 'onFileType:pdf'],
    permissions: {'filesystem.workspace.read'},
    editors: [
      OpenMuseEditorContribution(
        id: 'viewer.image',
        extensions: {'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'},
        priority: 20,
      ),
      OpenMuseEditorContribution(
        id: 'viewer.pdf',
        extensions: {'pdf'},
        priority: 20,
      ),
      OpenMuseEditorContribution(
        id: 'viewer.fallback',
        extensions: {},
        priority: 0,
        catchAll: true,
      ),
    ],
  );

  @override
  Future<void> activate(OpenMusePluginContext context) async {}

  @override
  Future<void> deactivate() async {}

  @override
  Widget buildEditor(BuildContext context, OpenMuseResource resource) {
    if (!resource.uri.isScheme('file')) {
      return const _ViewerMessage('Viewer 仅接受 Host 授权后的本地文件句柄。');
    }
    if (!descriptor.editors.take(2).any((editor) => editor.accepts(resource))) {
      return const _ViewerMessage('此文件类型尚无可用预览器。可安装对应格式的插件。');
    }
    if (Platform.isMacOS) {
      final path = resource.uri.toFilePath();
      return AppKitView(
        key: ValueKey(path),
        viewType: 'com.openmuse.viewer',
        creationParams: <String, Object?>{'path': path},
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    return const _ViewerMessage('Windows viewer 原生适配器尚未通过发布门禁。');
  }

  @override
  Widget? buildPanel(BuildContext context, String panelId) => null;
}

final class _ViewerMessage extends StatelessWidget {
  const _ViewerMessage(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xfff1f2f5),
    child: Center(child: Text(message)),
  );
}

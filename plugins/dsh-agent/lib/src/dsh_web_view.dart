import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final class DshResourceOpenMessage {
  const DshResourceOpenMessage({
    required this.path,
    required this.cwd,
    this.line,
  });

  factory DshResourceOpenMessage.parse(Object? raw) {
    final value = raw is String ? jsonDecode(raw) : raw;
    if (value is! Map || value['type'] != 'resource.open') {
      throw const FormatException('无效 DSH 文件打开消息');
    }
    final path = value['path'];
    final cwd = value['cwd'];
    if (path is! String ||
        cwd is! String ||
        path.isEmpty ||
        cwd.isEmpty ||
        path.length > 4096 ||
        cwd.length > 4096) {
      throw const FormatException('无效 DSH 文件路径');
    }
    final line = value['line'];
    return DshResourceOpenMessage(
      path: path,
      cwd: cwd,
      line: line is int && line > 0 ? line : null,
    );
  }

  final String path;
  final String cwd;
  final int? line;
}

final class DshWebView extends StatefulWidget {
  const DshWebView({
    super.key,
    required this.url,
    required this.onOpenResource,
    required this.reloadToken,
  });

  final Uri url;
  final Future<void> Function(DshResourceOpenMessage request) onOpenResource;
  final int reloadToken;

  @override
  State<DshWebView> createState() => _DshWebViewState();
}

final class _DshWebViewState extends State<DshWebView> {
  MethodChannel? _channel;

  @override
  void didUpdateWidget(DshWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadToken != widget.reloadToken) {
      _channel?.invokeMethod<void>('reload');
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _created(int viewId) {
    final channel = MethodChannel('com.openmuse.dsh/webview/$viewId');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'resourceOpen') return;
      try {
        final request = DshResourceOpenMessage.parse(call.arguments);
        await widget.onOpenResource(request);
      } catch (error) {
        debugPrint('Rejected DSH resource open: $error');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) {
      return Center(
        child: SelectableText(
          'DSH 已启动：\n${widget.url}\n\n当前平台的嵌入式 WebView 仍在适配。',
          textAlign: TextAlign.center,
        ),
      );
    }
    return AppKitView(
      viewType: 'com.openmuse.dsh/webview',
      creationParams: {'url': widget.url.toString()},
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _created,
    );
  }
}

library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';

final class OpenMuseNativeTextGatePlugin implements OpenMusePlugin {
  @override
  final descriptor = const OpenMusePluginDescriptor(
    id: 'com.openmuse.native-text-gate',
    name: 'Native Text Gate',
    version: '0.1.0',
    runtime: OpenMusePluginRuntime.builtIn,
    activationEvents: ['onFileType:native-gate'],
    editors: [
      OpenMuseEditorContribution(
        id: 'native-text.gate',
        extensions: {'native-gate'},
        priority: 100,
      ),
    ],
  );

  @override
  Future<void> activate(OpenMusePluginContext context) async {}

  @override
  Future<void> deactivate() async {}

  @override
  Widget buildEditor(BuildContext context, OpenMuseResource resource) =>
      _NativeTextSurface(active: true);

  @override
  Widget? buildPanel(BuildContext context, String panelId) => null;
}

final class _NativeTextSurface extends StatelessWidget {
  const _NativeTextSurface({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) {
      return const AppKitView(
        viewType: 'com.openmuse.native-text',
        creationParams: <String, Object?>{
          'text': 'OpenMuse Native View 插件\n\n请测试中文输入法、焦点、选择、复制粘贴与窗口缩放。',
        },
        creationParamsCodec: StandardMessageCodec(),
      );
    }
    if (Platform.isWindows) return WindowsNativeTextSlot(active: active);
    return const Center(child: Text('当前平台没有 Native View 适配器。'));
  }
}

final class WindowsNativeTextSlot extends StatefulWidget {
  const WindowsNativeTextSlot({super.key, required this.active});
  final bool active;

  @override
  State<WindowsNativeTextSlot> createState() => _WindowsNativeTextSlotState();
}

final class _WindowsNativeTextSlotState extends State<WindowsNativeTextSlot>
    with WidgetsBindingObserver {
  static const channel = MethodChannel('com.openmuse.native_text_gate/view');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleBounds();
  }

  @override
  void didUpdateWidget(covariant WindowsNativeTextSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) {
      channel.invokeMethod<void>('hide');
    } else {
      _scheduleBounds();
    }
  }

  @override
  void didChangeMetrics() => _scheduleBounds();

  @override
  Widget build(BuildContext context) {
    _scheduleBounds();
    return const ColoredBox(color: Color(0xfff7f8fb));
  }

  void _scheduleBounds() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !widget.active) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final origin = box.localToGlobal(Offset.zero);
      final ratio = MediaQuery.devicePixelRatioOf(context);
      await channel.invokeMethod<void>('show', {
        'x': origin.dx * ratio,
        'y': origin.dy * ratio,
        'width': box.size.width * ratio,
        'height': box.size.height * ratio,
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    channel.invokeMethod<void>('hide');
    super.dispose();
  }
}

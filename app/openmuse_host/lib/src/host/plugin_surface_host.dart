import 'package:flutter/material.dart';
import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';

final class PluginEditorHost extends StatefulWidget {
  const PluginEditorHost({
    super.key,
    required this.registry,
    required this.plugin,
    required this.resource,
  });

  final OpenMusePluginRegistry registry;
  final OpenMusePlugin plugin;
  final OpenMuseResource resource;

  @override
  State<PluginEditorHost> createState() => _PluginEditorHostState();
}

final class _PluginEditorHostState extends State<PluginEditorHost> {
  late Future<void> activation;

  @override
  void initState() {
    super.initState();
    activation = widget.registry.ensureActive(widget.plugin);
  }

  @override
  void didUpdateWidget(covariant PluginEditorHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plugin.descriptor.id != widget.plugin.descriptor.id) {
      activation = widget.registry.ensureActive(widget.plugin);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: activation,
    builder: (context, snapshot) {
      if (snapshot.hasError) return _PluginError(error: snapshot.error!);
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      return widget.plugin.buildEditor(context, widget.resource);
    },
  );
}

final class PluginPanelHost extends StatefulWidget {
  const PluginPanelHost({
    super.key,
    required this.registry,
    required this.plugin,
    required this.panelId,
  });

  final OpenMusePluginRegistry registry;
  final OpenMusePlugin plugin;
  final String panelId;

  @override
  State<PluginPanelHost> createState() => _PluginPanelHostState();
}

final class _PluginPanelHostState extends State<PluginPanelHost> {
  late Future<void> activation = widget.registry.ensureActive(widget.plugin);

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: activation,
    builder: (context, snapshot) {
      if (snapshot.hasError) return _PluginError(error: snapshot.error!);
      if (snapshot.connectionState != ConnectionState.done) {
        return const ColoredBox(
          color: Color(0xff171719),
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xff9cacff),
            ),
          ),
        );
      }
      return widget.plugin.buildPanel(context, widget.panelId) ??
          const SizedBox.shrink();
    },
  );
}

final class _PluginError extends StatelessWidget {
  const _PluginError({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text('插件启动失败\n$error', textAlign: TextAlign.center),
    ),
  );
}

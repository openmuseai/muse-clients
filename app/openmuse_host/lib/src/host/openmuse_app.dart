import 'package:flutter/material.dart';
import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';

import 'design_system.dart';
import 'local_settings.dart';
import 'workbench_shell.dart';
import 'workspace_controller.dart';

final class OpenMuseHostApp extends StatelessWidget {
  const OpenMuseHostApp({
    super.key,
    required this.registry,
    required this.workspace,
    this.settings,
  });

  final OpenMusePluginRegistry registry;
  final LocalWorkspaceController workspace;
  final OpenMuseLocalSettings? settings;

  @override
  Widget build(BuildContext context) {
    final preferences = settings ?? OpenMuseLocalSettings();
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'OpenMuse',
        theme: buildOpenMuseTheme(),
        darkTheme: buildOpenMuseTheme(brightness: Brightness.dark),
        themeMode: preferences.themeMode,
        home: OpenMuseWorkbench(
          registry: registry,
          workspace: workspace,
          settings: preferences,
        ),
      ),
    );
  }
}

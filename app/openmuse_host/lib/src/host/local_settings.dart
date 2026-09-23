import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// Local, non-secret Host preferences. Plugin values are namespaced and never
/// interpreted by the Host; credentials remain the responsibility of plugins.
final class OpenMuseLocalSettings extends ChangeNotifier {
  OpenMuseLocalSettings({this.file});

  final File? file;
  ThemeMode themeMode = ThemeMode.system;
  double? sidebarWidth;
  double? assistantWidth;
  bool assistantVisible = true;
  final Map<String, String> _defaultEditors = {};
  final Map<String, Map<String, Object?>> _pluginValues = {};

  Future<void> load() async {
    final source = file;
    if (source == null || !await source.exists()) return;
    try {
      final data = jsonDecode(await source.readAsString());
      if (data is! Map<String, dynamic> || data['version'] != 1) return;
      themeMode = ThemeMode.values.firstWhere(
        (mode) => mode.name == data['themeMode'],
        orElse: () => ThemeMode.system,
      );
      sidebarWidth = _validWidth(data['sidebarWidth'], 180, 520);
      assistantWidth = _validWidth(data['assistantWidth'], 280, 960);
      assistantVisible = data['assistantVisible'] is bool
          ? data['assistantVisible'] as bool
          : true;
      if (data['defaultEditors'] case final Map defaults) {
        for (final entry in defaults.entries) {
          if (entry.key is String && entry.value is String) {
            _defaultEditors[entry.key as String] = entry.value as String;
          }
        }
      }
      if (data['plugins'] case final Map plugins) {
        for (final entry in plugins.entries) {
          if (entry.key is String && entry.value is Map) {
            _pluginValues[entry.key as String] = Map<String, Object?>.from(
              entry.value as Map,
            );
          }
        }
      }
      notifyListeners();
    } on FormatException {
      // A corrupt preferences file must not block local workspace startup.
    } on FileSystemException {
      // Read-only profiles can still launch with defaults.
    }
  }

  static double? _validWidth(Object? value, double min, double max) =>
      value is num && value.isFinite && value >= min && value <= max
      ? value.toDouble()
      : null;

  Map<String, Object?> pluginValues(String pluginId) =>
      Map.unmodifiable(_pluginValues[pluginId] ?? const {});

  String? defaultEditorFor(String extension) =>
      _defaultEditors[extension.toLowerCase()];

  Future<void> setDefaultEditor(String extension, String editorId) async {
    _defaultEditors[extension.toLowerCase()] = editorId;
    notifyListeners();
    await save();
  }

  Future<void> updatePluginValues(
    String pluginId,
    Map<String, Object?> values,
  ) async {
    if (!pluginId.startsWith('com.openmuse.')) {
      throw ArgumentError.value(pluginId, 'pluginId');
    }
    _pluginValues[pluginId] = Map.of(values);
    notifyListeners();
    await save();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    themeMode = value;
    notifyListeners();
    await save();
  }

  Future<void> setAssistantVisible(bool value) async {
    assistantVisible = value;
    notifyListeners();
    await save();
  }

  void setPaneWidth({double? sidebar, double? assistant}) {
    if (sidebar != null) sidebarWidth = sidebar.clamp(180, 520);
    if (assistant != null) assistantWidth = assistant.clamp(280, 960);
    notifyListeners();
  }

  Future<void> resetPaneWidth({required bool sidebar}) async {
    if (sidebar) {
      sidebarWidth = null;
    } else {
      assistantWidth = null;
    }
    notifyListeners();
    await save();
  }

  Future<void> save() async {
    final target = file;
    if (target == null) return;
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'version': 1,
        'themeMode': themeMode.name,
        'sidebarWidth': sidebarWidth,
        'assistantWidth': assistantWidth,
        'assistantVisible': assistantVisible,
        'defaultEditors': _defaultEditors,
        'plugins': _pluginValues,
      }),
      flush: true,
    );
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }
}

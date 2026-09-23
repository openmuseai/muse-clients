import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_host/src/host/local_settings.dart';

void main() {
  test(
    'local appearance, pane widths and plugin namespace round-trip',
    () async {
      final root = await Directory.systemTemp.createTemp('openmuse-settings-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/settings.json');
      final settings = OpenMuseLocalSettings(file: file);
      await settings.setThemeMode(ThemeMode.dark);
      settings.setPaneWidth(sidebar: 310, assistant: 520);
      await settings.setAssistantVisible(false);
      await settings.setDefaultEditor('SH', 'helix.editor');
      await settings.updatePluginValues('com.openmuse.helix', {
        'theme': 'openmuse_dark',
        'enableLsp': false,
      });

      final restored = OpenMuseLocalSettings(file: file);
      await restored.load();
      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.sidebarWidth, 310);
      expect(restored.assistantWidth, 520);
      expect(restored.assistantVisible, isFalse);
      expect(restored.defaultEditorFor('sh'), 'helix.editor');
      expect(restored.pluginValues('com.openmuse.helix')['enableLsp'], false);
      expect(restored.pluginValues('com.openmuse.dsh-agent'), isEmpty);
    },
  );

  test(
    'invalid width and corrupt JSON fall back without startup failure',
    () async {
      final root = await Directory.systemTemp.createTemp('openmuse-settings-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/settings.json');
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'themeMode': 'unknown',
          'sidebarWidth': 9999,
          'assistantWidth': -1,
        }),
      );
      final settings = OpenMuseLocalSettings(file: file);
      await settings.load();
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.sidebarWidth, isNull);
      expect(settings.assistantWidth, isNull);

      await file.writeAsString('{broken');
      await OpenMuseLocalSettings(file: file).load();
    },
  );
}

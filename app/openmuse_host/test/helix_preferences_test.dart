import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_helix_plugin/openmuse_helix_plugin.dart';

void main() {
  test(
    'Helix preferences create live runtime theme, keymap and LSP config',
    () {
      final settings = const HelixPreferences().copyWith(
        theme: 'openmuse_dark',
        vscodeKeymap: true,
        fontFamily: 'Monaco',
        fontSize: 16,
        enableLsp: false,
      );
      expect(settings.configToml, contains('theme = "openmuse_dark"'));
      expect(settings.configToml, contains('enable = false'));
      expect(settings.configToml, contains('F12 = "goto_definition"'));
      expect(settings.configToml, contains('C-z = "undo"'));
      expect(settings.terminalStyle.fontSize, 16);
      expect(settings.terminalTheme.background, isNotNull);
      expect(
        HelixPreferences.fromJson(settings.toJson()).toJson(),
        settings.toJson(),
      );
    },
  );

  test('Language Server override uses an existing local executable', () async {
    final directory = await Directory.systemTemp.createTemp('openmuse-lsp-');
    addTearDown(() => directory.delete(recursive: true));
    final executable = File('${directory.path}/dart');
    await executable.writeAsString('test');
    final settings = const HelixPreferences().copyWith(
      languageServerPaths: {
        'dart': executable.path,
        'rust-analyzer': '${directory.path}/missing',
        'untrusted.name': executable.path,
      },
    );
    expect(settings.languagesToml, contains('[language-server.dart]'));
    expect(settings.languagesToml, contains(executable.path));
    expect(settings.languagesToml, isNot(contains('rust-analyzer')));
    expect(settings.languagesToml, isNot(contains('untrusted.name')));
  });

  test('LS catalog reports custom, system and missing independently', () async {
    final directory = await Directory.systemTemp.createTemp('openmuse-lsp-');
    addTearDown(() => directory.delete(recursive: true));
    final dart = File('${directory.path}/dart');
    await dart.writeAsString('test');
    await File('${directory.path}/rust-analyzer').writeAsString('test');
    final statuses = inspectHelixLanguageServers({
      'dart': dart.path,
      'ruff': '${directory.path}/missing',
    }, pathEnvironment: directory.path);
    expect(statuses.length, helixLanguageServers.length);
    expect(statuses.first.presence, HelixServerPresence.custom);
    expect(
      statuses
          .where((value) => value.spec.command == 'rust-analyzer')
          .single
          .presence,
      HelixServerPresence.system,
    );
    expect(
      statuses.where((value) => value.spec.command == 'ruff').single.presence,
      HelixServerPresence.missing,
    );
    final preferences = const HelixPreferences().copyWith(
      languageServerPaths: {'ruff': dart.path},
    );
    expect(preferences.languagesToml, contains('[language-server.ruff]'));
    expect(preferences.languagesToml, contains('"server"'));
  });
}

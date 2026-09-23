import 'dart:io';

import 'package:path/path.dart' as p;

/// The plugin owns the LS catalog. Host persists paths without interpreting it.
final class HelixLanguageServerSpec {
  const HelixLanguageServerSpec(this.command, this.label, this.arguments);

  final String command;
  final String label;
  final List<String> arguments;
}

const helixLanguageServers = <HelixLanguageServerSpec>[
  HelixLanguageServerSpec('dart', 'Dart / Flutter', [
    'language-server',
    '--client-id=helix',
  ]),
  HelixLanguageServerSpec('rust-analyzer', 'Rust', []),
  HelixLanguageServerSpec(
    'typescript-language-server',
    'TypeScript / JavaScript',
    ['--stdio'],
  ),
  HelixLanguageServerSpec('ruff', 'Python / Ruff', ['server']),
  HelixLanguageServerSpec('gopls', 'Go', []),
  HelixLanguageServerSpec('clangd', 'C / C++ / Objective-C', []),
  HelixLanguageServerSpec('vscode-json-language-server', 'JSON / HTML / CSS', [
    '--stdio',
  ]),
];

enum HelixServerPresence { custom, system, missing }

final class HelixServerStatus {
  const HelixServerStatus(this.spec, this.presence, this.path);
  final HelixLanguageServerSpec spec;
  final HelixServerPresence presence;
  final String? path;
}

List<HelixServerStatus> inspectHelixLanguageServers(
  Map<String, String> overrides, {
  String? pathEnvironment,
}) {
  final pathEntries = (pathEnvironment ?? Platform.environment['PATH'] ?? '')
      .split(Platform.isWindows ? ';' : ':')
      .where((item) => item.isNotEmpty);
  return [
    for (final spec in helixLanguageServers)
      _inspect(spec, overrides[spec.command], pathEntries),
  ];
}

HelixServerStatus _inspect(
  HelixLanguageServerSpec spec,
  String? override,
  Iterable<String> pathEntries,
) {
  if (override != null &&
      p.isAbsolute(override) &&
      File(override).existsSync()) {
    return HelixServerStatus(spec, HelixServerPresence.custom, override);
  }
  for (final directory in pathEntries) {
    for (final suffix
        in Platform.isWindows ? const ['', '.exe', '.cmd'] : const ['']) {
      final candidate = p.join(directory, '${spec.command}$suffix');
      if (File(candidate).existsSync()) {
        return HelixServerStatus(spec, HelixServerPresence.system, candidate);
      }
    }
  }
  return HelixServerStatus(spec, HelixServerPresence.missing, null);
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import 'helix_preferences.dart';

enum HelixRuntimeState { stopped, starting, ready, failed }

final class HelixRuntimePool extends ChangeNotifier {
  HelixRuntimePool({String? executable})
    : executable = executable ?? resolveHelixExecutable();

  final String executable;
  final Terminal _idleTerminal = Terminal(maxLines: 5000);
  final Map<String, _HelixSession> _sessions = {};
  Terminal get terminal => _sessions[activePath]?.terminal ?? _idleTerminal;
  Future<void>? _starting;
  HelixRuntimeState state = HelixRuntimeState.stopped;
  Object? lastError;
  int launchCount = 0;
  int? get pid => _sessions[activePath]?.pty.pid;
  String? activePath;
  HelixPreferences preferences = const HelixPreferences();
  final String _configInstance = DateTime.now().microsecondsSinceEpoch
      .toString();
  String get _generatedConfigDirectory =>
      '${Directory.systemTemp.path}/openmuse-helix-$_configInstance';

  Future<void> configure(HelixPreferences value) async {
    preferences = value;
    notifyListeners();
    await _writeConfig();
    if (_sessions.isNotEmpty) {
      for (final session in _sessions.values) {
        await _sendCommand(session.pty, ':config-reload');
        await _sendCommand(session.pty, ':theme ${value.theme}');
      }
    }
  }

  Future<File> _writeConfig() async {
    final directory = Directory(_generatedConfigDirectory);
    await directory.create(recursive: true);
    final config = File('${directory.path}/config.toml');
    await config.writeAsString(preferences.configToml, flush: true);
    final languages = File('${directory.path}/helix/languages.toml');
    await languages.parent.create(recursive: true);
    await languages.writeAsString(preferences.languagesToml, flush: true);
    return config;
  }

  Future<void> _sendCommand(Pty pty, String command) async {
    pty.write(Uint8List.fromList(const [0x1b]));
    await Future<void>.delayed(const Duration(milliseconds: 35));
    pty.write(Uint8List.fromList(utf8.encode(command)));
    await Future<void>.delayed(const Duration(milliseconds: 35));
    pty.write(Uint8List.fromList(const [0x0d]));
  }

  Future<void> openDocument(String path) async {
    if (_sessions.containsKey(path)) {
      activePath = path;
      state = HelixRuntimeState.ready;
      notifyListeners();
      return;
    }
    final inFlight = _starting;
    if (inFlight != null) {
      await inFlight;
      return openDocument(path);
    }
    final operation = _start(path);
    _starting = operation;
    try {
      await operation;
    } finally {
      _starting = null;
    }
  }

  Future<void> _start(String path) async {
    state = HelixRuntimeState.starting;
    activePath = path;
    lastError = null;
    notifyListeners();
    try {
      final runtimePath = File(executable).parent.path;
      final environment = <String, String>{};
      environment['XDG_CONFIG_HOME'] = _generatedConfigDirectory;
      if (File(executable).existsSync() &&
          Directory('$runtimePath/runtime').existsSync()) {
        environment['HELIX_RUNTIME'] = '$runtimePath/runtime';
      }
      final config = await _writeConfig();
      // Launch with the file as an argument, as in the original self-authored
      // surface. Typing an absolute path via :open triggers Helix completion
      // on every character and exposes the command prompt in the editor.
      final pty = Pty.start(
        executable,
        arguments: ['--config', config.path, path],
        workingDirectory: File(path).parent.path,
        environment: environment,
        rows: 30,
        columns: 100,
      );
      final session = _HelixSession(pty);
      session.terminal.onOutput = (data) {
        pty.write(Uint8List.fromList(utf8.encode(data)));
      };
      session.terminal.onResize = (width, height, _, _) =>
          pty.resize(height, width);
      _sessions[path] = session;
      launchCount++;
      activePath = path;
      session.output = pty.output.listen(
        (bytes) =>
            session.terminal.write(utf8.decode(bytes, allowMalformed: true)),
      );
      unawaited(
        pty.exitCode.then((code) {
          if (_sessions[path] != session) return;
          _sessions.remove(path);
          unawaited(session.output?.cancel());
          if (activePath == path) {
            activePath = null;
            state = code == 0
                ? HelixRuntimeState.stopped
                : HelixRuntimeState.failed;
            if (code != 0)
              lastError = StateError('Helix exited with code $code');
            notifyListeners();
          }
        }),
      );
      state = HelixRuntimeState.ready;
      notifyListeners();
    } catch (error) {
      state = HelixRuntimeState.failed;
      lastError = error;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stop() async {
    final sessions = _sessions.values.toList();
    _sessions.clear();
    for (final session in sessions) {
      session.pty.kill();
      await session.output?.cancel();
    }
    activePath = null;
    state = HelixRuntimeState.stopped;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final session in _sessions.values) {
      session.pty.kill();
      unawaited(session.output?.cancel());
    }
    _sessions.clear();
    super.dispose();
  }
}

final class _HelixSession {
  _HelixSession(this.pty);
  final Pty pty;
  final Terminal terminal = Terminal(maxLines: 5000);
  StreamSubscription<List<int>>? output;
}

String resolveHelixExecutable() {
  final override = Platform.environment['OPENMUSE_HELIX_BIN'];
  if (override != null && override.isNotEmpty) return override;
  final executableDirectory = File(Platform.resolvedExecutable).parent.path;
  final relative = Platform.isMacOS
      ? '../Frameworks/App.framework/Resources/flutter_assets/'
            'packages/openmuse_helix_plugin/assets/engines/helix/hx'
      : Platform.isWindows
      ? 'data/flutter_assets/packages/openmuse_helix_plugin/'
            'assets/engines/helix/hx.exe'
      : 'data/flutter_assets/packages/openmuse_helix_plugin/'
            'assets/engines/helix/hx';
  final bundled = File('$executableDirectory/$relative').absolute.path;
  return File(bundled).existsSync() ? bundled : 'hx';
}

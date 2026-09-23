library;

import 'dart:async';

import 'package:flutter/widgets.dart';

enum OpenMusePluginRuntime { builtIn, nativeProcess, webView }

enum OpenMusePluginState { installed, activating, active, deactivating, failed }

enum OpenMuseSurfaceRegion { editor, rightSidebar }

@immutable
final class OpenMuseResource {
  const OpenMuseResource({
    required this.uri,
    required this.displayName,
    this.mediaType,
  });

  final Uri uri;
  final String displayName;
  final String? mediaType;

  String get extension {
    final segment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final separator = segment.lastIndexOf('.');
    return separator < 0 ? '' : segment.substring(separator + 1).toLowerCase();
  }
}

@immutable
final class OpenMuseEditorCandidate {
  const OpenMuseEditorCandidate({required this.plugin, required this.editor});

  final OpenMusePlugin plugin;
  final OpenMuseEditorContribution editor;
}

@immutable
final class OpenMuseEditorContribution {
  const OpenMuseEditorContribution({
    required this.id,
    required this.extensions,
    required this.priority,
    this.catchAll = false,
  });

  final String id;
  final Set<String> extensions;
  final int priority;
  final bool catchAll;

  bool accepts(OpenMuseResource resource) =>
      catchAll || extensions.contains(resource.extension);
}

@immutable
final class OpenMusePanelContribution {
  const OpenMusePanelContribution({required this.id, required this.region});

  final String id;
  final OpenMuseSurfaceRegion region;
}

@immutable
final class OpenMusePluginDescriptor {
  const OpenMusePluginDescriptor({
    required this.id,
    required this.name,
    required this.version,
    required this.runtime,
    this.activationEvents = const [],
    this.permissions = const {},
    this.editors = const [],
    this.panels = const [],
  });

  final String id;
  final String name;
  final String version;
  final OpenMusePluginRuntime runtime;
  final List<String> activationEvents;
  final Set<String> permissions;
  final List<OpenMuseEditorContribution> editors;
  final List<OpenMusePanelContribution> panels;
}

@immutable
final class OpenMusePluginContext {
  const OpenMusePluginContext({
    required this.executeHostCommand,
    this.hostChanges,
  });

  final Future<Object?> Function(String command, Object? arguments)
  executeHostCommand;

  /// Invalidates read-only Host snapshots; plugins re-query through commands.
  final Listenable? hostChanges;
}

abstract interface class OpenMusePlugin {
  OpenMusePluginDescriptor get descriptor;

  Future<void> activate(OpenMusePluginContext context);

  Future<void> deactivate();

  Widget buildEditor(BuildContext context, OpenMuseResource resource);

  Widget? buildPanel(BuildContext context, String panelId);
}

/// Optional plugin-owned settings surface. Host provides the containing page
/// and namespaced persistence; it does not know editor or agent preferences.
abstract interface class OpenMuseSettingsContributor {
  Widget buildSettings(BuildContext context);
}

final class OpenMusePluginRegistry extends ChangeNotifier {
  OpenMusePluginRegistry({required OpenMusePluginContext context})
    : _context = context;

  final OpenMusePluginContext _context;
  final Map<String, OpenMusePlugin> _plugins = {};
  final Map<String, OpenMusePluginState> _states = {};
  final Map<String, Future<void>> _transitions = {};

  Iterable<OpenMusePluginDescriptor> get descriptors =>
      _plugins.values.map((plugin) => plugin.descriptor);

  OpenMusePluginState? stateOf(String pluginId) => _states[pluginId];

  OpenMusePlugin? plugin(String pluginId) => _plugins[pluginId];

  void install(OpenMusePlugin plugin) {
    final id = plugin.descriptor.id;
    if (_plugins.containsKey(id)) {
      throw StateError('Plugin already installed: $id');
    }
    _plugins[id] = plugin;
    _states[id] = OpenMusePluginState.installed;
    notifyListeners();
  }

  Future<void> uninstall(String pluginId) async {
    final plugin = _plugins[pluginId];
    if (plugin == null) return;
    await deactivate(pluginId);
    _plugins.remove(pluginId);
    _states.remove(pluginId);
    notifyListeners();
  }

  Future<void> activate(String pluginId) {
    return _serialize(pluginId, () async {
      final plugin = _requirePlugin(pluginId);
      if (_states[pluginId] == OpenMusePluginState.active) return;
      _states[pluginId] = OpenMusePluginState.activating;
      notifyListeners();
      try {
        await plugin.activate(_context);
        _states[pluginId] = OpenMusePluginState.active;
      } catch (_) {
        _states[pluginId] = OpenMusePluginState.failed;
        rethrow;
      } finally {
        notifyListeners();
      }
    });
  }

  Future<void> deactivate(String pluginId) {
    return _serialize(pluginId, () async {
      final plugin = _plugins[pluginId];
      if (plugin == null ||
          _states[pluginId] == OpenMusePluginState.installed) {
        return;
      }
      _states[pluginId] = OpenMusePluginState.deactivating;
      notifyListeners();
      try {
        await plugin.deactivate();
        _states[pluginId] = OpenMusePluginState.installed;
      } catch (_) {
        _states[pluginId] = OpenMusePluginState.failed;
        rethrow;
      } finally {
        notifyListeners();
      }
    });
  }

  List<OpenMuseEditorCandidate> editorCandidates(OpenMuseResource resource) {
    final result = <OpenMuseEditorCandidate>[
      for (final plugin in _plugins.values)
        for (final editor in plugin.descriptor.editors)
          if (editor.accepts(resource))
            OpenMuseEditorCandidate(plugin: plugin, editor: editor),
    ]..sort((a, b) => b.editor.priority.compareTo(a.editor.priority));
    return result;
  }

  OpenMusePlugin? editorFor(OpenMuseResource resource, {String? editorId}) {
    final candidates = editorCandidates(resource);
    if (editorId == null) return candidates.firstOrNull?.plugin;
    return candidates
            .where((candidate) => candidate.editor.id == editorId)
            .firstOrNull
            ?.plugin ??
        candidates.firstOrNull?.plugin;
  }

  OpenMusePlugin? panelProvider(
    OpenMuseSurfaceRegion region, {
    String? panelId,
  }) {
    return _plugins.values.cast<OpenMusePlugin?>().firstWhere(
      (plugin) => plugin!.descriptor.panels.any(
        (panel) =>
            panel.region == region && (panelId == null || panel.id == panelId),
      ),
      orElse: () => null,
    );
  }

  Future<void> ensureActive(OpenMusePlugin plugin) =>
      activate(plugin.descriptor.id);

  OpenMusePlugin _requirePlugin(String pluginId) {
    final plugin = _plugins[pluginId];
    if (plugin == null) throw StateError('Plugin not installed: $pluginId');
    return plugin;
  }

  Future<void> _serialize(String pluginId, Future<void> Function() operation) {
    final previous = _transitions[pluginId] ?? Future<void>.value();
    final next = previous.then((_) => operation());
    late final Future<void> tracked;
    tracked = next.whenComplete(() {
      if (identical(_transitions[pluginId], tracked)) {
        _transitions.remove(pluginId);
      }
    });
    _transitions[pluginId] = tracked;
    return tracked;
  }
}

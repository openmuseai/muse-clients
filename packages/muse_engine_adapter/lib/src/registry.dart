import 'adapter.dart';

final class MuseAdapterRegistration {
  const MuseAdapterRegistration({
    required this.adapter,
    required this.generation,
  });
  final MuseEngineAdapter adapter;
  final int generation;
  String get adapterRef => adapter.manifest.adapterRef;
  String get key => '$adapterRef#$generation';
}

final class MuseAdapterLease {
  MuseAdapterLease._(this._registry, this.registration);
  final MuseAdapterRegistry _registry;
  final MuseAdapterRegistration registration;
  var _closed = false;
  bool get isClosed => _closed;
  void close() {
    if (_closed) return;
    _closed = true;
    _registry._remove(registration.key);
  }
}

final class MuseAdapterRegistry {
  final _registrations = <String, MuseAdapterRegistration>{};

  int get count => _registrations.length;
  List<MuseAdapterRegistration> get all {
    final result = _registrations.values.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    return result;
  }

  MuseAdapterLease register(
    MuseEngineAdapter adapter, {
    required int generation,
  }) {
    if (generation < 1) throw ArgumentError.value(generation, 'generation');
    final registration = MuseAdapterRegistration(
      adapter: adapter,
      generation: generation,
    );
    if (_registrations.containsKey(registration.key)) {
      throw StateError(
        'ADAPTER_GENERATION_ALREADY_REGISTERED:${registration.key}',
      );
    }
    _registrations[registration.key] = registration;
    return MuseAdapterLease._(this, registration);
  }

  List<MuseAdapterRegistration> candidates({
    required String formatId,
    required String os,
    required String arch,
    required String placement,
  }) {
    final latest = <String, MuseAdapterRegistration>{};
    for (final registration in _registrations.values) {
      final manifest = registration.adapter.manifest;
      final supportsFormat = manifest.formats.any(
        (format) => format.formatId == formatId,
      );
      final supportsPlatform = manifest.platforms.any(
        (platform) => platform.os == os && platform.arch == arch,
      );
      final supportsPlacement = manifest.placements.any(
        (item) =>
            item.name.replaceAllMapped(
              RegExp(r'(?<=[a-z0-9])([A-Z])'),
              (match) => '-${match.group(1)!.toLowerCase()}',
            ) ==
            placement,
      );
      if (!supportsFormat || !supportsPlatform || !supportsPlacement) continue;
      final current = latest[manifest.adapterRef];
      if (current == null || registration.generation > current.generation)
        latest[manifest.adapterRef] = registration;
    }
    final result = latest.values.toList(growable: false)
      ..sort((a, b) => a.adapterRef.compareTo(b.adapterRef));
    return result;
  }

  void _remove(String key) => _registrations.remove(key);
}

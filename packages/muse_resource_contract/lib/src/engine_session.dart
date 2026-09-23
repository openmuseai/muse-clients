import 'presentation.dart';
import 'resource.dart';
import 'wire.dart';

enum MuseEngineMode { view, ephemeralEdit, edit }

enum MusePlacementKind { desktopLocal, webRemote, mobileRemote }

enum MuseAdapterCapability {
  focus,
  setActive,
  navigate,
  context,
  commit,
  health,
}

enum MuseFidelity { nativeEngine, nativePartial, converted, generic }

enum MuseStartupClass { hotFast, warmMedium, coldSlow }

enum MuseEngineSessionState {
  allocating,
  materializing,
  starting,
  ready,
  focused,
  background,
  dirty,
  committing,
  conflict,
  failed,
  closing,
  closed,
  forcedTerminated,
}

final class MuseEngineIdentityV1 {
  const MuseEngineIdentityV1({
    required this.vendor,
    required this.engineId,
    required this.engineVersion,
    this.runtimeDigest,
  });
  final String vendor, engineId, engineVersion;
  final String? runtimeDigest;
  factory MuseEngineIdentityV1.fromJson(Object? value) {
    final map = objectMap(value, 'engine');
    requireKeys(
      map,
      required: {'vendor', 'engineId', 'engineVersion'},
      optional: {'runtimeDigest'},
    );
    return MuseEngineIdentityV1(
      vendor: stringField(map, 'vendor'),
      engineId: stringField(map, 'engineId'),
      engineVersion: stringField(map, 'engineVersion'),
      runtimeDigest: optionalString(map, 'runtimeDigest'),
    );
  }
  Map<String, Object?> toJson() => {
    'vendor': vendor,
    'engineId': engineId,
    'engineVersion': engineVersion,
    if (runtimeDigest != null) 'runtimeDigest': runtimeDigest,
  };
}

final class MusePlatformV1 {
  const MusePlatformV1({required this.os, required this.arch});
  final String os, arch;
  factory MusePlatformV1.fromJson(Object? value) {
    final map = objectMap(value, 'platform');
    requireKeys(map, required: {'os', 'arch'});
    return MusePlatformV1(
      os: stringField(map, 'os'),
      arch: stringField(map, 'arch'),
    );
  }
  Map<String, Object?> toJson() => {'os': os, 'arch': arch};
}

final class MuseFormatSupportV1 {
  const MuseFormatSupportV1({
    required this.formatId,
    required this.mimeTypes,
    required this.extensionsHint,
  });
  final String formatId;
  final List<String> mimeTypes, extensionsHint;
  factory MuseFormatSupportV1.fromJson(Object? value) {
    final map = objectMap(value, 'format');
    requireKeys(map, required: {'formatId', 'mimeTypes', 'extensionsHint'});
    return MuseFormatSupportV1(
      formatId: stringField(map, 'formatId'),
      mimeTypes: stringList(map, 'mimeTypes'),
      extensionsHint: stringList(map, 'extensionsHint'),
    );
  }
  Map<String, Object?> toJson() => {
    'formatId': formatId,
    'mimeTypes': mimeTypes,
    'extensionsHint': extensionsHint,
  };
}

final class MuseAdapterRiskV1 {
  const MuseAdapterRiskV1({
    required this.executesProcess,
    required this.executesActiveContent,
    required this.requiresGpu,
  });
  final bool executesProcess, executesActiveContent, requiresGpu;
  factory MuseAdapterRiskV1.fromJson(Object? value) {
    final map = objectMap(value, 'risk');
    requireKeys(
      map,
      required: {'executesProcess', 'executesActiveContent', 'requiresGpu'},
    );
    return MuseAdapterRiskV1(
      executesProcess: boolField(map, 'executesProcess'),
      executesActiveContent: boolField(map, 'executesActiveContent'),
      requiresGpu: boolField(map, 'requiresGpu'),
    );
  }
  Map<String, Object?> toJson() => {
    'executesProcess': executesProcess,
    'executesActiveContent': executesActiveContent,
    'requiresGpu': requiresGpu,
  };
}

final class MuseEngineAdapterManifestV1 {
  const MuseEngineAdapterManifestV1({
    required this.adapterId,
    required this.adapterVersion,
    required this.engine,
    required this.placements,
    required this.platforms,
    required this.formats,
    required this.modes,
    required this.materializations,
    required this.contextProviders,
    required this.capabilities,
    required this.risk,
  });
  final String adapterId, adapterVersion;
  String get adapterRef => '$adapterId~$adapterVersion';
  final MuseEngineIdentityV1 engine;
  final List<MusePlacementKind> placements;
  final List<MusePlatformV1> platforms;
  final List<MuseFormatSupportV1> formats;
  final List<MuseEngineMode> modes;
  final List<MuseMaterializationKind> materializations;
  final List<String> contextProviders;
  final List<MuseAdapterCapability> capabilities;
  final MuseAdapterRiskV1 risk;
  factory MuseEngineAdapterManifestV1.fromJson(Map<String, Object?> map) {
    if (map['manifestVersion'] != 'muse.engine-adapter-manifest/v1')
      throw const MuseContractFormatException(
        'manifestVersion must be muse.engine-adapter-manifest/v1',
      );
    requireKeys(
      map,
      required: {
        'manifestVersion',
        'adapterId',
        'adapterVersion',
        'engine',
        'placements',
        'platforms',
        'formats',
        'modes',
        'materializations',
        'contextProviders',
        'capabilities',
        'risk',
      },
    );
    final modes = enumList(map, 'modes', MuseEngineMode.values);
    final capabilities = enumList(
      map,
      'capabilities',
      MuseAdapterCapability.values,
    );
    if (modes.contains(MuseEngineMode.edit) &&
        !capabilities.contains(MuseAdapterCapability.commit))
      throw const MuseContractFormatException(
        'edit mode requires commit capability',
      );
    final placements = enumList(map, 'placements', MusePlacementKind.values);
    final platforms = objectList(
      map['platforms'],
      'platforms',
    ).map(MusePlatformV1.fromJson).toList();
    final formats = objectList(
      map['formats'],
      'formats',
    ).map(MuseFormatSupportV1.fromJson).toList();
    final materializations = enumList(
      map,
      'materializations',
      MuseMaterializationKind.values,
    );
    if (placements.isEmpty ||
        platforms.isEmpty ||
        formats.isEmpty ||
        modes.isEmpty ||
        materializations.isEmpty) {
      throw const MuseContractFormatException(
        'manifest placements/platforms/formats/modes/materializations must not be empty',
      );
    }
    return MuseEngineAdapterManifestV1(
      adapterId: stringField(map, 'adapterId'),
      adapterVersion: stringField(map, 'adapterVersion'),
      engine: MuseEngineIdentityV1.fromJson(map['engine']),
      placements: placements,
      platforms: platforms,
      formats: formats,
      modes: modes,
      materializations: materializations,
      contextProviders: stringList(map, 'contextProviders'),
      capabilities: capabilities,
      risk: MuseAdapterRiskV1.fromJson(map['risk']),
    );
  }
  Map<String, Object?> toJson() => {
    'manifestVersion': 'muse.engine-adapter-manifest/v1',
    'adapterId': adapterId,
    'adapterVersion': adapterVersion,
    'engine': engine.toJson(),
    'placements': placements.map(enumWire).toList(),
    'platforms': platforms.map((e) => e.toJson()).toList(),
    'formats': formats.map((e) => e.toJson()).toList(),
    'modes': modes.map(enumWire).toList(),
    'materializations': materializations.map(enumWire).toList(),
    'contextProviders': contextProviders,
    'capabilities': capabilities.map(enumWire).toList(),
    'risk': risk.toJson(),
  };
}

final class MuseProbeDescriptorV1 {
  const MuseProbeDescriptorV1({
    required this.resourceRef,
    required this.revision,
    required this.format,
    required this.security,
    this.sizeBytes,
  });
  final String resourceRef, revision;
  final MuseResourceFormat format;
  final int? sizeBytes;
  final MuseResourceSecurity security;
  factory MuseProbeDescriptorV1.fromJson(Object? value) {
    final map = objectMap(value, 'descriptor');
    requireKeys(
      map,
      required: {'resourceRef', 'revision', 'format', 'security'},
      optional: {'sizeBytes'},
    );
    return MuseProbeDescriptorV1(
      resourceRef: stringField(map, 'resourceRef'),
      revision: stringField(map, 'revision'),
      format: MuseResourceFormat.fromJson(map['format']),
      sizeBytes: optionalInt(map, 'sizeBytes'),
      security: MuseResourceSecurity.fromJson(map['security']),
    );
  }
  Map<String, Object?> toJson() => {
    'resourceRef': resourceRef,
    'revision': revision,
    'format': format.toJson(),
    if (sizeBytes != null) 'sizeBytes': sizeBytes,
    'security': security.toJson(),
  };
}

final class MuseProbePlacementV1 {
  const MuseProbePlacementV1({
    required this.kind,
    required this.os,
    required this.arch,
    required this.memoryBudgetBytes,
    required this.gpu,
  });
  final MusePlacementKind kind;
  final String os, arch;
  final int memoryBudgetBytes;
  final bool gpu;
  factory MuseProbePlacementV1.fromJson(Object? value) {
    final map = objectMap(value, 'placement');
    requireKeys(
      map,
      required: {'kind', 'os', 'arch', 'memoryBudgetBytes', 'gpu'},
    );
    return MuseProbePlacementV1(
      kind: enumField(map, 'kind', MusePlacementKind.values),
      os: stringField(map, 'os'),
      arch: stringField(map, 'arch'),
      memoryBudgetBytes: intField(map, 'memoryBudgetBytes'),
      gpu: boolField(map, 'gpu'),
    );
  }
  Map<String, Object?> toJson() => {
    'kind': enumWire(kind),
    'os': os,
    'arch': arch,
    'memoryBudgetBytes': memoryBudgetBytes,
    'gpu': gpu,
  };
}

final class MuseProbeRequestV1 {
  const MuseProbeRequestV1({
    required this.probeRef,
    required this.descriptor,
    required this.placement,
    required this.requestedMode,
    required this.policyRevision,
    required this.deadlineAt,
    required this.cancellationRef,
  });
  final String probeRef, policyRevision, cancellationRef;
  final MuseProbeDescriptorV1 descriptor;
  final MuseProbePlacementV1 placement;
  final MuseRequestedMode requestedMode;
  final int deadlineAt;
  factory MuseProbeRequestV1.fromJson(Map<String, Object?> map) {
    requireProtocol(map, 'muse.engine/probe-request/v1');
    requireKeys(
      map,
      required: {
        'protocol',
        'probeRef',
        'descriptor',
        'placement',
        'requestedMode',
        'policyRevision',
        'deadlineAt',
        'cancellationRef',
      },
    );
    return MuseProbeRequestV1(
      probeRef: stringField(map, 'probeRef'),
      descriptor: MuseProbeDescriptorV1.fromJson(map['descriptor']),
      placement: MuseProbePlacementV1.fromJson(map['placement']),
      requestedMode: enumField(map, 'requestedMode', MuseRequestedMode.values),
      policyRevision: stringField(map, 'policyRevision'),
      deadlineAt: intField(map, 'deadlineAt'),
      cancellationRef: stringField(map, 'cancellationRef'),
    );
  }
  Map<String, Object?> toJson() => {
    'protocol': 'muse.engine/probe-request/v1',
    'probeRef': probeRef,
    'descriptor': descriptor.toJson(),
    'placement': placement.toJson(),
    'requestedMode': enumWire(requestedMode),
    'policyRevision': policyRevision,
    'deadlineAt': deadlineAt,
    'cancellationRef': cancellationRef,
  };
}

final class MuseProbeQualityV1 {
  const MuseProbeQualityV1({
    required this.fidelity,
    required this.startupClass,
  });
  final MuseFidelity fidelity;
  final MuseStartupClass startupClass;
  factory MuseProbeQualityV1.fromJson(Object? value) {
    final map = objectMap(value, 'quality');
    requireKeys(map, required: {'fidelity', 'startupClass'});
    final raw = stringField(map, 'fidelity');
    final fidelity = switch (raw) {
      'native' => MuseFidelity.nativeEngine,
      'native-partial' => MuseFidelity.nativePartial,
      'converted' => MuseFidelity.converted,
      'generic' => MuseFidelity.generic,
      _ => throw MuseContractFormatException(
        'fidelity has unsupported value $raw',
      ),
    };
    return MuseProbeQualityV1(
      fidelity: fidelity,
      startupClass: enumField(map, 'startupClass', MuseStartupClass.values),
    );
  }
  Map<String, Object?> toJson() => {
    'fidelity': fidelity == MuseFidelity.nativeEngine
        ? 'native'
        : enumWire(fidelity),
    'startupClass': enumWire(startupClass),
  };
}

final class MuseProbeResultV1 {
  const MuseProbeResultV1({
    required this.probeRef,
    required this.available,
    required this.effectiveModes,
    required this.materializationKinds,
    required this.maxBytes,
    required this.quality,
    required this.warnings,
    required this.probeDigest,
    required this.expiresAt,
  });
  final String probeRef, probeDigest;
  final bool available;
  final List<MuseEngineMode> effectiveModes;
  final List<MuseMaterializationKind> materializationKinds;
  final int maxBytes;
  final MuseProbeQualityV1 quality;
  final List<String> warnings;
  final int expiresAt;
  factory MuseProbeResultV1.fromJson(Map<String, Object?> map) {
    requireProtocol(map, 'muse.engine/probe-result/v1');
    requireKeys(
      map,
      required: {
        'protocol',
        'probeRef',
        'available',
        'effectiveModes',
        'materializationKinds',
        'limits',
        'quality',
        'warnings',
        'probeDigest',
        'expiresAt',
      },
    );
    final available = boolField(map, 'available');
    final modes = enumList(map, 'effectiveModes', MuseEngineMode.values);
    final kinds = enumList(
      map,
      'materializationKinds',
      MuseMaterializationKind.values,
    );
    if (!available && (modes.isNotEmpty || kinds.isNotEmpty))
      throw const MuseContractFormatException(
        'unavailable probe cannot advertise usable modes',
      );
    final limits = objectMap(map['limits'], 'limits');
    requireKeys(limits, required: {'maxBytes'});
    return MuseProbeResultV1(
      probeRef: stringField(map, 'probeRef'),
      available: available,
      effectiveModes: modes,
      materializationKinds: kinds,
      maxBytes: intField(limits, 'maxBytes'),
      quality: MuseProbeQualityV1.fromJson(map['quality']),
      warnings: stringList(map, 'warnings'),
      probeDigest: stringField(map, 'probeDigest'),
      expiresAt: intField(map, 'expiresAt'),
    );
  }
  Map<String, Object?> toJson() => {
    'protocol': 'muse.engine/probe-result/v1',
    'probeRef': probeRef,
    'available': available,
    'effectiveModes': effectiveModes.map(enumWire).toList(),
    'materializationKinds': materializationKinds.map(enumWire).toList(),
    'limits': {'maxBytes': maxBytes},
    'quality': quality.toJson(),
    'warnings': warnings,
    'probeDigest': probeDigest,
    'expiresAt': expiresAt,
  };
}

final class MuseOpenMaterializationV1 {
  const MuseOpenMaterializationV1({
    required this.kind,
    required this.handleRef,
    required this.expiresAt,
  });
  final MuseMaterializationKind kind;
  final String handleRef;
  final int expiresAt;
  factory MuseOpenMaterializationV1.fromJson(Object? value) {
    final map = objectMap(value, 'materialization');
    requireKeys(map, required: {'kind', 'handleRef', 'expiresAt'});
    return MuseOpenMaterializationV1(
      kind: enumField(map, 'kind', MuseMaterializationKind.values),
      handleRef: stringField(map, 'handleRef'),
      expiresAt: intField(map, 'expiresAt'),
    );
  }
  Map<String, Object?> toJson() => {
    'kind': enumWire(kind),
    'handleRef': handleRef,
    'expiresAt': expiresAt,
  };
}

final class MuseOpenSurfaceV1 {
  const MuseOpenSurfaceV1({
    required this.windowRef,
    required this.placement,
    required this.reuse,
  });
  final String windowRef, placement, reuse;
  factory MuseOpenSurfaceV1.fromJson(Object? value) {
    final map = objectMap(value, 'surface');
    requireKeys(map, required: {'windowRef', 'placement', 'reuse'});
    final placement = stringField(map, 'placement'),
        reuse = stringField(map, 'reuse');
    if (!{'main', 'side-panel', 'floating', 'background'}.contains(placement) ||
        !{'never', 'compatible', 'resource'}.contains(reuse))
      throw const MuseContractFormatException('unsupported surface policy');
    return MuseOpenSurfaceV1(
      windowRef: stringField(map, 'windowRef'),
      placement: placement,
      reuse: reuse,
    );
  }
  Map<String, Object?> toJson() => {
    'windowRef': windowRef,
    'placement': placement,
    'reuse': reuse,
  };
}

final class MuseOpenEngineSessionRequestV1 {
  const MuseOpenEngineSessionRequestV1({
    required this.requestRef,
    required this.attemptRef,
    required this.resourceRef,
    required this.baseRevision,
    required this.mode,
    required this.materialization,
    required this.surface,
    required this.generation,
    this.anchorHint,
  });
  final String requestRef, attemptRef, resourceRef, baseRevision;
  final MuseEngineMode mode;
  final MuseOpenMaterializationV1 materialization;
  final MuseOpenSurfaceV1 surface;
  final MuseAnchorHintV1? anchorHint;
  final int generation;
  factory MuseOpenEngineSessionRequestV1.fromJson(Map<String, Object?> map) {
    requireProtocol(map, 'muse.engine/open-session-request/v1');
    requireKeys(
      map,
      required: {
        'protocol',
        'requestRef',
        'attemptRef',
        'resourceRef',
        'baseRevision',
        'mode',
        'materialization',
        'surface',
        'generation',
      },
      optional: {'anchorHint'},
    );
    return MuseOpenEngineSessionRequestV1(
      requestRef: stringField(map, 'requestRef'),
      attemptRef: stringField(map, 'attemptRef'),
      resourceRef: stringField(map, 'resourceRef'),
      baseRevision: stringField(map, 'baseRevision'),
      mode: enumField(map, 'mode', MuseEngineMode.values),
      materialization: MuseOpenMaterializationV1.fromJson(
        map['materialization'],
      ),
      surface: MuseOpenSurfaceV1.fromJson(map['surface']),
      generation: intField(map, 'generation', min: 1),
      anchorHint: map['anchorHint'] == null
          ? null
          : MuseAnchorHintV1.fromJson(map['anchorHint']),
    );
  }
  Map<String, Object?> toJson() => {
    'protocol': 'muse.engine/open-session-request/v1',
    'requestRef': requestRef,
    'attemptRef': attemptRef,
    'resourceRef': resourceRef,
    'baseRevision': baseRevision,
    'mode': enumWire(mode),
    'materialization': materialization.toJson(),
    'surface': surface.toJson(),
    if (anchorHint != null) 'anchorHint': anchorHint!.toJson(),
    'generation': generation,
  };
}

final class MuseEngineSessionHandleV1 {
  const MuseEngineSessionHandleV1({
    required this.sessionRef,
    required this.surfaceInstanceRef,
    required this.adapterRef,
    required this.resourceRef,
    required this.baseRevision,
    required this.mode,
    required this.generation,
    required this.state,
  });
  final String sessionRef,
      surfaceInstanceRef,
      adapterRef,
      resourceRef,
      baseRevision;
  final MuseEngineMode mode;
  final int generation;
  final MuseEngineSessionState state;
  factory MuseEngineSessionHandleV1.fromJson(Map<String, Object?> map) {
    requireProtocol(map, 'muse.engine/session-handle/v1');
    requireKeys(
      map,
      required: {
        'protocol',
        'sessionRef',
        'surfaceInstanceRef',
        'adapterRef',
        'resourceRef',
        'baseRevision',
        'mode',
        'generation',
        'state',
      },
    );
    return MuseEngineSessionHandleV1(
      sessionRef: stringField(map, 'sessionRef'),
      surfaceInstanceRef: stringField(map, 'surfaceInstanceRef'),
      adapterRef: stringField(map, 'adapterRef'),
      resourceRef: stringField(map, 'resourceRef'),
      baseRevision: stringField(map, 'baseRevision'),
      mode: enumField(map, 'mode', MuseEngineMode.values),
      generation: intField(map, 'generation', min: 1),
      state: enumField(map, 'state', MuseEngineSessionState.values),
    );
  }
  Map<String, Object?> toJson() => {
    'protocol': 'muse.engine/session-handle/v1',
    'sessionRef': sessionRef,
    'surfaceInstanceRef': surfaceInstanceRef,
    'adapterRef': adapterRef,
    'resourceRef': resourceRef,
    'baseRevision': baseRevision,
    'mode': enumWire(mode),
    'generation': generation,
    'state': enumWire(state),
  };
}

sealed class MuseEngineSessionWireValueV1 {
  const MuseEngineSessionWireValueV1();
  Map<String, Object?> toJson();
  factory MuseEngineSessionWireValueV1.fromJson(
    String kind,
    Map<String, Object?> map,
  ) => switch (kind) {
    'manifest' => MuseManifestMessage(
      MuseEngineAdapterManifestV1.fromJson(map),
    ),
    'probe-request' => MuseProbeRequestMessage(
      MuseProbeRequestV1.fromJson(map),
    ),
    'probe-result' => MuseProbeResultMessage(MuseProbeResultV1.fromJson(map)),
    'open-session-request' => MuseOpenSessionRequestMessage(
      MuseOpenEngineSessionRequestV1.fromJson(map),
    ),
    'session-handle' => MuseSessionHandleMessage(
      MuseEngineSessionHandleV1.fromJson(map),
    ),
    'session-event' => MuseSessionEventMessage.parse(map),
    _ => throw MuseContractFormatException('unknown engine schema kind $kind'),
  };
}

final class MuseManifestMessage extends MuseEngineSessionWireValueV1 {
  const MuseManifestMessage(this.value);
  final MuseEngineAdapterManifestV1 value;
  @override
  Map<String, Object?> toJson() => value.toJson();
}

final class MuseProbeRequestMessage extends MuseEngineSessionWireValueV1 {
  const MuseProbeRequestMessage(this.value);
  final MuseProbeRequestV1 value;
  @override
  Map<String, Object?> toJson() => value.toJson();
}

final class MuseProbeResultMessage extends MuseEngineSessionWireValueV1 {
  const MuseProbeResultMessage(this.value);
  final MuseProbeResultV1 value;
  @override
  Map<String, Object?> toJson() => value.toJson();
}

final class MuseOpenSessionRequestMessage extends MuseEngineSessionWireValueV1 {
  const MuseOpenSessionRequestMessage(this.value);
  final MuseOpenEngineSessionRequestV1 value;
  @override
  Map<String, Object?> toJson() => value.toJson();
}

final class MuseSessionHandleMessage extends MuseEngineSessionWireValueV1 {
  const MuseSessionHandleMessage(this.value);
  final MuseEngineSessionHandleV1 value;
  @override
  Map<String, Object?> toJson() => value.toJson();
}

final class MuseSessionEventMessage extends MuseEngineSessionWireValueV1 {
  MuseSessionEventMessage._(this._value);
  final Map<String, Object?> _value;
  static MuseSessionEventMessage parse(Map<String, Object?> map) {
    requireProtocol(map, 'muse.engine/session-event/v1');
    requireKeys(
      map,
      required: {
        'protocol',
        'eventRef',
        'cursor',
        'sessionRef',
        'resourceRef',
        'generation',
        'state',
        'occurredAt',
      },
      optional: {'details'},
    );
    for (final key in ['eventRef', 'cursor', 'sessionRef', 'resourceRef']) {
      stringField(map, key);
    }
    intField(map, 'generation', min: 1);
    enumField(map, 'state', MuseEngineSessionState.values);
    intField(map, 'occurredAt');
    if (map['details'] != null) objectMap(map['details'], 'details');
    return MuseSessionEventMessage._(deepCopyMap(map));
  }

  @override
  Map<String, Object?> toJson() => deepCopyMap(_value);
}

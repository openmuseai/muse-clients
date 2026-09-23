import 'package:muse_engine_adapter/muse_engine_adapter.dart';
import 'package:muse_resource_contract/muse_resource_contract.dart';

import 'admission.dart';

final class MuseIofficeWordHealth {
  const MuseIofficeWordHealth({
    required this.artifactPresent,
    required this.digestMatches,
    required this.abiMatches,
    required this.ffiInitialized,
    required this.smokeLayoutPassed,
    required this.canEditHeap,
    required this.canExportDocx,
    required this.runtimeDigest,
    required this.os,
    required this.arch,
  });
  final bool artifactPresent,
      digestMatches,
      abiMatches,
      ffiInitialized,
      smokeLayoutPassed,
      canEditHeap,
      canExportDocx;
  final String runtimeDigest, os, arch;
  bool get canView =>
      artifactPresent &&
      digestMatches &&
      abiMatches &&
      ffiInitialized &&
      smokeLayoutPassed;
}

abstract interface class MuseIofficeWordRuntimeSession {
  String get sessionRef;
  String get surfaceInstanceRef;
  Future<void> focus();
  Future<void> dispose();
}

abstract interface class MuseIofficeWordRuntime {
  Future<MuseIofficeWordHealth> health();
  Future<MuseIofficeWordRuntimeSession> open(
    MuseOpenEngineSessionRequestV1 request,
    MuseCancellationToken cancellation,
  );
}

final class MuseIofficeWordAdapter implements MuseEngineAdapter {
  MuseIofficeWordAdapter({
    required this.runtime,
    required this.admission,
    this.adapterVersion = '1.0.0',
    this.allowInternalEphemeralEdit = false,
  });
  final MuseIofficeWordRuntime runtime;
  final MuseOfficeAdmission admission;
  final String adapterVersion;
  final bool allowInternalEphemeralEdit;
  final _sessions = <String, MuseIofficeWordRuntimeSession>{};
  int get liveSessionCount => _sessions.length;
  @override
  MuseEngineAdapterManifestV1 get manifest => MuseEngineAdapterManifestV1(
    adapterId: 'muse.ioffice.word',
    adapterVersion: adapterVersion,
    engine: const MuseEngineIdentityV1(
      vendor: 'ioffice',
      engineId: 'word',
      engineVersion: '0.1.0',
    ),
    placements: const [MusePlacementKind.desktopLocal],
    platforms: const [MusePlatformV1(os: 'macos', arch: 'arm64')],
    formats: const [
      MuseFormatSupportV1(
        formatId: 'ooxml.word',
        mimeTypes: [
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ],
        extensionsHint: ['docx'],
      ),
    ],
    modes: [
      if (admission.effectiveModes.contains(MuseEngineMode.view))
        MuseEngineMode.view,
      if (allowInternalEphemeralEdit && admission.engineBound)
        MuseEngineMode.ephemeralEdit,
      if (admission.effectiveModes.contains(MuseEngineMode.edit))
        MuseEngineMode.edit,
    ],
    materializations: const [MuseMaterializationKind.bytesHandle],
    contextProviders: const ['page', 'text-selection'],
    capabilities: [
      MuseAdapterCapability.focus,
      MuseAdapterCapability.navigate,
      MuseAdapterCapability.context,
      MuseAdapterCapability.health,
      if (admission.effectiveModes.contains(MuseEngineMode.edit))
        MuseAdapterCapability.commit,
    ],
    risk: const MuseAdapterRiskV1(
      executesProcess: false,
      executesActiveContent: false,
      requiresGpu: false,
    ),
  );
  @override
  Future<MuseProbeResultV1> probe(
    MuseProbeRequestV1 request,
    MuseCancellationToken cancellation,
  ) async {
    cancellation.throwIfCancelled();
    final health = await runtime.health();
    cancellation.throwIfCancelled();
    final correctFormat =
        request.descriptor.format.formatId == 'ooxml.word' &&
        request.descriptor.format.confidence != MuseFormatConfidence.claimed;
    final correctPlatform =
        request.placement.kind == MusePlacementKind.desktopLocal &&
        request.placement.os == health.os &&
        request.placement.arch == health.arch;
    final base =
        admission.engineBound &&
        admission.viewCertified &&
        health.canView &&
        correctFormat &&
        correctPlatform &&
        request.descriptor.security.activeContent != MuseActiveContent.blocked;
    final modes = <MuseEngineMode>[
      if (base) MuseEngineMode.view,
      if (base && allowInternalEphemeralEdit && health.canEditHeap)
        MuseEngineMode.ephemeralEdit,
      if (base &&
          admission.editCertified &&
          admission.exportCertified &&
          health.canExportDocx)
        MuseEngineMode.edit,
    ];
    final requested = request.requestedMode;
    final available =
        base &&
        (requested == MuseRequestedMode.view ||
            requested == MuseRequestedMode.preferEdit && modes.isNotEmpty ||
            requested == MuseRequestedMode.edit &&
                modes.contains(MuseEngineMode.edit));
    return MuseProbeResultV1(
      probeRef: request.probeRef,
      available: available,
      effectiveModes: available ? modes : const [],
      materializationKinds: available
          ? const [MuseMaterializationKind.bytesHandle]
          : const [],
      maxBytes: 128 * 1024 * 1024,
      quality: const MuseProbeQualityV1(
        fidelity: MuseFidelity.nativePartial,
        startupClass: MuseStartupClass.warmMedium,
      ),
      warnings: [
        if (base && !health.canExportDocx) 'SAVE_UNAVAILABLE',
        if (!health.digestMatches) 'ARTIFACT_DIGEST_MISMATCH',
        if (!health.smokeLayoutPassed) 'LAYOUT_SMOKE_FAILED',
        if (!correctPlatform) 'PLATFORM_UNSUPPORTED',
      ],
      probeDigest: '${health.runtimeDigest}:${admission.reasonCode}',
      expiresAt: DateTime.now().millisecondsSinceEpoch + 5000,
    );
  }

  @override
  Future<MuseEngineSessionHandleV1> open(
    MuseOpenEngineSessionRequestV1 request,
    MuseCancellationToken cancellation,
  ) async {
    if (!manifest.modes.contains(request.mode))
      throw const MuseAdapterException('MODE_NOT_ADMITTED', retryable: false);
    if (request.materialization.kind != MuseMaterializationKind.bytesHandle)
      throw const MuseAdapterException(
        'BYTES_HANDLE_REQUIRED',
        retryable: false,
      );
    final session = await runtime.open(request, cancellation);
    cancellation.throwIfCancelled();
    _sessions[session.sessionRef] = session;
    return MuseEngineSessionHandleV1(
      sessionRef: session.sessionRef,
      surfaceInstanceRef: session.surfaceInstanceRef,
      adapterRef: manifest.adapterRef,
      resourceRef: request.resourceRef,
      baseRevision: request.baseRevision,
      mode: request.mode,
      generation: request.generation,
      state: MuseEngineSessionState.ready,
    );
  }

  @override
  Future<void> focus(MuseEngineSessionHandleV1 session) async {
    final target = _sessions[session.sessionRef];
    if (target == null)
      throw const MuseAdapterException('SESSION_NOT_FOUND', retryable: false);
    await target.focus();
  }

  @override
  Future<void> close(
    MuseEngineSessionHandleV1 session, {
    required String reason,
  }) async {
    await _sessions.remove(session.sessionRef)?.dispose();
  }
}

import 'package:muse_engine_adapter/muse_engine_adapter.dart';
import 'package:muse_resource_bridge/muse_resource_bridge.dart';
import 'package:muse_resource_contract/muse_resource_contract.dart';

import 'certification.dart';

final class MuseViewerRuntimeHealth {
  const MuseViewerRuntimeHealth({
    required this.bundleReady,
    required this.workerReady,
    required this.implicitNetworkRequests,
    required this.runtimeDigest,
  });
  final bool bundleReady, workerReady, implicitNetworkRequests;
  final String runtimeDigest;
}

abstract interface class MuseViewerRuntimeSession {
  String get sessionRef;
  String get surfaceInstanceRef;
  Future<void> focus();
  Future<void> destroy();
}

abstract interface class MuseViewerRuntime {
  Future<MuseViewerRuntimeHealth> health();
  Future<MuseViewerRuntimeSession> open(
    MuseOpenEngineSessionRequestV1 request,
    MuseCancellationToken cancellation,
  );
}

final class MuseOpenFileViewerAdapter implements MuseEngineAdapter {
  MuseOpenFileViewerAdapter({
    required this.runtime,
    required this.catalog,
    required this.profile,
    this.adapterVersion = '1.0.0',
  });
  final MuseViewerRuntime runtime;
  final MuseViewerCertificationCatalog catalog;
  final MuseClientCapabilityProfile profile;
  final String adapterVersion;
  final _sessions = <String, MuseViewerRuntimeSession>{};
  int get liveSessionCount => _sessions.length;
  @override
  MuseEngineAdapterManifestV1 get manifest => MuseEngineAdapterManifestV1(
    adapterId: 'muse.viewer.readonly',
    adapterVersion: adapterVersion,
    engine: const MuseEngineIdentityV1(
      vendor: 'open-file-viewer',
      engineId: 'viewer',
      engineVersion: '0.1.45',
    ),
    placements: [profile.placement],
    platforms: [MusePlatformV1(os: _os(profile.end), arch: _arch(profile.end))],
    formats: catalog.effective
        .map(
          (item) => MuseFormatSupportV1(
            formatId: item.formatId,
            mimeTypes: item.mimeTypes,
            extensionsHint: item.extensionsHint,
          ),
        )
        .toList(),
    modes: const [MuseEngineMode.view],
    materializations: profile.allowedMaterializations
        .where(
          (kind) =>
              kind != MuseMaterializationKind.workingCopy &&
              kind != MuseMaterializationKind.readFileHandle,
        )
        .toList(),
    contextProviders: const ['page', 'text-selection'],
    capabilities: const [
      MuseAdapterCapability.focus,
      MuseAdapterCapability.navigate,
      MuseAdapterCapability.context,
      MuseAdapterCapability.health,
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
    final certification = catalog[request.descriptor.format.formatId];
    final health = await runtime.health();
    cancellation.throwIfCancelled();
    final size = request.descriptor.sizeBytes ?? 0;
    final allowed =
        certification != null &&
        certification.state == MuseViewerCertificationState.certified &&
        !certification.requiresNetwork &&
        health.bundleReady &&
        (!certification.requiresWorker || health.workerReady) &&
        !health.implicitNetworkRequests &&
        request.descriptor.security.activeContent !=
            MuseActiveContent.present &&
        request.descriptor.security.activeContent !=
            MuseActiveContent.blocked &&
        size <= certification.maxBytes &&
        size <= profile.maxResourceBytes &&
        request.requestedMode != MuseRequestedMode.edit;
    return MuseProbeResultV1(
      probeRef: request.probeRef,
      available: allowed,
      effectiveModes: allowed ? const [MuseEngineMode.view] : const [],
      materializationKinds: allowed ? manifest.materializations : const [],
      maxBytes: certification?.maxBytes ?? 0,
      quality: const MuseProbeQualityV1(
        fidelity: MuseFidelity.generic,
        startupClass: MuseStartupClass.hotFast,
      ),
      warnings: [
        if (health.implicitNetworkRequests) 'IMPLICIT_NETWORK_BLOCKED',
        if (certification?.state != MuseViewerCertificationState.certified)
          'FORMAT_NOT_CERTIFIED',
        if (size > (certification?.maxBytes ?? 0)) 'RESOURCE_TOO_LARGE',
      ],
      probeDigest:
          '${health.runtimeDigest}:${certification?.formatId ?? 'unsupported'}',
      expiresAt: DateTime.now().millisecondsSinceEpoch + 5000,
    );
  }

  @override
  Future<MuseEngineSessionHandleV1> open(
    MuseOpenEngineSessionRequestV1 request,
    MuseCancellationToken cancellation,
  ) async {
    if (request.mode != MuseEngineMode.view)
      throw const MuseAdapterException('VIEWER_READ_ONLY', retryable: false);
    if (!manifest.materializations.contains(request.materialization.kind))
      throw const MuseAdapterException(
        'MATERIALIZATION_NOT_SUPPORTED',
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
      mode: MuseEngineMode.view,
      generation: request.generation,
      state: MuseEngineSessionState.ready,
    );
  }

  @override
  Future<void> focus(MuseEngineSessionHandleV1 session) async {
    final runtimeSession = _sessions[session.sessionRef];
    if (runtimeSession == null)
      throw const MuseAdapterException('SESSION_NOT_FOUND', retryable: false);
    await runtimeSession.focus();
  }

  @override
  Future<void> close(
    MuseEngineSessionHandleV1 session, {
    required String reason,
  }) async {
    final runtimeSession = _sessions.remove(session.sessionRef);
    await runtimeSession?.destroy();
  }

  static String _os(MuseClientEnd end) => switch (end) {
    MuseClientEnd.desktop => 'macos',
    MuseClientEnd.web => 'web',
    MuseClientEnd.mobile => 'mobile',
  };
  static String _arch(MuseClientEnd end) => switch (end) {
    MuseClientEnd.desktop => 'arm64',
    MuseClientEnd.web => 'wasm32',
    MuseClientEnd.mobile => 'universal',
  };
}

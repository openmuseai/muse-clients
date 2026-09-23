import 'package:muse_engine_adapter/muse_engine_adapter.dart';
import 'package:muse_resource_contract/muse_resource_contract.dart';

import 'admission.dart';
import 'pty.dart';

abstract interface class MuseHelixRuntime {
  Future<MuseHelixRuntimeHealth> health();
  Future<MuseHelixRuntimeSession> spawn(
    MuseOpenEngineSessionRequestV1 request,
    MuseCancellationToken cancellation,
  );
}

final class MuseHelixAdapter implements MuseEngineAdapter {
  MuseHelixAdapter({
    required this.runtime,
    required this.admission,
    this.adapterVersion = '1.0.0',
  });
  final MuseHelixRuntime runtime;
  final MuseHelixAdmission admission;
  final String adapterVersion;
  final _sessions = <String, MuseHelixRuntimeSession>{};
  int get liveSessionCount => _sessions.length;
  @override
  MuseEngineAdapterManifestV1 get manifest => MuseEngineAdapterManifestV1(
    adapterId: 'muse.helix.editor',
    adapterVersion: adapterVersion,
    engine: const MuseEngineIdentityV1(
      vendor: 'helix',
      engineId: 'hx',
      engineVersion: '25.7.1',
    ),
    placements: const [MusePlacementKind.desktopLocal],
    platforms: admission.platforms,
    formats: const [
      MuseFormatSupportV1(
        formatId: 'text.plain',
        mimeTypes: ['text/plain'],
        extensionsHint: ['txt', 'md', 'log'],
      ),
      MuseFormatSupportV1(
        formatId: 'code.source',
        mimeTypes: ['text/plain'],
        extensionsHint: ['rs', 'ts', 'dart', 'py', 'go'],
      ),
    ],
    modes: [
      MuseEngineMode.view,
      if (admission.editAdmitted) MuseEngineMode.edit,
    ],
    materializations: const [MuseMaterializationKind.workingCopy],
    contextProviders: const ['resource', 'focus'],
    capabilities: [
      MuseAdapterCapability.focus,
      MuseAdapterCapability.setActive,
      MuseAdapterCapability.health,
      if (admission.editAdmitted) MuseAdapterCapability.commit,
    ],
    risk: const MuseAdapterRiskV1(
      executesProcess: true,
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
    final platform = admission.platforms.any(
      (item) =>
          item.os == request.placement.os &&
          item.arch == request.placement.arch,
    );
    final format = {
      'text.plain',
      'code.source',
    }.contains(request.descriptor.format.formatId);
    final noBinary =
        request.descriptor.security.activeContent == MuseActiveContent.none;
    final modes = <MuseEngineMode>[
      if (admission.viewAdmitted && health.ready) MuseEngineMode.view,
      if (admission.editAdmitted && health.ready) MuseEngineMode.edit,
    ];
    final available =
        health.ready &&
        platform &&
        format &&
        noBinary &&
        (request.requestedMode != MuseRequestedMode.edit ||
            modes.contains(MuseEngineMode.edit)) &&
        modes.isNotEmpty;
    return MuseProbeResultV1(
      probeRef: request.probeRef,
      available: available,
      effectiveModes: available ? modes : const [],
      materializationKinds: available
          ? const [MuseMaterializationKind.workingCopy]
          : const [],
      maxBytes: 100 * 1024 * 1024,
      quality: const MuseProbeQualityV1(
        fidelity: MuseFidelity.nativeEngine,
        startupClass: MuseStartupClass.coldSlow,
      ),
      warnings: [
        if (!admission.h0Passed) admission.reasonCode,
        if (!health.digestMatches) 'BINARY_DIGEST_MISMATCH',
        if (!health.processTreeControl) 'PROCESS_TREE_UNCONTROLLED',
        if (!platform) 'PLATFORM_UNCERTIFIED',
      ],
      probeDigest: '${health.runtimeDigest}:${admission.reasonCode}',
      expiresAt: DateTime.now().millisecondsSinceEpoch + 3000,
    );
  }

  @override
  Future<MuseEngineSessionHandleV1> open(
    MuseOpenEngineSessionRequestV1 request,
    MuseCancellationToken cancellation,
  ) async {
    if (!manifest.modes.contains(request.mode))
      throw const MuseAdapterException('MODE_NOT_ADMITTED', retryable: false);
    if (request.materialization.kind != MuseMaterializationKind.workingCopy)
      throw const MuseAdapterException(
        'WORKING_COPY_REQUIRED',
        retryable: false,
      );
    final session = await runtime.spawn(request, cancellation);
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

  MuseHelixUserInputGrant grantUserInput(MuseEngineSessionHandleV1 session) {
    if (!_sessions.containsKey(session.sessionRef))
      throw const MuseAdapterException('SESSION_NOT_FOUND', retryable: false);
    return MuseHelixUserInputGrant.issueForUser(
      session.sessionRef,
      session.generation,
    );
  }

  Future<void> sendUserInput(
    MuseEngineSessionHandleV1 session,
    List<int> bytes,
    MuseHelixUserInputGrant grant,
  ) async {
    if (grant.sessionRef != session.sessionRef ||
        grant.generation != session.generation)
      throw const MuseAdapterException(
        'INPUT_AUTHORITY_MISMATCH',
        retryable: false,
      );
    await _sessions[session.sessionRef]?.sendUserInput(bytes, grant);
  }

  Future<void> resize(
    MuseEngineSessionHandleV1 session,
    MuseHelixPtySize size,
  ) async {
    if (size.columns < 1 || size.rows < 1)
      throw const MuseAdapterException('INVALID_PTY_SIZE', retryable: false);
    final target = _sessions[session.sessionRef];
    if (target == null)
      throw const MuseAdapterException('SESSION_NOT_FOUND', retryable: false);
    await target.resize(size);
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
    await _sessions.remove(session.sessionRef)?.terminate();
  }
}

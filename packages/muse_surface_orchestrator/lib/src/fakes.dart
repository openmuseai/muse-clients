import 'dart:async';

import 'package:muse_engine_adapter/muse_engine_adapter.dart';
import 'package:muse_resource_contract/muse_resource_contract.dart';

enum MuseFakeFailurePoint {
  describe,
  materialize,
  probe,
  open,
  focus,
  close,
  revoke,
}

final class MuseFakeResourceGateway implements MuseResourceGateway {
  MuseFakeResourceGateway({
    required this.descriptor,
    this.delay = Duration.zero,
    this.failures = const {},
  });
  final MuseResourceDescriptorV1 descriptor;
  final Duration delay;
  final Set<MuseFakeFailurePoint> failures;
  int describeCalls = 0, materializeCalls = 0, revokeCalls = 0;
  final liveHandles = <String>{};
  var _ids = 0;
  @override
  Future<MuseResourceDescriptorV1> describe(
    String resourceRef,
    MuseCancellationToken cancellation,
  ) async {
    describeCalls++;
    await _step(MuseFakeFailurePoint.describe, cancellation);
    if (resourceRef != descriptor.resourceRef)
      throw const MuseAdapterException('RESOURCE_NOT_FOUND', retryable: false);
    return descriptor;
  }

  @override
  Future<MuseResourceMaterializationV1> materialize({
    required MuseResourceDescriptorV1 descriptor,
    required String consumerAdapterRef,
    required MuseMaterializationKind kind,
    required MuseAccessMode accessMode,
    required MuseCancellationToken cancellation,
  }) async {
    materializeCalls++;
    await _step(MuseFakeFailurePoint.materialize, cancellation);
    final ref = 'fake.materialization.${++_ids}';
    liveHandles.add(ref);
    return MuseResourceMaterializationV1(
      handleRef: ref,
      resourceRef: descriptor.resourceRef,
      revision: descriptor.revision,
      consumerAdapterRef: consumerAdapterRef,
      kind: kind,
      accessMode: accessMode,
      expiresAt: DateTime.now().millisecondsSinceEpoch + 60000,
      sizeBytes: descriptor.sizeBytes,
    );
  }

  @override
  Future<void> revoke(String handleRef) async {
    revokeCalls++;
    if (failures.contains(MuseFakeFailurePoint.revoke))
      throw const MuseAdapterException('FAKE_REVOKE_FAILED');
    liveHandles.remove(handleRef);
  }

  Future<void> _step(
    MuseFakeFailurePoint point,
    MuseCancellationToken cancellation,
  ) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    cancellation.throwIfCancelled();
    if (failures.contains(point))
      throw MuseAdapterException('FAKE_${point.name.toUpperCase()}_FAILED');
  }
}

final class MuseFakeSurface {
  const MuseFakeSurface(this.session);
  final MuseEngineSessionHandleV1 session;
}

final class MuseFakeEngineAdapter implements MuseEngineAdapter {
  MuseFakeEngineAdapter({
    required this.manifest,
    this.delay = Duration.zero,
    this.failures = const {},
    this.lateGenerationOffset = 0,
    this.available = true,
    this.quality = const MuseProbeQualityV1(
      fidelity: MuseFidelity.nativePartial,
      startupClass: MuseStartupClass.hotFast,
    ),
  });
  @override
  final MuseEngineAdapterManifestV1 manifest;
  final Duration delay;
  final Set<MuseFakeFailurePoint> failures;
  final int lateGenerationOffset;
  final bool available;
  final MuseProbeQualityV1 quality;
  int probeCalls = 0, openCalls = 0, focusCalls = 0, closeCalls = 0;
  final surfaces = <String, MuseFakeSurface>{};
  var _ids = 0;
  @override
  Future<MuseProbeResultV1> probe(
    MuseProbeRequestV1 request,
    MuseCancellationToken cancellation,
  ) async {
    probeCalls++;
    await _step(MuseFakeFailurePoint.probe, cancellation);
    return MuseProbeResultV1(
      probeRef: request.probeRef,
      available: available,
      effectiveModes: available ? manifest.modes : const [],
      materializationKinds: available ? manifest.materializations : const [],
      maxBytes: 1024 * 1024 * 1024,
      quality: quality,
      warnings: const [],
      probeDigest: 'fake.${manifest.adapterRef}',
      expiresAt: DateTime.now().millisecondsSinceEpoch + 5000,
    );
  }

  @override
  Future<MuseEngineSessionHandleV1> open(
    MuseOpenEngineSessionRequestV1 request,
    MuseCancellationToken cancellation,
  ) async {
    openCalls++;
    await _step(
      MuseFakeFailurePoint.open,
      cancellation,
      checkAfterDelay: false,
    );
    final id = ++_ids;
    final handle = MuseEngineSessionHandleV1(
      sessionRef: 'fake.session.$id',
      surfaceInstanceRef: 'fake.surface.$id',
      adapterRef: manifest.adapterRef,
      resourceRef: request.resourceRef,
      baseRevision: request.baseRevision,
      mode: request.mode,
      generation: request.generation + lateGenerationOffset,
      state: MuseEngineSessionState.ready,
    );
    surfaces[handle.sessionRef] = MuseFakeSurface(handle);
    return handle;
  }

  @override
  Future<void> focus(MuseEngineSessionHandleV1 session) async {
    focusCalls++;
    if (failures.contains(MuseFakeFailurePoint.focus))
      throw const MuseAdapterException('FAKE_FOCUS_FAILED');
  }

  @override
  Future<void> close(
    MuseEngineSessionHandleV1 session, {
    required String reason,
  }) async {
    closeCalls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    surfaces.remove(session.sessionRef);
    if (failures.contains(MuseFakeFailurePoint.close))
      throw const MuseAdapterException('FAKE_CLOSE_FAILED');
  }

  Future<void> _step(
    MuseFakeFailurePoint point,
    MuseCancellationToken cancellation, {
    bool checkAfterDelay = true,
  }) async {
    cancellation.throwIfCancelled();
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (checkAfterDelay) cancellation.throwIfCancelled();
    if (failures.contains(point))
      throw MuseAdapterException('FAKE_${point.name.toUpperCase()}_FAILED');
  }
}

MuseEngineAdapterManifestV1 museFakeManifest({
  required String adapterId,
  String version = '1.0.0',
  String formatId = 'ooxml.word',
  List<MuseEngineMode> modes = const [MuseEngineMode.view],
  List<MuseMaterializationKind> materializations = const [
    MuseMaterializationKind.bytesHandle,
  ],
}) => MuseEngineAdapterManifestV1(
  adapterId: adapterId,
  adapterVersion: version,
  engine: MuseEngineIdentityV1(
    vendor: 'fake',
    engineId: adapterId,
    engineVersion: version,
    runtimeDigest: 'fake-runtime-$version',
  ),
  placements: const [MusePlacementKind.desktopLocal],
  platforms: const [MusePlatformV1(os: 'macos', arch: 'arm64')],
  formats: [
    MuseFormatSupportV1(
      formatId: formatId,
      mimeTypes: const ['application/octet-stream'],
      extensionsHint: const [],
    ),
  ],
  modes: modes,
  materializations: materializations,
  contextProviders: const [],
  capabilities: const [
    MuseAdapterCapability.focus,
    MuseAdapterCapability.health,
  ],
  risk: const MuseAdapterRiskV1(
    executesProcess: false,
    executesActiveContent: false,
    requiresGpu: false,
  ),
);

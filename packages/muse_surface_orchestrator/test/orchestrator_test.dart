import 'package:flutter_test/flutter_test.dart';
import 'package:muse_engine_adapter/muse_engine_adapter.dart';
import 'package:muse_resource_bridge/muse_resource_bridge.dart';
import 'package:muse_resource_contract/muse_resource_contract.dart';
import 'package:muse_surface_orchestrator/muse_surface_orchestrator.dart';
import 'package:muse_surface_orchestrator/muse_surface_orchestrator_testing.dart';

void main() {
  test(
    '100 duplicate opens share one operation, surface, and terminal receipt',
    () async {
      final fixture = _Fixture();
      final request = fixture.request('preq.duplicate');
      final operations = List.generate(
        100,
        (_) => fixture.orchestrator.request(request),
      );
      expect(operations.toSet(), hasLength(1));
      final receipts = await Future.wait(
        operations.map((operation) => operation.terminal),
      );
      expect(receipts.toSet(), hasLength(1));
      expect(receipts.first.result, MusePresentationResult.opened);
      expect(fixture.resources.describeCalls, 1);
      expect(fixture.adapter.openCalls, 1);
      expect(fixture.orchestrator.activeSessionCount, 1);
      final terminalStatus = fixture.orchestrator.status('preq.duplicate')!;
      expect(
        terminalStatus.decision!.selectedAdapterRef,
        fixture.adapter.manifest.adapterRef,
      );
      expect(terminalStatus.decision!.alternatives, hasLength(1));
      await fixture.orchestrator.closeSession(
        (receipts.first as MusePresentationSuccessReceiptV2).sessionRef,
      );
      expect(fixture.adapter.surfaces, isEmpty);
      expect(fixture.resources.liveHandles, isEmpty);
      expect(fixture.orchestrator.activeSessionCount, 0);
    },
  );

  test('requestRef cannot be reused for a different request', () {
    final fixture = _Fixture();
    fixture.orchestrator.request(fixture.request('same'));
    expect(
      () => fixture.orchestrator.request(
        fixture.request('same', resourceRef: 'resource.other'),
      ),
      throwsA(isA<MuseOrchestratorException>()),
    );
  });

  test(
    'explicit focus reuses the owned surface without materializing again',
    () async {
      final fixture = _Fixture();
      final opened =
          await fixture.orchestrator
                  .request(fixture.request('preq.open'))
                  .terminal
              as MusePresentationSuccessReceiptV2;
      final focusedRequest = MusePresentationRequestV2(
        requestRef: 'preq.focus',
        resourceRef: 'resource.docx.1',
        disposition: MusePresentationDisposition.focus,
        requestedMode: MuseRequestedMode.view,
        placementHint: MusePlacementHint.currentWindow,
        cause: const MusePresentationCauseV2(kind: 'user'),
        requestedAt: 2,
      );
      final focused =
          await fixture.orchestrator.request(focusedRequest).terminal
              as MusePresentationSuccessReceiptV2;
      expect(focused.result, MusePresentationResult.focused);
      expect(focused.sessionRef, opened.sessionRef);
      expect(fixture.resources.materializeCalls, 1);
      expect(fixture.adapter.focusCalls, 1);
      await fixture.orchestrator.closeSession(opened.sessionRef);
    },
  );

  test(
    'cancel wins atomically and late ready generation is disposed',
    () async {
      final fixture = _Fixture(delay: const Duration(milliseconds: 20));
      final operation = fixture.orchestrator.request(
        fixture.request('preq.cancel'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final cancelled = await fixture.orchestrator.cancel('preq.cancel');
      expect(cancelled.result, MusePresentationResult.cancelled);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(
        fixture.orchestrator.status('preq.cancel')!.receipt,
        same(cancelled),
      );
      expect(fixture.adapter.surfaces, isEmpty);
      expect(fixture.resources.liveHandles, isEmpty);
      expect(fixture.orchestrator.activeSessionCount, 0);
      expect(await operation.terminal, same(cancelled));
    },
  );

  test(
    'late-generation session cannot become terminal success and leaks nothing',
    () async {
      final resources = MuseFakeResourceGateway(
        descriptor: _Fixture.descriptor,
      );
      final adapter = MuseFakeEngineAdapter(
        manifest: museFakeManifest(adapterId: 'fake.late'),
        lateGenerationOffset: -1,
      );
      final registry = MuseAdapterRegistry()..register(adapter, generation: 1);
      final orchestrator = MuseSurfaceOrchestrator(
        resources: resources,
        registry: registry,
      );
      final receipt = await orchestrator
          .request(_Fixture.makeRequest('preq.late'))
          .terminal;
      expect(receipt.result, MusePresentationResult.failed);
      expect(adapter.surfaces, isEmpty);
      expect(resources.liveHandles, isEmpty);
      expect(orchestrator.activeSessionCount, 0);
    },
  );

  test(
    'failed primary rolls back and opens fallback with visible receipt',
    () async {
      final resources = MuseFakeResourceGateway(
        descriptor: _Fixture.descriptor,
      );
      final primary = MuseFakeEngineAdapter(
        manifest: museFakeManifest(adapterId: 'fake.primary'),
        failures: const {MuseFakeFailurePoint.open},
        quality: const MuseProbeQualityV1(
          fidelity: MuseFidelity.nativeEngine,
          startupClass: MuseStartupClass.hotFast,
        ),
      );
      final fallback = MuseFakeEngineAdapter(
        manifest: museFakeManifest(adapterId: 'fake.fallback'),
        quality: const MuseProbeQualityV1(
          fidelity: MuseFidelity.generic,
          startupClass: MuseStartupClass.coldSlow,
        ),
      );
      final registry = MuseAdapterRegistry()
        ..register(primary, generation: 1)
        ..register(fallback, generation: 1);
      final orchestrator = MuseSurfaceOrchestrator(
        resources: resources,
        registry: registry,
      );
      final receipt =
          await orchestrator
                  .request(_Fixture.makeRequest('preq.fallback'))
                  .terminal
              as MusePresentationSuccessReceiptV2;
      expect(receipt.result, MusePresentationResult.fallback);
      expect(receipt.selectedAdapterRef, fallback.manifest.adapterRef);
      expect(receipt.warnings, contains('primary-adapter-failed'));
      expect(
        resources.liveHandles,
        hasLength(1),
        reason: 'only winning session owns a materialization',
      );
      await orchestrator.closeSession(receipt.sessionRef);
      expect(resources.liveHandles, isEmpty);
      expect(primary.surfaces, isEmpty);
      expect(fallback.surfaces, isEmpty);
    },
  );

  test(
    '1000 open-close soak returns all resource and surface counters to zero',
    () async {
      final fixture = _Fixture();
      for (var index = 0; index < 1000; index++) {
        final receipt =
            await fixture.orchestrator
                    .request(
                      fixture.request(
                        'preq.soak.$index',
                        resourceRef: 'resource.docx.1',
                      ),
                    )
                    .terminal
                as MusePresentationSuccessReceiptV2;
        await fixture.orchestrator.closeSession(receipt.sessionRef);
      }
      expect(fixture.resources.liveHandles, isEmpty);
      expect(fixture.adapter.surfaces, isEmpty);
      expect(fixture.orchestrator.activeSessionCount, 0);
      expect(fixture.orchestrator.pendingRequestCount, 0);
    },
  );

  test('feature rollout, breaker, latency and leak gates fail closed', () {
    final rollout = MuseEngineRolloutGate(
      adapterModes: {
        'viewer~1': MuseRolloutMode.shadow,
        'helix~1': MuseRolloutMode.cohort,
      },
      cohortActors: {'actor.allowed'},
    );
    expect(rollout.decide('viewer~1', actorRef: 'a').mayOpen, isFalse);
    expect(
      rollout.decide('helix~1', actorRef: 'actor.allowed').mayOpen,
      isTrue,
    );
    expect(rollout.decide('unknown~1', actorRef: 'a').mayProbe, isFalse);

    var now = 0;
    final breaker = MuseAdapterCircuitBreaker(
      failureThreshold: 2,
      cooldown: const Duration(seconds: 1),
      clock: () => now,
    );
    breaker.failure('viewer~1');
    expect(breaker.allows('viewer~1'), isTrue);
    breaker.failure('viewer~1');
    expect(breaker.allows('viewer~1'), isFalse);
    now = 1000;
    expect(breaker.allows('viewer~1'), isTrue);

    final latency = MuseLatencyHistogram()
      ..record(const Duration(milliseconds: 10))
      ..record(const Duration(milliseconds: 30))
      ..record(const Duration(milliseconds: 20));
    expect(latency.percentile(.95), const Duration(milliseconds: 30));
    const MuseLeakSnapshot(
      pendingRequests: 0,
      sessions: 0,
      materializations: 0,
      surfaces: 0,
    ).verifyZero();
    expect(
      () => const MuseLeakSnapshot(
        pendingRequests: 0,
        sessions: 1,
        materializations: 0,
        surfaces: 0,
      ).verifyZero(),
      throwsStateError,
    );
  });

  test(
    'neutral Host Bridge request/status drives fake Surface end to end',
    () async {
      final fixture = _Fixture();
      final service = MusePresentationHostService(fixture.orchestrator);
      MusePresentationBridgeEnvelope envelope(
        String wireRef,
        MusePresentationBridgeMethod method,
        MusePresentationBridgePayload payload,
      ) => MusePresentationBridgeEnvelope(
        requestId: wireRef,
        method: method,
        workspaceRef: 'workspace.1',
        actorRef: 'actor.1',
        payload: payload,
      );
      final accepted = await service.handle(
        envelope(
          'wire.1',
          MusePresentationBridgeMethod.request,
          MuseBridgeRequestPayload(fixture.request('preq.bridge')),
        ),
      );
      expect(accepted.phase, MusePresentationPhase.accepted);
      await fixture.orchestrator
          .request(fixture.request('preq.bridge'))
          .terminal;
      final terminal = await service.handle(
        envelope(
          'wire.2',
          MusePresentationBridgeMethod.status,
          const MuseBridgeStatusPayload('preq.bridge'),
        ),
      );
      expect(terminal.terminal, isTrue);
      expect(terminal.receipt!.result, MusePresentationResult.opened);
      expect(
        terminal.decision!.selectedAdapterRef,
        fixture.adapter.manifest.adapterRef,
      );
      await fixture.orchestrator.closeSession(
        (terminal.receipt! as MusePresentationSuccessReceiptV2).sessionRef,
      );
    },
  );
}

final class _Fixture {
  _Fixture({Duration delay = Duration.zero})
    : resources = MuseFakeResourceGateway(descriptor: descriptor, delay: delay),
      adapter = MuseFakeEngineAdapter(
        manifest: museFakeManifest(adapterId: 'fake.word'),
        delay: delay,
      ) {
    registry.register(adapter, generation: 1);
    orchestrator = MuseSurfaceOrchestrator(
      resources: resources,
      registry: registry,
    );
  }
  static const descriptor = MuseResourceDescriptorV1(
    resourceRef: 'resource.docx.1',
    revision: 'rev.docx.1',
    displayName: 'Spec.docx',
    mediaType:
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    format: MuseResourceFormat(
      formatId: 'ooxml.word',
      confidence: MuseFormatConfidence.verified,
    ),
    capabilities: [
      MuseResourceCapability.describe,
      MuseResourceCapability.materialize,
    ],
    security: MuseResourceSecurity(
      classification: MuseSecurityClassification.internal,
      activeContent: MuseActiveContent.none,
    ),
    sizeBytes: 42,
  );
  final MuseFakeResourceGateway resources;
  final MuseFakeEngineAdapter adapter;
  final MuseAdapterRegistry registry = MuseAdapterRegistry();
  late final MuseSurfaceOrchestrator orchestrator;
  MusePresentationRequestV2 request(
    String ref, {
    String resourceRef = 'resource.docx.1',
  }) => makeRequest(ref, resourceRef: resourceRef);
  static MusePresentationRequestV2 makeRequest(
    String ref, {
    String resourceRef = 'resource.docx.1',
  }) => MusePresentationRequestV2(
    requestRef: ref,
    resourceRef: resourceRef,
    disposition: MusePresentationDisposition.open,
    requestedMode: MuseRequestedMode.view,
    placementHint: MusePlacementHint.currentWindow,
    cause: const MusePresentationCauseV2(kind: 'user'),
    requestedAt: 1,
  );
}

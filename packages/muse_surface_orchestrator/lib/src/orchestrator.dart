import 'dart:async';
import 'dart:convert';

import 'package:muse_engine_adapter/muse_engine_adapter.dart';
import 'package:muse_resource_contract/muse_resource_contract.dart';

import 'saga.dart';

enum MusePresentationPhase {
  accepted,
  describing,
  probing,
  materializing,
  opening,
  terminal,
}

final class MusePresentationStatus {
  const MusePresentationStatus({
    required this.requestRef,
    required this.phase,
    this.attemptRef,
    this.decision,
    this.receipt,
  });
  final String requestRef;
  final MusePresentationPhase phase;
  final String? attemptRef;
  final MuseRouteDecisionV2? decision;
  final MusePresentationReceiptV2? receipt;
}

final class MusePresentationOperation {
  MusePresentationOperation._(this.request, this._terminal);
  final MusePresentationRequestV2 request;
  final Completer<MusePresentationReceiptV2> _terminal;
  Future<MusePresentationReceiptV2> get terminal => _terminal.future;
}

final class MuseOrchestratorException implements Exception {
  const MuseOrchestratorException(this.code);
  final String code;
  @override
  String toString() => 'MuseOrchestratorException($code)';
}

final class MuseSurfaceOrchestrator {
  MuseSurfaceOrchestrator({
    required MuseResourceGateway resources,
    required MuseAdapterRegistry registry,
    MuseProbeCoordinator? probes,
    MuseEngineRouter? router,
    MuseRoutePolicy Function(MusePresentationRequestV2 request)? policyFor,
    MuseProbePlacementV1 Function(MusePresentationRequestV2 request)?
    placementFor,
    String Function(MusePresentationRequestV2 request)? windowRefFor,
    int Function()? clock,
    String Function(String prefix)? idFactory,
  }) : _resources = resources,
       _registry = registry,
       _probes = probes ?? MuseProbeCoordinator(),
       _router = router ?? const MuseEngineRouter(),
       _policyFor =
           policyFor ?? ((_) => const MuseRoutePolicy(revision: 'default')),
       _placementFor = placementFor ?? _desktopPlacement,
       _windowRefFor = windowRefFor ?? ((_) => 'window.primary'),
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
       _idFactory = idFactory ?? _defaultId;
  final MuseResourceGateway _resources;
  final MuseAdapterRegistry _registry;
  final MuseProbeCoordinator _probes;
  final MuseEngineRouter _router;
  final MuseRoutePolicy Function(MusePresentationRequestV2 request) _policyFor;
  final MuseProbePlacementV1 Function(MusePresentationRequestV2 request)
  _placementFor;
  final String Function(MusePresentationRequestV2 request) _windowRefFor;
  final int Function() _clock;
  final String Function(String prefix) _idFactory;
  final _records = <String, _RequestRecord>{};
  final _sessions = <String, _OwnedSession>{};
  final _sessionByResource = <String, String>{};
  var _generation = 0;
  var _disposed = false;
  static var _ids = 0;
  static String _defaultId(String prefix) => '$prefix.${++_ids}';

  int get requestCount => _records.length;
  int get activeSessionCount => _sessions.length;
  int get pendingRequestCount => _records.values
      .where((record) => record.status.phase != MusePresentationPhase.terminal)
      .length;
  int get ownedHandleCount => _sessions.length;

  MusePresentationOperation request(MusePresentationRequestV2 request) {
    if (_disposed)
      throw const MuseOrchestratorException('ORCHESTRATOR_DISPOSED');
    final fingerprint = jsonEncode(request.toJson());
    final existing = _records[request.requestRef];
    if (existing != null) {
      if (existing.fingerprint != fingerprint)
        throw const MuseOrchestratorException('REQUEST_REF_REUSED');
      return existing.operation;
    }
    final terminal = Completer<MusePresentationReceiptV2>();
    final operation = MusePresentationOperation._(request, terminal);
    final record = _RequestRecord(
      operation: operation,
      fingerprint: fingerprint,
      cancellation: MuseCancellationToken(),
      generation: ++_generation,
      status: MusePresentationStatus(
        requestRef: request.requestRef,
        phase: MusePresentationPhase.accepted,
      ),
    );
    _records[request.requestRef] = record;
    scheduleMicrotask(() => _run(record));
    return operation;
  }

  MusePresentationStatus? status(String requestRef) =>
      _records[requestRef]?.status;

  Future<MusePresentationReceiptV2> cancel(String requestRef) async {
    final record = _records[requestRef];
    if (record == null)
      throw const MuseOrchestratorException('REQUEST_NOT_FOUND');
    record.cancellation.cancel();
    if (record.status.phase != MusePresentationPhase.terminal) {
      _commit(
        record,
        _failure(
          record,
          result: MusePresentationResult.cancelled,
          errorCode: 'CANCELLED',
          retryable: false,
        ),
      );
    }
    return record.operation.terminal;
  }

  Future<void> closeSession(
    String sessionRef, {
    String reason = 'user-close',
  }) async {
    final owned = _sessions.remove(sessionRef);
    if (owned == null) return;
    if (_sessionByResource[owned.handle.resourceRef] == sessionRef)
      _sessionByResource.remove(owned.handle.resourceRef);
    try {
      await owned.adapter.close(owned.handle, reason: reason);
    } finally {
      await _resources.revoke(owned.materializationRef);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final record in _records.values.where(
      (item) => item.status.phase != MusePresentationPhase.terminal,
    )) {
      record.cancellation.cancel();
      _commit(
        record,
        _failure(
          record,
          result: MusePresentationResult.cancelled,
          errorCode: 'ORCHESTRATOR_DISPOSED',
          retryable: false,
        ),
      );
    }
    for (final ref in _sessions.keys.toList()) {
      await closeSession(ref, reason: 'orchestrator-dispose');
    }
  }

  Future<void> _run(_RequestRecord record) async {
    final request = record.operation.request;
    try {
      record.cancellation.throwIfCancelled();
      final existingRef = _sessionByResource[request.resourceRef];
      final existing = existingRef == null ? null : _sessions[existingRef];
      if (existing != null &&
          request.disposition == MusePresentationDisposition.focus) {
        await existing.adapter.focus(existing.handle);
        record.cancellation.throwIfCancelled();
        _commit(
          record,
          _success(
            record,
            attemptRef: _idFactory('attempt'),
            result: MusePresentationResult.focused,
            mode: existing.handle.mode,
            adapterRef: existing.handle.adapterRef,
            resourceRef: existing.handle.resourceRef,
            revision: existing.handle.baseRevision,
            session: existing.handle,
            warnings: const [],
          ),
        );
        return;
      }
      _phase(record, MusePresentationPhase.describing);
      final descriptor = await _resources.describe(
        request.resourceRef,
        record.cancellation,
      );
      record.cancellation.throwIfCancelled();
      final placement = _placementFor(request);
      final registrations = _registry.candidates(
        formatId: descriptor.format.formatId,
        os: placement.os,
        arch: placement.arch,
        placement: _wirePlacement(placement.kind),
      );
      if (registrations.isEmpty) {
        _commit(
          record,
          _failure(
            record,
            result: MusePresentationResult.unsupported,
            errorCode: 'NO_ADAPTER',
            retryable: false,
          ),
        );
        return;
      }
      _phase(record, MusePresentationPhase.probing);
      final policy = _policyFor(request);
      final outcomes = await _probes.probeAll(
        registrations: registrations,
        requestFor: (registration) => MuseProbeRequestV1(
          probeRef: _idFactory('probe'),
          descriptor: MuseProbeDescriptorV1(
            resourceRef: descriptor.resourceRef,
            revision: descriptor.revision,
            format: descriptor.format,
            sizeBytes: descriptor.sizeBytes,
            security: descriptor.security,
          ),
          placement: placement,
          requestedMode: request.requestedMode,
          policyRevision: policy.revision,
          deadlineAt: _clock() + 2000,
          cancellationRef: _idFactory('cancel'),
        ),
        cancellation: record.cancellation,
      );
      final remaining = [...outcomes];
      var failedAttempts = 0;
      String? lastAttemptError;
      while (remaining.isNotEmpty) {
        record.cancellation.throwIfCancelled();
        final selection = _router.select(
          outcomes: remaining,
          requestedMode: request.requestedMode,
          policy: policy,
        );
        if (selection == null) break;
        final attemptRef = _idFactory('attempt');
        final decision = MuseRouteDecisionV2(
          decisionRef: _idFactory('route'),
          requestRef: request.requestRef,
          attemptRef: attemptRef,
          selectedAdapterRef: selection.registration.adapterRef,
          effectiveMode: MuseEffectiveMode.values.byName(
            selection.effectiveMode.name,
          ),
          reasonCodes: selection.reasonCodes,
          alternatives: selection.candidates,
          decidedAt: _clock(),
        );
        record.status = MusePresentationStatus(
          requestRef: request.requestRef,
          phase: MusePresentationPhase.materializing,
          attemptRef: attemptRef,
          decision: decision,
        );
        final saga = MuseOpenSaga();
        try {
          final kind = selection.probe.materializationKinds.first;
          final materialization = await _resources.materialize(
            descriptor: descriptor,
            consumerAdapterRef: selection.registration.adapterRef,
            kind: kind,
            accessMode: selection.effectiveMode == MuseEngineMode.edit
                ? MuseAccessMode.readWrite
                : MuseAccessMode.read,
            cancellation: record.cancellation,
          );
          Future<void> revoke() => _resources.revoke(materialization.handleRef);
          saga.own(revoke);
          record.cancellation.throwIfCancelled();
          _phase(record, MusePresentationPhase.opening, attemptRef: attemptRef);
          final open = MuseOpenEngineSessionRequestV1(
            requestRef: request.requestRef,
            attemptRef: attemptRef,
            resourceRef: descriptor.resourceRef,
            baseRevision: descriptor.revision,
            mode: selection.effectiveMode,
            materialization: MuseOpenMaterializationV1(
              kind: materialization.kind,
              handleRef: materialization.handleRef,
              expiresAt: materialization.expiresAt,
            ),
            surface: MuseOpenSurfaceV1(
              windowRef: _windowRefFor(request),
              placement: _surfacePlacement(request.placementHint),
              reuse: 'compatible',
            ),
            generation: record.generation,
            anchorHint: request.anchorHint,
          );
          final handle = await selection.registration.adapter.open(
            open,
            record.cancellation,
          );
          Future<void> close() => selection.registration.adapter.close(
            handle,
            reason: 'open-saga-rollback',
          );
          saga.own(close);
          record.cancellation.throwIfCancelled();
          _validateHandle(open, selection.registration.adapterRef, handle);
          final owned = _OwnedSession(
            adapter: selection.registration.adapter,
            handle: handle,
            materializationRef: materialization.handleRef,
          );
          _sessions[handle.sessionRef] = owned;
          _sessionByResource[handle.resourceRef] = handle.sessionRef;
          saga.release(close);
          saga.release(revoke);
          final warnings = [
            ...selection.probe.warnings,
            if (failedAttempts > 0) 'primary-adapter-failed',
          ];
          _commit(
            record,
            _success(
              record,
              attemptRef: attemptRef,
              result: failedAttempts == 0
                  ? MusePresentationResult.opened
                  : MusePresentationResult.fallback,
              mode: handle.mode,
              adapterRef: handle.adapterRef,
              resourceRef: handle.resourceRef,
              revision: handle.baseRevision,
              session: handle,
              warnings: warnings,
            ),
          );
          return;
        } catch (error) {
          failedAttempts++;
          lastAttemptError = error is MuseAdapterException
              ? error.code
              : 'ADAPTER_OPEN_FAILED';
          remaining.removeWhere(
            (outcome) => outcome.registration.key == selection.registration.key,
          );
          if (error is MuseAdapterException && !error.retryable) rethrow;
        } finally {
          await saga.close();
        }
      }
      _commit(
        record,
        _failure(
          record,
          result: failedAttempts == 0
              ? MusePresentationResult.unsupported
              : MusePresentationResult.failed,
          errorCode: lastAttemptError ?? 'NO_VIABLE_ROUTE',
          retryable: failedAttempts > 0,
        ),
      );
    } on MuseAdapterException catch (error) {
      _commit(
        record,
        _failure(
          record,
          result: error.code == 'CANCELLED'
              ? MusePresentationResult.cancelled
              : MusePresentationResult.failed,
          errorCode: error.code,
          retryable: error.retryable,
        ),
      );
    } catch (_) {
      _commit(
        record,
        _failure(
          record,
          result: MusePresentationResult.failed,
          errorCode: 'OPEN_FAILED',
          retryable: true,
        ),
      );
    }
  }

  void _phase(
    _RequestRecord record,
    MusePresentationPhase phase, {
    String? attemptRef,
  }) {
    if (record.status.phase == MusePresentationPhase.terminal) return;
    record.status = MusePresentationStatus(
      requestRef: record.operation.request.requestRef,
      phase: phase,
      attemptRef: attemptRef ?? record.status.attemptRef,
      decision: record.status.decision,
    );
  }

  void _commit(_RequestRecord record, MusePresentationReceiptV2 receipt) {
    if (record.status.phase == MusePresentationPhase.terminal) return;
    record.status = MusePresentationStatus(
      requestRef: record.operation.request.requestRef,
      phase: MusePresentationPhase.terminal,
      attemptRef: receipt.attemptRef,
      decision: record.status.decision,
      receipt: receipt,
    );
    if (!record.operation._terminal.isCompleted)
      record.operation._terminal.complete(receipt);
  }

  MusePresentationFailureReceiptV2 _failure(
    _RequestRecord record, {
    required MusePresentationResult result,
    required String errorCode,
    required bool retryable,
  }) => MusePresentationFailureReceiptV2(
    receiptRef: _idFactory('receipt'),
    requestRef: record.operation.request.requestRef,
    attemptRef: record.status.attemptRef ?? _idFactory('attempt'),
    completedAt: _clock(),
    traceRef: _idFactory('trace'),
    result: result,
    errorCode: errorCode,
    retryable: retryable,
  );
  MusePresentationSuccessReceiptV2 _success(
    _RequestRecord record, {
    required String attemptRef,
    required MusePresentationResult result,
    required MuseEngineMode mode,
    required String adapterRef,
    required String resourceRef,
    required String revision,
    required MuseEngineSessionHandleV1 session,
    required List<String> warnings,
  }) => MusePresentationSuccessReceiptV2(
    receiptRef: _idFactory('receipt'),
    requestRef: record.operation.request.requestRef,
    attemptRef: attemptRef,
    completedAt: _clock(),
    traceRef: _idFactory('trace'),
    result: result,
    effectiveMode: MuseEffectiveMode.values.byName(mode.name),
    selectedAdapterRef: adapterRef,
    resourceRef: resourceRef,
    revision: revision,
    sessionRef: session.sessionRef,
    surfaceInstanceRef: session.surfaceInstanceRef,
    warnings: warnings,
  );
  void _validateHandle(
    MuseOpenEngineSessionRequestV1 open,
    String adapterRef,
    MuseEngineSessionHandleV1 handle,
  ) {
    if (handle.generation != open.generation)
      throw const MuseAdapterException('LATE_GENERATION', retryable: true);
    if (handle.adapterRef != adapterRef ||
        handle.resourceRef != open.resourceRef ||
        handle.baseRevision != open.baseRevision)
      throw const MuseAdapterException(
        'SESSION_OWNERSHIP_MISMATCH',
        retryable: false,
      );
    if (!{
      MuseEngineSessionState.ready,
      MuseEngineSessionState.focused,
      MuseEngineSessionState.background,
    }.contains(handle.state))
      throw const MuseAdapterException('SESSION_NOT_READY', retryable: true);
  }

  static MuseProbePlacementV1 _desktopPlacement(
    MusePresentationRequestV2 request,
  ) => const MuseProbePlacementV1(
    kind: MusePlacementKind.desktopLocal,
    os: 'macos',
    arch: 'arm64',
    memoryBudgetBytes: 1024 * 1024 * 1024,
    gpu: true,
  );
  String _wirePlacement(MusePlacementKind kind) => switch (kind) {
    MusePlacementKind.desktopLocal => 'desktop-local',
    MusePlacementKind.webRemote => 'web-remote',
    MusePlacementKind.mobileRemote => 'mobile-remote',
  };
  String _surfacePlacement(MusePlacementHint hint) => switch (hint) {
    MusePlacementHint.currentWindow => 'main',
    MusePlacementHint.newWindow => 'floating',
    MusePlacementHint.sidePanel => 'side-panel',
    MusePlacementHint.background => 'background',
  };
}

final class _RequestRecord {
  _RequestRecord({
    required this.operation,
    required this.fingerprint,
    required this.cancellation,
    required this.generation,
    required this.status,
  });
  final MusePresentationOperation operation;
  final String fingerprint;
  final MuseCancellationToken cancellation;
  final int generation;
  MusePresentationStatus status;
}

final class _OwnedSession {
  const _OwnedSession({
    required this.adapter,
    required this.handle,
    required this.materializationRef,
  });
  final MuseEngineAdapter adapter;
  final MuseEngineSessionHandleV1 handle;
  final String materializationRef;
}

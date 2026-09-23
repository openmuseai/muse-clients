import 'dart:async';
import 'dart:collection';

import 'package:muse_resource_contract/muse_resource_contract.dart';

import 'adapter.dart';
import 'registry.dart';

final class MuseProbeOutcome {
  const MuseProbeOutcome({
    required this.registration,
    this.result,
    this.errorCode,
  });
  final MuseAdapterRegistration registration;
  final MuseProbeResultV1? result;
  final String? errorCode;
}

final class MuseProbeCoordinator {
  MuseProbeCoordinator({
    this.concurrency = 4,
    this.maxCacheTtl = const Duration(seconds: 5),
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    if (concurrency < 1) throw ArgumentError.value(concurrency, 'concurrency');
  }
  final int concurrency;
  final Duration maxCacheTtl;
  final int Function() _clock;
  final _cache = <String, _CachedProbe>{};

  int get cacheEntries => _cache.length;
  void clear() => _cache.clear();

  Future<List<MuseProbeOutcome>> probeAll({
    required List<MuseAdapterRegistration> registrations,
    required MuseProbeRequestV1 Function(MuseAdapterRegistration registration)
    requestFor,
    required MuseCancellationToken cancellation,
  }) async {
    final queue = Queue<MuseAdapterRegistration>.of(registrations);
    final outcomes = <MuseProbeOutcome>[];
    Future<void> worker() async {
      while (queue.isNotEmpty && !cancellation.isCancelled) {
        final registration = queue.removeFirst();
        final request = requestFor(registration);
        final key = _cacheKey(registration, request);
        final cached = _cache[key];
        if (cached != null && cached.expiresAt > _clock()) {
          outcomes.add(
            MuseProbeOutcome(
              registration: registration,
              result: _withProbeRef(cached.result, request.probeRef),
            ),
          );
          continue;
        }
        try {
          cancellation.throwIfCancelled();
          final result = await registration.adapter.probe(
            request,
            cancellation,
          );
          cancellation.throwIfCancelled();
          if (result.probeRef != request.probeRef)
            throw const MuseAdapterException('PROBE_REF_MISMATCH');
          final expiresAt =
              result.expiresAt < _clock() + maxCacheTtl.inMilliseconds
              ? result.expiresAt
              : _clock() + maxCacheTtl.inMilliseconds;
          if (expiresAt > _clock())
            _cache[key] = _CachedProbe(result, expiresAt);
          outcomes.add(
            MuseProbeOutcome(registration: registration, result: result),
          );
        } on MuseAdapterException catch (error) {
          outcomes.add(
            MuseProbeOutcome(registration: registration, errorCode: error.code),
          );
        } catch (_) {
          outcomes.add(
            MuseProbeOutcome(
              registration: registration,
              errorCode: 'PROBE_FAILED',
            ),
          );
        }
      }
    }

    await Future.wait(
      List.generate(
        concurrency < registrations.length ? concurrency : registrations.length,
        (_) => worker(),
      ),
    );
    if (cancellation.isCancelled)
      throw const MuseAdapterException('CANCELLED', retryable: false);
    outcomes.sort(
      (a, b) => a.registration.adapterRef.compareTo(b.registration.adapterRef),
    );
    return outcomes;
  }

  String _cacheKey(
    MuseAdapterRegistration registration,
    MuseProbeRequestV1 request,
  ) {
    final manifest = registration.adapter.manifest;
    final placement = request.placement;
    return [
      registration.adapterRef,
      registration.generation,
      manifest.engine.runtimeDigest ?? manifest.engine.engineVersion,
      request.descriptor.resourceRef,
      request.descriptor.revision,
      request.descriptor.format.formatId,
      placement.kind.name,
      placement.os,
      placement.arch,
      placement.memoryBudgetBytes,
      placement.gpu,
      request.requestedMode.name,
      request.policyRevision,
    ].join('|');
  }

  MuseProbeResultV1 _withProbeRef(MuseProbeResultV1 value, String probeRef) =>
      MuseProbeResultV1(
        probeRef: probeRef,
        available: value.available,
        effectiveModes: value.effectiveModes,
        materializationKinds: value.materializationKinds,
        maxBytes: value.maxBytes,
        quality: value.quality,
        warnings: value.warnings,
        probeDigest: value.probeDigest,
        expiresAt: value.expiresAt,
      );
}

final class _CachedProbe {
  const _CachedProbe(this.result, this.expiresAt);
  final MuseProbeResultV1 result;
  final int expiresAt;
}

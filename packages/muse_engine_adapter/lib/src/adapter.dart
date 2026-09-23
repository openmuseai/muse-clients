import 'dart:async';

import 'package:muse_resource_contract/muse_resource_contract.dart';

final class MuseCancellationToken {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  void throwIfCancelled() {
    if (isCancelled)
      throw const MuseAdapterException('CANCELLED', retryable: false);
  }
}

final class MuseAdapterException implements Exception {
  const MuseAdapterException(this.code, {this.retryable = true});
  final String code;
  final bool retryable;
  @override
  String toString() => 'MuseAdapterException($code)';
}

abstract interface class MuseEngineAdapter {
  MuseEngineAdapterManifestV1 get manifest;
  Future<MuseProbeResultV1> probe(
    MuseProbeRequestV1 request,
    MuseCancellationToken cancellation,
  );
  Future<MuseEngineSessionHandleV1> open(
    MuseOpenEngineSessionRequestV1 request,
    MuseCancellationToken cancellation,
  );
  Future<void> focus(MuseEngineSessionHandleV1 session);
  Future<void> close(
    MuseEngineSessionHandleV1 session, {
    required String reason,
  });
}

abstract interface class MuseResourceGateway {
  Future<MuseResourceDescriptorV1> describe(
    String resourceRef,
    MuseCancellationToken cancellation,
  );
  Future<MuseResourceMaterializationV1> materialize({
    required MuseResourceDescriptorV1 descriptor,
    required String consumerAdapterRef,
    required MuseMaterializationKind kind,
    required MuseAccessMode accessMode,
    required MuseCancellationToken cancellation,
  });
  Future<void> revoke(String handleRef);
}

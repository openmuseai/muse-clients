import 'package:muse_resource_contract/muse_resource_contract.dart';

import 'profile.dart';

final class MuseDataPlaneException implements Exception {
  const MuseDataPlaneException(this.code);
  final String code;
  @override
  String toString() => 'MuseDataPlaneException($code)';
}

final class MuseRemoteMaterializationGrant {
  const MuseRemoteMaterializationGrant({
    required this.handleRef,
    required this.resourceRef,
    required this.revision,
    required this.kind,
    required this.accessMode,
    required this.audience,
    required this.origin,
    required this.expiresAt,
    required this.sizeBytes,
    required this.rangeEnabled,
    required this.generation,
  });
  final String handleRef, resourceRef, revision, audience, origin;
  final MuseMaterializationKind kind;
  final MuseAccessMode accessMode;
  final int expiresAt, sizeBytes, generation;
  final bool rangeEnabled;
}

final class MuseDataPlaneBroker {
  MuseDataPlaneBroker({
    required this.profile,
    required this.expectedAudience,
    required Set<String> allowedOrigins,
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
       _allowedOrigins = allowedOrigins.map(_normalizeOrigin).toSet();
  final MuseClientCapabilityProfile profile;
  final String expectedAudience;
  final Set<String> _allowedOrigins;
  final int Function() _clock;
  final _grants = <String, MuseRemoteMaterializationGrant>{};
  int get activeGrantCount => _grants.length;

  void admit(MuseRemoteMaterializationGrant grant) {
    if (grant.generation < 1)
      throw const MuseDataPlaneException('INVALID_GENERATION');
    if (grant.audience != expectedAudience)
      throw const MuseDataPlaneException('AUDIENCE_MISMATCH');
    if (grant.expiresAt <= _clock())
      throw const MuseDataPlaneException('GRANT_EXPIRED');
    if (grant.accessMode != MuseAccessMode.read)
      throw const MuseDataPlaneException('REMOTE_WRITE_DENIED');
    if (!profile.allowedMaterializations.contains(grant.kind))
      throw const MuseDataPlaneException('MATERIALIZATION_NOT_ALLOWED');
    if (grant.sizeBytes > profile.maxResourceBytes)
      throw const MuseDataPlaneException('RESOURCE_TOO_LARGE');
    if (grant.rangeEnabled && !profile.rangeReads)
      throw const MuseDataPlaneException('RANGE_NOT_SUPPORTED');
    final origin = _normalizeOrigin(grant.origin);
    if (!_allowedOrigins.contains(origin))
      throw const MuseDataPlaneException('ORIGIN_MISMATCH');
    final uri = Uri.parse(origin);
    if (profile.end == MuseClientEnd.desktop) {
      if (grant.kind == MuseMaterializationKind.loopbackUrl &&
          (uri.scheme != 'http' || uri.host != '127.0.0.1'))
        throw const MuseDataPlaneException('LOOPBACK_ORIGIN_REQUIRED');
    } else if (uri.scheme != 'https')
      throw const MuseDataPlaneException('HTTPS_REQUIRED');
    final existing = _grants[grant.handleRef];
    if (existing != null &&
        (existing.resourceRef != grant.resourceRef ||
            existing.revision != grant.revision ||
            existing.generation != grant.generation))
      throw const MuseDataPlaneException('HANDLE_REF_REUSED');
    _grants[grant.handleRef] = grant;
  }

  MuseRemoteMaterializationGrant authorize(
    String handleRef, {
    required String resourceRef,
    required int generation,
  }) {
    final grant = _grants[handleRef];
    if (grant == null) throw const MuseDataPlaneException('HANDLE_NOT_FOUND');
    if (grant.expiresAt <= _clock()) {
      _grants.remove(handleRef);
      throw const MuseDataPlaneException('GRANT_EXPIRED');
    }
    if (grant.resourceRef != resourceRef)
      throw const MuseDataPlaneException('RESOURCE_MISMATCH');
    if (grant.generation != generation)
      throw const MuseDataPlaneException('STALE_GENERATION');
    return grant;
  }

  void revoke(String handleRef) => _grants.remove(handleRef);
  void revokeGeneration(int generation) =>
      _grants.removeWhere((_, grant) => grant.generation == generation);
  void sweepExpired() {
    final now = _clock();
    _grants.removeWhere((_, grant) => grant.expiresAt <= now);
  }

  static String _normalizeOrigin(String value) {
    final uri = Uri.parse(value);
    if (!uri.hasScheme ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.isNotEmpty)
      throw const MuseDataPlaneException('INVALID_ORIGIN');
    return uri.origin;
  }
}

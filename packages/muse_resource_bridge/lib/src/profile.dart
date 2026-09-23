import 'package:muse_resource_contract/muse_resource_contract.dart';

enum MuseClientEnd { desktop, web, mobile }

final class MuseClientCapabilityProfile {
  const MuseClientCapabilityProfile({
    required this.end,
    required this.placement,
    required this.allowedMaterializations,
    required this.allowedModes,
    required this.maxResourceBytes,
    required this.memoryBudgetBytes,
    required this.gpu,
    required this.rangeReads,
    required this.pagination,
    required this.maxEnvelopeBytes,
  });
  final MuseClientEnd end;
  final MusePlacementKind placement;
  final Set<MuseMaterializationKind> allowedMaterializations;
  final Set<MuseEngineMode> allowedModes;
  final int maxResourceBytes, memoryBudgetBytes, maxEnvelopeBytes;
  final bool gpu, rangeReads, pagination;

  static const desktop = MuseClientCapabilityProfile(
    end: MuseClientEnd.desktop,
    placement: MusePlacementKind.desktopLocal,
    allowedMaterializations: {
      MuseMaterializationKind.bytesHandle,
      MuseMaterializationKind.readFileHandle,
      MuseMaterializationKind.workingCopy,
      MuseMaterializationKind.loopbackUrl,
      MuseMaterializationKind.streamHandle,
    },
    allowedModes: {
      MuseEngineMode.view,
      MuseEngineMode.ephemeralEdit,
      MuseEngineMode.edit,
    },
    maxResourceBytes: 2 * 1024 * 1024 * 1024,
    memoryBudgetBytes: 1024 * 1024 * 1024,
    gpu: true,
    rangeReads: true,
    pagination: true,
    maxEnvelopeBytes: 64 * 1024,
  );
  static const web = MuseClientCapabilityProfile(
    end: MuseClientEnd.web,
    placement: MusePlacementKind.webRemote,
    allowedMaterializations: {
      MuseMaterializationKind.remoteUrl,
      MuseMaterializationKind.streamHandle,
    },
    allowedModes: {MuseEngineMode.view, MuseEngineMode.ephemeralEdit},
    maxResourceBytes: 512 * 1024 * 1024,
    memoryBudgetBytes: 512 * 1024 * 1024,
    gpu: true,
    rangeReads: true,
    pagination: true,
    maxEnvelopeBytes: 64 * 1024,
  );
  static const mobile = MuseClientCapabilityProfile(
    end: MuseClientEnd.mobile,
    placement: MusePlacementKind.mobileRemote,
    allowedMaterializations: {
      MuseMaterializationKind.remoteUrl,
      MuseMaterializationKind.streamHandle,
    },
    allowedModes: {MuseEngineMode.view},
    maxResourceBytes: 64 * 1024 * 1024,
    memoryBudgetBytes: 192 * 1024 * 1024,
    gpu: false,
    rangeReads: true,
    pagination: true,
    maxEnvelopeBytes: 32 * 1024,
  );
}

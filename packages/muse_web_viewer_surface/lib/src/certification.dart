enum MuseViewerCertificationState { candidate, certified, disabled }

final class MuseViewerFormatCertification {
  const MuseViewerFormatCertification({
    required this.formatId,
    required this.mimeTypes,
    required this.extensionsHint,
    required this.state,
    required this.maxBytes,
    required this.maxDecodedPixels,
    required this.requiresWorker,
    required this.requiresNetwork,
    required this.requiresGpu,
    required this.supportsRange,
    required this.supportsPageContext,
  });
  final String formatId;
  final List<String> mimeTypes, extensionsHint;
  final MuseViewerCertificationState state;
  final int maxBytes, maxDecodedPixels;
  final bool requiresWorker,
      requiresNetwork,
      requiresGpu,
      supportsRange,
      supportsPageContext;
}

final class MuseViewerCertificationCatalog {
  MuseViewerCertificationCatalog(Iterable<MuseViewerFormatCertification> values)
    : _byFormat = {for (final value in values) value.formatId: value};
  final Map<String, MuseViewerFormatCertification> _byFormat;
  MuseViewerFormatCertification? operator [](String formatId) =>
      _byFormat[formatId];
  List<MuseViewerFormatCertification> get effective =>
      _byFormat.values
          .where(
            (value) =>
                value.state == MuseViewerCertificationState.certified &&
                !value.requiresNetwork,
          )
          .toList(growable: false)
        ..sort((a, b) => a.formatId.compareTo(b.formatId));
  static MuseViewerCertificationCatalog
  wave1() => MuseViewerCertificationCatalog(const [
    MuseViewerFormatCertification(
      formatId: 'text.plain',
      mimeTypes: ['text/plain'],
      extensionsHint: ['txt', 'md', 'log'],
      state: MuseViewerCertificationState.certified,
      maxBytes: 16 * 1024 * 1024,
      maxDecodedPixels: 0,
      requiresWorker: false,
      requiresNetwork: false,
      requiresGpu: false,
      supportsRange: true,
      supportsPageContext: false,
    ),
    MuseViewerFormatCertification(
      formatId: 'image.raster',
      mimeTypes: ['image/png', 'image/jpeg', 'image/webp', 'image/gif'],
      extensionsHint: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
      state: MuseViewerCertificationState.certified,
      maxBytes: 64 * 1024 * 1024,
      maxDecodedPixels: 100000000,
      requiresWorker: false,
      requiresNetwork: false,
      requiresGpu: false,
      supportsRange: false,
      supportsPageContext: false,
    ),
    MuseViewerFormatCertification(
      formatId: 'document.pdf',
      mimeTypes: ['application/pdf'],
      extensionsHint: ['pdf'],
      state: MuseViewerCertificationState.certified,
      maxBytes: 512 * 1024 * 1024,
      maxDecodedPixels: 0,
      requiresWorker: true,
      requiresNetwork: false,
      requiresGpu: false,
      supportsRange: true,
      supportsPageContext: true,
    ),
    MuseViewerFormatCertification(
      formatId: 'ooxml.word',
      mimeTypes: [
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      ],
      extensionsHint: ['docx'],
      state: MuseViewerCertificationState.candidate,
      maxBytes: 64 * 1024 * 1024,
      maxDecodedPixels: 0,
      requiresWorker: true,
      requiresNetwork: false,
      requiresGpu: false,
      supportsRange: false,
      supportsPageContext: true,
    ),
    MuseViewerFormatCertification(
      formatId: 'archive.zip',
      mimeTypes: ['application/zip'],
      extensionsHint: ['zip'],
      state: MuseViewerCertificationState.disabled,
      maxBytes: 0,
      maxDecodedPixels: 0,
      requiresWorker: false,
      requiresNetwork: false,
      requiresGpu: false,
      supportsRange: false,
      supportsPageContext: false,
    ),
  ]);
}

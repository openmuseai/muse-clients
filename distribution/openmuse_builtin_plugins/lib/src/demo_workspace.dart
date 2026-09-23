import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';

final class OpenMuseDemoWorkspace {
  const OpenMuseDemoWorkspace({
    required this.rootPath,
    required this.pngPath,
    required this.pdfPath,
    required this.firstTextPath,
    required this.secondTextPath,
  });

  final String rootPath;
  final String pngPath;
  final String pdfPath;
  final String firstTextPath;
  final String secondTextPath;

  List<OpenMuseResource> get resources => [
    OpenMuseResource(
      uri: Uri.file(firstTextPath),
      displayName: 'README.md',
      mediaType: 'text/markdown',
    ),
    OpenMuseResource(
      uri: Uri.file(secondTextPath),
      displayName: 'architecture.md',
      mediaType: 'text/markdown',
    ),
    OpenMuseResource(
      uri: Uri.file(pngPath),
      displayName: 'preview.png',
      mediaType: 'image/png',
    ),
    OpenMuseResource(
      uri: Uri.file(pdfPath),
      displayName: 'specification.pdf',
      mediaType: 'application/pdf',
    ),
    OpenMuseResource(
      uri: Uri.file('$rootPath/platform.native-gate'),
      displayName: 'Native View Gate',
    ),
  ];

  static Future<OpenMuseDemoWorkspace> create() async {
    final root = Directory('${Directory.systemTemp.path}/openmuse-host-gates');
    await root.create(recursive: true);
    final png = File('${root.path}/viewer-sample.png');
    final pdf = File('${root.path}/viewer-sample.pdf');
    final firstText = File('${root.path}/helix-first.md');
    final secondText = File('${root.path}/helix-second.md');
    await png.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL8WQAAAABJRU5ErkJggg==',
      ),
      flush: true,
    );
    await pdf.writeAsBytes(
      _minimalPdf('OpenMuse local viewer PDF'),
      flush: true,
    );
    await firstText.writeAsString(
      '# OpenMuse Helix gate\n\nThis is the first document.\n',
      flush: true,
    );
    await secondText.writeAsString(
      '# Runtime reuse\n\nEach file owns a PTY; returning to a tab reuses its session.\n',
      flush: true,
    );
    return OpenMuseDemoWorkspace(
      rootPath: root.path,
      pngPath: png.path,
      pdfPath: pdf.path,
      firstTextPath: firstText.path,
      secondTextPath: secondText.path,
    );
  }
}

Uint8List _minimalPdf(String text) {
  final escaped = text
      .replaceAll(r'\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)');
  final stream = 'BT /F1 24 Tf 72 720 Td ($escaped) Tj ET';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    '<< /Length ${latin1.encode(stream).length} >>\nstream\n$stream\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  var byteCount = latin1.encode(buffer.toString()).length;
  for (var index = 0; index < objects.length; index++) {
    offsets.add(byteCount);
    final object = '${index + 1} 0 obj\n${objects[index]}\nendobj\n';
    buffer.write(object);
    byteCount += latin1.encode(object).length;
  }
  final xrefOffset = byteCount;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n',
  );
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

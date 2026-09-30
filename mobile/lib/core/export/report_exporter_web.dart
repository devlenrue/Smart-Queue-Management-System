import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'report_exporter.dart';

/// Hands the CSV to the browser as a download.
///
/// There is no documents directory in a tab, and `path_provider` has no web
/// implementation at all, so the desktop behaviour cannot simply be reused.
/// The bytes are still the server's own — this only chooses where they land.
class DownloadReportExporter implements ReportExporter {
  const DownloadReportExporter();

  @override
  Future<String> save(String filename, String contents) async {
    final web.Blob blob = web.Blob(
      <JSAny>[contents.toJS].toJS,
      web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
    );

    final String url = web.URL.createObjectURL(blob);
    final web.HTMLAnchorElement anchor =
        web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = filename;
    anchor.click();
    web.URL.revokeObjectURL(url);

    return 'your browser downloads folder';
  }
}

ReportExporter createPlatformReportExporter() => const DownloadReportExporter();

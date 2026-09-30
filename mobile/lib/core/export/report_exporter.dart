// The platform half is chosen at compile time. Importing `dart:io` from a
// library that `main()` can reach makes the whole program unbuildable for the
// web — `flutter build web` stops with "Dart library 'dart:io' is not
// available on this platform" — even though nothing ever exports a report on
// startup. Keeping the interface here and the implementations behind a
// conditional import is the standard way out.
import 'report_exporter_web.dart' if (dart.library.io) 'report_exporter_io.dart';

/// Where an exported report ends up.
///
/// An interface rather than a bare function so a widget test can export a
/// report without touching a platform channel — `path_provider` needs a real
/// device or a mocked channel, and neither belongs in a test about whether
/// the button works.
abstract class ReportExporter {
  /// Writes [contents] under [filename] and returns a human-readable
  /// destination, which the screen shows so the marker can go and open it.
  Future<String> save(String filename, String contents);
}

/// The exporter for whichever platform this build targets:
/// a file in the documents directory on mobile and desktop, a browser
/// download on the web.
ReportExporter createReportExporter() => createPlatformReportExporter();

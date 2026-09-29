import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where an exported report ends up.
///
/// An interface rather than a bare function so a widget test can export a
/// report without touching a platform channel — `path_provider` needs a real
/// device or a mocked channel, and neither belongs in a test about whether
/// the button works.
abstract class ReportExporter {
  /// Writes [contents] under [filename] and returns the full path, which
  /// the screen shows so the marker can go and open the file.
  Future<String> save(String filename, String contents);
}

/// Saves into the app's documents directory.
///
/// Deliberately not a share sheet: §82 rules out extra platform plugins,
/// and a file on disk is enough to prove the export works — on Android it
/// lands in the app's own storage, on a desktop run it is a normal file in
/// the user's documents folder.
class FileReportExporter implements ReportExporter {
  const FileReportExporter();

  @override
  Future<String> save(String filename, String contents) async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final Directory reports = Directory('${directory.path}/smartqueue-reports');
    if (!await reports.exists()) {
      await reports.create(recursive: true);
    }

    final File file = File('${reports.path}/$filename');
    await file.writeAsString(contents);
    return file.path;
  }
}

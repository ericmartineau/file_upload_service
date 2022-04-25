// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// GruntGenerator
// **************************************************************************

import 'package:logging/logging.dart';
import 'package:logging_config/logging_config.dart';
import 'package:worker_service/work_in_ww.dart';
import 'package:file_upload_service/upload_large_file.dart';

final _log = Logger("gruntUploadLargeFile");
void main() async {
  await configureLogging(
      LogConfig.root(Level.FINE, handler: LoggingHandler.console()));
  _log.info('Configured logging: FINE, console');
  var channel = GruntChannel.create(UploadLargeFile());
  await channel.done;
  _log.info("Job UploadLargeFile is done");
}

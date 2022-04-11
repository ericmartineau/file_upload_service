// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// GruntGenerator
// **************************************************************************

import 'package:logging/logging.dart';
import 'package:logging_config/logging_config.dart';
import 'package:worker_service/work_in_ww.dart';
import 'package:sunny_services/upload_large_file.dart';

final _log = Logger("gruntUploadLargeFile");
void main() async {
  configureLogging(LogConfig.root(Level.INFO, handler: LoggingHandler.dev()));
  var channel = GruntChannel.create(UploadLargeFile());
  await channel.done;
  _log.info("Job UploadLargeFile is done");
}

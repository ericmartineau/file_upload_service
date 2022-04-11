import 'package:flutter/cupertino.dart';
import 'package:pfile/pfile_api.dart';
import 'package:sunny_services/gstorage/gstorage.dart';
import 'package:sunny_services/upload_large_file.dart';

import 'sunny_services_test.dart';

UploadLargeFile newUploadLargeFile() => UploadLargeFile();

Future main() async {
  PFile.initialize();
  initializeGStorageFileLoaders();
  runApp(SunnyServicesTestApp());
}

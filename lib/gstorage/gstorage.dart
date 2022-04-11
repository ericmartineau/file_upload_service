import 'package:pfile_picker/pfile_picker.dart';

export 'gstorage_platform.dart' if (dart.library.io) 'gstorage_native.dart' if (dart.library.js) 'gstorage_web.dart';
export 'gstorage_shared.dart';

var _initialized = false;

void initializeGStorageFileLoaders() {
  if (_initialized != true) {
    _initialized = true;
    PFile.loaders += loadPlatformFile;
  }
}

PFile? loadPlatformFile(dynamic file, {String? name, int? size}) {
  if (file is PlatformFile) {
    return PFile.loaders
        .fileOf(file.bytes ?? file.readStream ?? Uri.parse(file.path), name: name ?? file.path, size: size ?? file.size);
  }
  return null;
}

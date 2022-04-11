import 'dart:async';
import 'dart:io' as io;
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:logging/logging.dart';
import 'package:pfile_picker/pfile_picker.dart';
import 'package:sunny_dart/sunny_dart.dart';
import 'package:sunny_forms/media/media_content_type.dart';
import 'package:sunny_sdk_core/model/progress_tracker.dart';
import 'package:sunny_services/gstorage/gstorage.dart';

final _log = Logger('storage');

ProgressTracker<Uri> doUploadMedia(final dynamic file, MediaContentType contentType,
    {mediaType, required String mediaId, ProgressTracker<Uri>? progress}) {
  initializeGStorageFileLoaders();
  var storageReference = FirebaseStorage.instance.ref().child(getMediaRefUri(mediaId, mediaType));

  final pfile = PFile.of(file);
  var tuple = setupTask(storageReference, pfile!, "image/${file.extension ?? '*'}");
  final _progress = progress ?? ProgressTracker<Uri>.ratio();
  tuple.then((t) {
    StreamSubscription? sub;
    final _ = t.first;
    _.whenComplete(() async {
      final url = await storageReference.getDownloadURL();
      final uri = url.toString().toUri();
      _progress.complete(uri);
      _progress.dispose();
    });
    sub = _.snapshotEvents.listen((event) {
      switch (event.state) {
        case TaskState.paused:
          _log.info("Paused upload for $mediaId");
          break;
        case TaskState.running:
          _progress.update(event.bytesTransferred.toDouble() * 100 / event.totalBytes.toDouble());
          break;
        case TaskState.success:
          sub?.cancel();
          break;
        case TaskState.canceled:
          sub?.cancel();
          break;
        case TaskState.error:
          sub?.cancel();
          _progress.completeError();
          break;
      }
    });
  });

  return _progress;
}

int fileSize(file) {
  if (file is Uint8List) {
    return file.length;
  } else if (file is PlatformFile) {
    return file.size;
  } else if (file is PFile) {
    return file.size;
  } else {
    assert(file is File);
    return (file as File).lengthSync();
  }
}

Future<Tuple<UploadTask, int>> setupTask(Reference storageReference, PFile file, String contentType) async {
  // ignore: deprecated_member_use
  if (file.bytes != null) {
    return Tuple(
      // ignore: deprecated_member_use
      storageReference.putData(file.bytes!),
      file.size,
    );
  } else if (file.path != null) {
    var rawFile = io.File.fromUri(Uri.parse(file.path!));
    return Tuple(storageReference.putFile(rawFile, SettableMetadata(contentType: contentType)), rawFile.lengthSync());
  } else {
    var bytes = await file.awaitData;
    return Tuple(storageReference.putData(bytes, SettableMetadata(contentType: contentType)), file.size);
  }
}

Future<Uri> doGetMediaUri(String mediaId, {mediaType}) async {
  var storageReference = FirebaseStorage.instance.ref().child(getMediaRefUri(mediaId, mediaType));
  return (await storageReference.getDownloadURL()).toUri()!;
}

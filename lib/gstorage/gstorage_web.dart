import 'dart:async';

import 'package:firebase/firebase.dart' as fb;
import 'package:logging/logging.dart';
import 'package:pfile/pfile.dart';
import 'package:sunny_dart/sunny_dart.dart';
import 'package:sunny_forms/media/media_content_type.dart';
import 'package:sunny_sdk_core/model/progress_tracker.dart';

import 'gstorage.dart';

final _log = Logger("storage");
fb.StorageReference? __ref;

fb.StorageReference get _ref {
  return __ref ??= fb.app().storage().ref();
}

Future<Uri> doGetMediaUri(String mediaId, {mediaType}) async {
  var storageReference = _ref.child(getMediaRefUri(mediaId, mediaType));
  final url = await storageReference.getDownloadURL();
  return url;
}

ProgressTracker<Uri> doUploadMedia(final dynamic file, MediaContentType contentType,
    {mediaType, required String mediaId, ProgressTracker<Uri>? progress}) {
  initializeGStorageFileLoaders();
  var storageReference = _ref.child(getMediaRefUri(mediaId, mediaType));

  var pfile = PFile.of(file);
  var tup = setupTask(storageReference, pfile!, "image/jpeg");

  final _progress = progress ?? ProgressTracker<Uri>.ratio();
  tup.then((t) {
    StreamSubscription? sub;
    var uploadTask = t.first;
    sub = uploadTask.onStateChanged.listen((event) {
      switch (event.state) {
        case fb.TaskState.PAUSED:
          _log.info("Paused upload for $mediaId");
          break;
        case fb.TaskState.RUNNING:
          _progress.update(event.bytesTransferred.toDouble() * 100 / event.totalBytes.toDouble());
          break;
        case fb.TaskState.SUCCESS:
          sub?.cancel();
          break;
        case fb.TaskState.CANCELED:
          sub?.cancel();
          break;
        case fb.TaskState.ERROR:
          sub?.cancel();
          _progress.completeError();
          break;
      }
    });
    uploadTask.future.then((_) async {
      final url = await storageReference.getDownloadURL();
      final uri = url.toString().toUri();
      _progress.complete(uri);
      _progress.dispose();
    });
  });

  return _progress;
}

Future<Tuple<fb.UploadTask, int>> setupTask(fb.StorageReference storageReference, PFile file, String contentType) async {
  // ignore: deprecated_member_use
  if (file.bytes != null) {
    return Tuple(
      // ignore: deprecated_member_use
      storageReference.put(file.bytes),
      file.size,
    );
  } else {
    var bytes = await file.awaitData;
    return Tuple(storageReference.put(bytes, fb.UploadMetadata(contentType: contentType)), file.size);
  }
}

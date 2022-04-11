import 'package:sunny_forms/media.dart';
import 'package:sunny_sdk_core/model/progress_tracker.dart';

ProgressTracker<Uri> doUploadMedia(
        final dynamic file, MediaContentType contentType,
        {mediaType, required String mediaId, ProgressTracker<Uri>? progress}) =>
    throw "Not implemented";

Future<Uri> doGetMediaUri(String mediaId, {mediaType}) =>
    throw "Not implemented";

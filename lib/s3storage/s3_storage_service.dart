import 'dart:async';

import 'package:pfile/pfile_api.dart';
import 'package:sunny_dart/sunny_dart.dart';
import 'package:sunny_forms/form_fields/media_service.dart';
import 'package:sunny_forms/media/media_content_type.dart';
import 'package:sunny_forms/sunny_forms.dart';
import 'package:sunny_sdk_core/auth/firebase_api_auth.dart';
import 'package:sunny_sdk_core/model.dart';
import 'package:sunny_services/file_upload/uploads_api.dart';
import 'package:sunny_services/upload_large_file.dart';
import 'package:worker_service/work.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:sunny_services/upload_large_file.grunt.dart' as gm;
//
// if (kDebugMode) 'package:sunny_services/upload_large_file.grunt.dart'
// if (kProfileMode) 'package:sunny_services/upload_large_file.grunt.dart'
// if (kReleaseMode) 'blank.dart';

final gruntMain = gm.main;

const defaultCloudFrontUrl = 'https://sunny-img-hosting.s3.amazonaws.com';

class S3StorageService with LoggingMixin implements IMediaService {
  final String cloudFrontUrl;
  final String baseUrl;
  final IUploadsApi uploads;

  S3StorageService(this.uploads, this.baseUrl)
      : cloudFrontUrl = defaultCloudFrontUrl;

  S3StorageService.ofCloudFront(this.uploads, this.baseUrl,
      {this.cloudFrontUrl = defaultCloudFrontUrl});

  @override
  ProgressTracker<Uri> uploadMedia(
      final dynamic file, MediaContentType contentType,
      {mediaType, String? mediaId, ProgressTracker<Uri>? progress}) {
    var pfile = PFile.of(file);

    final _progress = progress ?? ProgressTracker<Uri>.ratio();

    // Check to see if file already exists first.
    uploads
        .findMedia(
      mediaType: contentType.name,
      filePath: pfile!.name!,
      fileSize: pfile.size,
    )
        .catchError((err) {
      print("No existing media found for ${pfile.name}");
      return null;
    }).then((existing) {
      if (existing != null) {
        var parsedExisting = Uri.tryParse(existing);
        if (parsedExisting != null) {
          print("Found existing media${pfile.name}");
          _progress.complete(parsedExisting);
          return;
        }
      }
      Supervisor.create(UploadLargeFile(), isProduction: kDebugMode != true)
          .then((supervisor) async {
        print("Main thread created supervisor");
        final keyName =
            (await getMediaPath(contentType, mediaId!, mediaType: mediaType))
                .substring(1);
        final mediaUrl =
            await getMediaUri(contentType, mediaId, mediaType: mediaType);
        final freshToken = await FirebaseApiAuth.user!.getIdToken(true);

        try {
          await supervisor.start(
              timeout: 20.seconds,
              params: UploadFileParams.ofPFile(
                file: pfile,
                keyName: keyName,
                apiBasePath: baseUrl,
                mediaType: contentType.fileType,
                mediaUrl: mediaUrl.toString(),
                apiToken: freshToken,
              ));
        } on TimeoutException {
          _progress.completeError(
              "Main thread timed out waiting for supervisor to start");

          supervisor.close().timeout(20.seconds);

          return;
        } catch (error, stack) {
          print("Main thread error getting start signal: $error");
          print(stack);
          rethrow;
        }
        StreamSubscription? _sub;
        _sub = supervisor.onStatus.listen((event) async {
          print(
              "Main thread received status from supervisor: ${event.phase} ${event.percentComplete}");
          switch (event.phase) {
            case WorkPhase.error:
              _progress.completeError(event.error);
              _sub?.cancel();
              break;
            case WorkPhase.stopped:
              _progress.complete(await getMediaUri(contentType, mediaId,
                  mediaType: mediaType));
              _sub?.cancel();
              break;
            default:
              _progress.update(event.percentComplete ?? 0, total: 100.0);
          }
        }, cancelOnError: false);
      });
    });

    return _progress;
  }

  @override
  FutureOr<Uri> getMediaUri(MediaContentType contentType, String mediaId,
      {mediaType}) {
    return mediaUriOf(
      contentType,
      mediaId,
      mediaType: mediaType,
      cloudFrontUrl: this.cloudFrontUrl,
    );
  }

  static Future<Uri> mediaUriOf(MediaContentType contentType, String mediaId,
      {String cloudFrontUrl = defaultCloudFrontUrl, mediaType}) async {
    return Uri.parse([
      cloudFrontUrl,
      contentType.name,
      mediaType?.toString() ?? "default",
      mediaId
    ].whereNotBlank().join("/"));
  }

  FutureOr<String> getMediaPath(MediaContentType contentType, String mediaId,
      {mediaType}) {
    return mediaPathOf(contentType, mediaId, mediaType: mediaType);
  }

  static FutureOr<String> mediaPathOf(
      MediaContentType contentType, String mediaId,
      {mediaType}) {
    return "/${[
      contentType.name,
      mediaType?.toString() ?? "default",
      mediaId
    ].whereNotBlank().join("/")}";
  }
}

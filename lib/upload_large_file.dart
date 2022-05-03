import 'dart:async';

import 'package:buffer/buffer.dart';
import 'package:dartx/dartx.dart';
import 'package:dio/dio.dart';
import 'package:pfile/pfile.dart';
import 'package:semaphore/semaphore.dart';
import 'package:sunny_dart/extensions/lang_extensions.dart';
import 'package:sunny_dart/helpers/logging_mixin.dart';
import 'package:sunny_sdk_core/api/api_client.dart';
import 'package:sunny_sdk_core/api/api_reader.dart';
import 'package:sunny_sdk_core/api/diolib_transport.dart';
import 'package:sunny_sdk_core/auth/bearer.dart';
import 'package:worker_service/work.dart';

import 'file_upload/api/e_tag_response.dart';
import 'file_upload/api/finish_upload.dart';
import 'file_upload/api/start_upload.dart';
import 'file_upload/api/upload_request.dart';
import 'file_upload/api/uploads_api_reader.dart';
import 'file_upload/uploads_api.dart';

// If any flutter dependencies get introduced to any of these imports ^^^ it
// will break the generator.  To troubleshoot, uncomment this @grunt and start
// removing dependencies until you find the offender.

// @grunt()
// class UploadLargeFile with GruntMixin<UploadLargeFile> {
//   @override
//   GruntFactoryFn<UploadLargeFile> get create => newUploadLargeFile;
//
//   @override
//   Future execute(params) {
//     throw UnimplementedError();
//   }
//
//   @override
//   String get key => "upload_large_file";
//
//   @override
//   String? get package => "file_upload_service";
//
//   UploadLargeFile();
// }

class UploadFileParams {
  final PFile file;
  final String? keyName;
  final String? mediaType;
  final String? mediaUrl;
  final String? apiToken;
  final String? apiBasePath;
  final bool? convertAspectRatio;

  UploadFileParams.ofPFile({
    required this.file,
    this.keyName,
    this.mediaType,
    this.mediaUrl,
    this.apiToken,
    this.apiBasePath,
    this.convertAspectRatio = false,
  });

  factory UploadFileParams.fromJson(map) {
    return UploadFileParams.ofPFile(
      file: PFile.of(map['file'])!,
      keyName: map['keyName'] as String?,
      apiToken: map['apiToken'] as String?,
      apiBasePath: map['apiBasePath'] as String?,
      convertAspectRatio: map['convertAspectRatio']?.toString() == "true",
    );
  }

  Map<String, dynamic> toJson() {
    // ignore: unnecessary_cast
    return {
      'file': this.file.file,
      'keyName': this.keyName,
      'apiToken': this.apiToken,
      'apiBasePath': this.apiBasePath,
      'convertAspectRatio': this.convertAspectRatio,
    } as Map<String, dynamic>;
  }
}

@grunt(logLevel: "FINE", logOutput: "console")
class UploadLargeFile with LoggingMixin, GruntMixin<UploadLargeFile> {
  late String uploadId;
  late IUploadsApi uploads;
  late int _currentPart;
  Map<int, int> _bytesProcessed = {};
  var _seen = 0;
  int lastPct = 0;

  @override
  UploadFileParams get params {
    return super.params as UploadFileParams;
  }

  UploadLargeFile();

  @override
  FutureOr doInitialize() async {
    // WidgetsFlutterBinding.ensureInitialized();
    try {
      await PFile.initialize();
    } catch (e) {
      print(e);
    }
    log.info("UploadLargeFile doInitialize()");
    sendUpdate(message: "Initialized files", progress: 5);
  }

  // Check progress
  Future notifyProgress() async {
    final p = _bytesProcessed.values.sum();
    var progress = (_seen + p.toDouble()) * 85 / (params.file.size * 2);
    if (lastPct == progress.round()) return;
    lastPct = progress.round();
    // log.info("Got $progress of ${totalSize.formatNumber()}");

    sendUpdate(progress: lastPct + 10.0);
  }

  @override
  Future execute(dynamic _params) async {
    print("Upload large file execute");
    this.params = _params as UploadFileParams;

    total = params.file.size.toDouble();

    workPhase = WorkPhase.processing;
    sendStatus();

    this.sendUpdate(
        message:
            "file: ${params.file.name} size ${params.file.size.formatBytes()}");
    var pfile = params.file;
    this.sendUpdate(message: "found file: ${pfile}");

    uploads = UploadsApi(
      ApiClient(
        transport: DioLibTransport(basePath: params.apiBasePath!),
        authentication: BearerAuthentication(params.apiToken!),
        serializer: AggregateApiReader(
          PrimitiveApiReader(),
          UploadsApiReader(),
          ApiReader.mmodel(),
        ),
      ),
    );
    // final _progress = progress ?? ProgressTracker<Uri>.ratio();

    String keyName;

    this.sendUpdate(
        message:
            "Starting upload... Total of ${params.file.size.formatBytes()}");
    keyName = params.keyName!;
    StartUpload upload;
    try {
      upload = await uploads.startUpload(
          body: UploadRequest.of(path: keyName),
          mediaParams: params.mediaType == null || params.mediaUrl == null
              ? null
              : {
                  "mediaType": params.mediaType,
                  "fileName": params.file.name,
                  "fileSize": params.file.size,
                  "mediaUrl": params.mediaUrl,
                });
    } catch (e, stack) {
      log.severe(e, stack);
      message = "Failed to start upload: $e";
      rethrow;
    }

    try {
      if (upload.mediaId != null) {
        sendUpdate(message: "Found a duplicate!", progress: 100);
        return;
      }
      uploadId = upload.uploadId!;
      log.info("Started upload $uploadId");
      sendUpdate(message: "Starting to buffer: $uploadId", progress: 10);

      log.info("Starting upload of ${pfile.name}");

      /// 5mb min size
      var uploadSize = 1024 * 1024 * 5;
      _currentPart = 1;

      var _buf = BytesBuffer();
      final _parts = <Future<ETagResponse>>[];

      final locks = LocalSemaphore(3);
      await for (var chunk in pfile.openStream()) {
        if (this.isShuttingDown) {
          return;
        }
        _buf.add(chunk);
        _seen += chunk.length;
        if (_buf.length >= uploadSize) {
          /// upload chunk
          _currentPart = _currentPart + 1;
          final me = _currentPart;
          var _b = _buf.toBytes();
          _buf = BytesBuffer();
          final _comp = Completer<ETagResponse>();
          _parts.add(_comp.future);
          await locks.acquire();
          try {
            log.info("Starting upload ${_currentPart + 1}");
            sendUpdate(
              message: "Buffered enough:  Uploading ${_currentPart - 1}",
              state: {
                "uploadId": uploadId,
                "currentPart": _currentPart,
              },
            );
            final p = await uploadPart(me, _b);
            _comp.complete(p);
          } finally {
            locks.release();
          }
        }
      }

      /// Wait for any pending items before continuing
      final parts = [...(await Future.wait(_parts))];

      /// Take care of the last item
      if (_buf.length > 0) {
        _currentPart = _currentPart + 1;
        final me = _currentPart;
        parts.add(await uploadPart(me, _buf.toBytes()));
      }

      sendUpdate(
          message: "Parts are done!  Now we need to finalize!", progress: 95);
      log.info("Completed uploading ${_parts.length} parts for $uploadId");
      var resp = await uploads.completeUpload(uploadId,
          body: FinishUpload.of(
            keyName: keyName,
            parts: parts,
          ));

      log.info("Completed $uploadId status of ${resp}");
      sendUpdate(message: "Done!");
    } catch (e, s) {
      log.severe(e, s);
      
      rethrow;
    }
  }

  Future<ETagResponse> uploadPart(int me, List<int> chunk) async {
    log.info("  Upload part $me size ${chunk.length}");

    Dio _dio = Dio(
      BaseOptions(baseUrl: params.apiBasePath!, headers: {
        "Authorization": "Bearer ${params.apiToken}",
      }),
    );

    final stream = Stream<List<int>>.fromIterable(
        chunk.chunked(1024 * 1024).map((e) => [...e])).asBroadcastStream();
    var resp = await _dio.post<Map<String, dynamic>>(
      "/uploads/$uploadId/parts",
      data: stream,
      onSendProgress: (completed, outof) async {
        log.info("  Buffered $completed/$outof bytes");
        sendUpdate(message: "Buffered $completed/$outof bytes");
        _bytesProcessed[me] = completed;
        await notifyProgress();
      },
      onReceiveProgress: (completed, outof) async {
        log.info("  Received $completed/$outof bytes");
        sendUpdate(message: "Received $completed/$outof bytes");
      },
      options: Options(
        contentType: "application/octet-stream",
        method: "POST",
        headers: {
          Headers.contentLengthHeader: chunk.length,
          "partnumber": me,
          "pathname": params.keyName,
        },
      ),
    );

    var etag = ETagResponse.fromJson(resp.data);

    message = "Completed upload for part: ${_currentPart - 1}";

    _bytesProcessed[me] = chunk.length;
    notifyProgress();

    log.info(" -> $me: ${etag.partName}");
    return etag;
  }

  /// Override this to customize encoding strategy.  Call next to chain them together,
  /// or just return something custom
  Payload encodePayload(Payload payload, PayloadEncoder next) {
    if (payload.data is UploadFileParams) {
      /// Send over a raw file, mark as 120 so I know what to look for
      return Payload(120, (payload.data as UploadFileParams).toJson());
    } else {
      return next(payload);
    }
  }

  dynamic decodePayload(
      int? contentType, dynamic content, PayloadDecoder next) {
    if (contentType == 120) {
      if (content is UploadFileParams) return content;
      return UploadFileParams.fromJson(content);
    } else {
      return next(contentType, content);
    }
  }

  @override
  GruntFactoryFn<UploadLargeFile> get create => newUploadLargeFile;

  @override
  String get key => "upload_large_file";

  @override
  String get package => "file_upload_service";
}

UploadLargeFile newUploadLargeFile() => UploadLargeFile();

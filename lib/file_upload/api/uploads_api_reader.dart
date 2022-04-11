import 'package:sunny_sdk_core/api/api_exceptions.dart';
import 'package:sunny_sdk_core/api/api_reader.dart';

import 'abort_upload.dart';
import 'e_tag_response.dart';
import 'finish_upload.dart';
import 'start_upload.dart';
import 'upload_request.dart';

class UploadsApiReader extends CollectionAwareApiReader {
  final bool _isStandalone;
  UploadsApiReader() : _isStandalone = false;
  UploadsApiReader.standalone() : _isStandalone = true;

  @override
  Deserializer? findSingleReader(final value, String? targetType) {
    try {
      switch (targetType) {
        case 'AbortUpload':
          return (value) => AbortUpload.fromJson(value);
        case 'ETagResponse':
          return (value) => ETagResponse.fromJson(value);
        case 'FinishUpload':
          return (value) => FinishUpload.fromJson(value);
        case 'StartUpload':
          return (value) => StartUpload.fromJson(value);
        case 'UploadRequest':
          return (value) => UploadRequest.fromJson(value);
        default:
          return _isStandalone != true
              ? null
              : PrimitiveApiReader().getReader(value, targetType);
      }
    } catch (e, stack) {
      throw ApiException.runtimeError(e, stack);
    }
  }
}

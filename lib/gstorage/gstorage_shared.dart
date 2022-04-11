import 'package:sunny_dart/helpers/strings.dart';

String getMediaRefUri(String mediaId, mediaType) {
  final returnId = joinString((str) {
    str += mediaType;
    str += mediaId;
  }, '/');
  return returnId;
}

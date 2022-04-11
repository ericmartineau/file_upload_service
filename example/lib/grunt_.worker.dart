import 'package:sunny_services/upload_large_file.dart';
import 'package:worker_service/work.dart';
import 'package:worker_service/worker_service.dart';

void main() {
  throw "Can't do this";
}

Future mainWorker(String workerName) async {
  try {
    // configureLogging(LogConfig.root(Level.FINE, handler: LoggingHandler.dev()));
    try {
      [...RunnerFactory.global.isolateInitializers].forEach((element) {
        print('Running initializer $element');
        element.init(element.param);
      });
      var channel = GruntChannel.create(UploadLargeFile());
      await channel.done;
      print("Job is done");
    } catch (e, stack) {
      print(e);
      print(stack);
    }

    /// Register all the factories so they will be able to be found below
    gruntRegistry += UploadLargeFile();

    /// This is the part that actually executes
    final gruntFactory = gruntRegistry[workerName];
    var gruntChannel = GruntChannel.create(gruntFactory);
    await gruntChannel.done;
  } catch (e, stack) {
    print(e);
    print(stack);
  }
}

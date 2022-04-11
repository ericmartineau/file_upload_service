import 'package:pfile_picker/pfile_picker.dart';
import 'package:flutter/material.dart';
import 'package:dartxx/dartxx.dart';
import 'package:sunny_forms/media/media_content_type.dart';
import 'package:sunny_services/s3storage/s3_storage_service.dart';
import 'package:sunny_services/upload_large_file.dart';
import 'package:sunny_services/upload_large_file.grunt.dart' as g;
import 'package:worker_service/work.dart';

void gs = g.main;

class SupervisorAndArgs<G extends Grunt> {
  final Supervisor<G> supervisor;
  final dynamic args;
  final List<String> logs = [];

  SupervisorAndArgs(this.supervisor, this.args);
}

class SunnyServicesTestApp extends StatefulWidget {
  const SunnyServicesTestApp({Key? key}) : super(key: key);

  @override
  _SunnyServicesTestAppState createState() => _SunnyServicesTestAppState();
}

class _SunnyServicesTestAppState extends State<SunnyServicesTestApp> {
  final _items = <SupervisorAndArgs>[];
  var i = 1;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: Text("Isolates"),
        ),
        // backgroundColor: Colors.white,
        body: Center(
          child: ListView(
            children: [
              SizedBox(height: 10),
              Container(
                child: Row(
                  children: [
                    ElevatedButton(
                        onPressed: () async {
                          var pickedFiles = await FilePicker.platform.pickFiles();
                          if (pickedFiles == null || pickedFiles.count == 0) return;
                          PFile file = pickedFiles.files.first;

                          var supervisor = await Supervisor.create(UploadLargeFile(), isProduction: false);
                          setState(() {
                            _items.add(SupervisorAndArgs(
                              supervisor,
                              UploadFileParams.ofPFile(
                                file: file,
                                keyName: S3StorageService.mediaPathOf(MediaContentType.image, file.name!).toString(),
                                // apiBasePath: "https://api.reliveit.app",
                                apiBasePath: "https://api.reliveit.app",
                                apiToken:
                                    "eyJhbGciOiJSUzI1NiIsImtpZCI6IjY5NmFhNzRjODFiZTYwYjI5NDg1NWE5YTVlZTliODY5OGUyYWJlYzEiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL3NlY3VyZXRva2VuLmdvb2dsZS5jb20vcmVsaXZlLWl0LWFwcCIsImF1ZCI6InJlbGl2ZS1pdC1hcHAiLCJhdXRoX3RpbWUiOjE2MDgyNDE0NzIsInVzZXJfaWQiOiJTZkJuSnNUa01XZW1vblZ6R0hIejFFSFNqUW4xIiwic3ViIjoiU2ZCbkpzVGtNV2Vtb25WekdISHoxRUhTalFuMSIsImlhdCI6MTYwODI0MTQ3MiwiZXhwIjoxNjA4MjQ1MDcyLCJlbWFpbCI6ImZyZWRAbWFpbGluYXRvci5jb20iLCJlbWFpbF92ZXJpZmllZCI6ZmFsc2UsImZpcmViYXNlIjp7ImlkZW50aXRpZXMiOnsiZW1haWwiOlsiZnJlZEBtYWlsaW5hdG9yLmNvbSJdfSwic2lnbl9pbl9wcm92aWRlciI6InBhc3N3b3JkIn19.VdQG8hSXI-ZufiONEnQx7K2LGRW7o2LVtEavqTIXdK8xtFfQXCX1mDaMUZst4HzStxnr1-qVmchiBZHYit14zx-C3kotVSVZrfKG7WFDGu9IEWkK0htNDL1EVx2EhTmUahT-YhpD8KVpCOS3ytsubyVCquzdo8B1lvXyp5HJltWJqALyqknD-X11JiTeghub4g1sQVlcld75e94XU2Kbpr8pm_97pkHo8jR3xZhisjXjGvc1Af3Lrwh0NT80kyQLLgIrVEtM_Y6uLP6LckR0HtYIdV9aL2hWLBZ5mjCuxXP7sOEN9bxtCsXtKLb3LQ4uwVfurtNU9JHlz6BK4plKHg",
                              ),
                            ));
                          });
                        },
                        child: Text("Upload Large File")),
                  ],
                ),
              ),
              for (var s in _items)
                JobTile(
                  execCtx: s,
                  onStop: (phase) {
                    if (phase >= WorkPhase.processing) {
                      s.supervisor.stop();
                    } else {
                      s.supervisor.start(params: s.args);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef EmptyCallback = void Function(WorkPhase p);

class JobTile extends StatelessWidget {
  final SupervisorAndArgs execCtx;
  final Supervisor supervisor;
  final EmptyCallback? onStop;
  final WorkStatus initialStatus;

  JobTile({Key? key, required this.execCtx, this.onStop})
      : initialStatus = execCtx.supervisor.status,
        supervisor = execCtx.supervisor,
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WorkStatus>(
        key: Key("Update ${supervisor.jobId ?? 'unknown'}"),
        stream: supervisor.onStatus,
        initialData: initialStatus,
        builder: (context, snapshot) {
          var phase = snapshot.data?.phase;
          var status = snapshot.data;
          if (status?.message != null && status?.message != execCtx.logs.lastOr()) {
            execCtx.logs.add(status!.message!);
          }
          print("Rebuilding List tile with ${snapshot.data?.phase}");
          return ListTile(
            leading: CircleAvatar(child: Text("${status?.percentComplete?.round() ?? 0}")),
            title: Text("Supervisor: ${supervisor.gruntType}"),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(snapshot.data!.phase.toString()),
                for (var log in execCtx.logs)
                  Text(
                    "[log] $log",
                    style: TextStyle(fontStyle: FontStyle.italic),
                    softWrap: false,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (status?.error != null) Text(status!.error!, style: TextStyle(color: Colors.red)),
                if (status!.errorStack != null) ...[
                  for (var line in status.errorStack!.split("\n")) Text(line, style: TextStyle(fontSize: 12)),
                ],
              ],
            ),
            trailing: MaterialButton(
              child: (phase > WorkPhase.initializing)
                  ? (phase == WorkPhase.stopped || phase == WorkPhase.error)
                      ? Text("Stopped")
                      : Text("Stop")
                  : (phase == WorkPhase.starting)
                      ? Text("Starting...")
                      : Text("Start"),
              onPressed: (phase == WorkPhase.stopped || phase == WorkPhase.error) ? null : (() => onStop?.call(phase!)),
            ),
          );
        });
  }
}

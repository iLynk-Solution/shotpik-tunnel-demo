import 'dart:async';
import 'dart:io';

class SharedFolderData {
  final String id;
  final String name;
  final String nameUrl;
  final String localPath;
  String? tunnelUrl;
  Process? process;
  bool isConnecting;
  StreamSubscription? outSub;
  StreamSubscription? errSub;

  SharedFolderData({
    required this.id,
    required this.name,
    required this.nameUrl,
    required this.localPath,
    this.tunnelUrl,
    this.process,
    this.isConnecting = false,
  });
}

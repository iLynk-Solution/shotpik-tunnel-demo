import 'dart:async';
import 'dart:io';

class SharedFolderData {
  final String id;
  final String name;
  final String namePath;
  final String localPath;
  final DateTime createdAt;
  String? tunnelUrl;
  Process? process;
  bool isConnecting;
  StreamSubscription? outSub;
  StreamSubscription? errSub;

  SharedFolderData({
    required this.id,
    required this.name,
    required this.namePath,
    required this.localPath,
    DateTime? createdAt,
    this.tunnelUrl,
    this.process,
    this.outSub,
    this.errSub,
    this.isConnecting = false,
  }) : createdAt = createdAt ?? DateTime.now();
}

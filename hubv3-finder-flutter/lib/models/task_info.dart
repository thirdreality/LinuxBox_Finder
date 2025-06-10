class TaskInfo {
  final bool success;
  final String task;
  final TaskData data;

  TaskInfo({required this.success, required this.task, required this.data});

  factory TaskInfo.fromJson(Map<String, dynamic> json) {
    return TaskInfo(
      success: json['success'] ?? false,
      task: json['task'] ?? '',
      data: TaskData.fromJson(json['data'] ?? {}),
    );
  }
}

class TaskData {
  final String status;
  final int progress;
  final String message;
  final String? subTask;

  TaskData({required this.status, required this.progress, required this.message, this.subTask});

  factory TaskData.fromJson(Map<String, dynamic> json) {
    return TaskData(
      status: json['status'] ?? 'unknown',
      progress: (json['progress'] as num? ?? 0).toInt(),
      message: json['message'] ?? '',
      subTask: json['sub_task'],
    );
  }
}

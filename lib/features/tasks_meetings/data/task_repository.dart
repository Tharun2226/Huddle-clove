import '../domain/meeting.dart';
import '../domain/task.dart';

/// Task / meeting persistence. Implemented by the Nest-backed HTTP repository.
abstract interface class TaskRepository {
  Stream<List<Task>> watchTasks();
  Stream<List<Meeting>> watchMeetings();

  Future<Task> createTask(TaskDraft draft, {required String actorId});
  Future<Task> updateTask(Task task, {required String actorId});
  Future<Task> setStatus(String taskId, TaskStatus status, {required String actorId, String? statusId});
  Future<Task> toggleChecklistItem(String taskId, String itemId);
  Future<Task> addChecklistItem(String taskId, String label);
  Future<Task> addComment(String taskId, String body, {required String actorId});
  Future<void> deleteTask(String taskId);
  Future<Meeting> createMeeting(MeetingDraft draft, {required String actorId});
  Future<Meeting> updateMeeting(
    String meetingId,
    MeetingDraft draft, {
    required String actorId,
  });
  Future<void> deleteMeeting(String meetingId);
}

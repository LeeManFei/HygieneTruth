import '../models/audit_log_model.dart';
import '../models/complaint_model.dart';
import '../models/inspection_model.dart';
import '../models/restaurant_model.dart';
import '../models/user_model.dart';

class CaseOrdering {
  const CaseOrdering._();

  static int complaints(ComplaintModel a, ComplaintModel b) {
    if (a.isFlaggedForReview != b.isFlaggedForReview) {
      return a.isFlaggedForReview ? -1 : 1;
    }

    final byDate = _newestFirst(
      DateTime.tryParse(a.submittedAt),
      DateTime.tryParse(b.submittedAt),
    );
    return byDate != 0 ? byDate : b.id.compareTo(a.id);
  }

  static int inspections(InspectionModel a, InspectionModel b) {
    final byDate = _newestFirst(_inspectionDate(a), _inspectionDate(b));
    return byDate != 0 ? byDate : b.id.compareTo(a.id);
  }

  static int auditLogs(AuditLogModel a, AuditLogModel b) {
    final byDate = _newestFirst(a.timestamp, b.timestamp);
    return byDate != 0 ? byDate : b.id.compareTo(a.id);
  }

  static int restaurants(RestaurantModel a, RestaurantModel b) {
    final byDate = _newestFirst(
      DateTime.tryParse(a.createdAt ?? ''),
      DateTime.tryParse(b.createdAt ?? ''),
    );
    return byDate != 0 ? byDate : b.id.compareTo(a.id);
  }

  static int users(UserModel a, UserModel b) {
    final byDate = _newestFirst(
      DateTime.tryParse(a.joinedDate ?? ''),
      DateTime.tryParse(b.joinedDate ?? ''),
    );
    return byDate != 0 ? byDate : b.id.compareTo(a.id);
  }

  static DateTime? _inspectionDate(InspectionModel inspection) {
    final dates = [
      inspection.scheduledDate,
      inspection.conductedDate,
      inspection.issuedDate,
      inspection.paidAt,
    ].whereType<String>().map(DateTime.tryParse).whereType<DateTime>().toList();

    if (dates.isEmpty) return null;
    dates.sort((a, b) => b.compareTo(a));
    return dates.first;
  }

  static int _newestFirst(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }
}

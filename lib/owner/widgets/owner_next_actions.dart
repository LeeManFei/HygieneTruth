import 'package:flutter/material.dart';
import '../../core/models/complaint_model.dart';
import '../../core/models/inspection_model.dart';
import '../../core/models/restaurant_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/services/workflow_service.dart';
import '../../core/utils/case_ordering.dart';
import '../../core/widgets/dashboard_next_actions.dart';
import '../../core/widgets/government_list_tools.dart';

class OwnerNextActions extends StatelessWidget {
  final List<RestaurantModel> ownedRestaurants;
  final RestaurantModel? selectedRestaurant;
  const OwnerNextActions({
    super.key,
    required this.ownedRestaurants,
    this.selectedRestaurant,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      ComplaintStoreService.complaintsNotifier,
      RestaurantStoreService.inspectionsNotifier,
      RestaurantStoreService.rectificationNotifier,
    ]),
    builder: (context, _) {
      final ownedIds = ownedRestaurants
          .map((r) => r.id)
          .where((id) => id.isNotEmpty)
          .toSet();
      bool owned(String id) =>
          ownedIds.contains(id) &&
          (selectedRestaurant == null || selectedRestaurant!.id == id);
      final complaints = ComplaintStoreService.complaintsNotifier.value
          .where(
            (c) =>
                owned(c.restaurantId) &&
                !c.isFlaggedForReview &&
                ![
                  ComplaintStatus.submitted,
                  ComplaintStatus.rejected,
                  ComplaintStatus.resolved,
                ].contains(c.status),
          )
          .toList();
      final inspections =
          RestaurantStoreService.inspectionsNotifier.value
              .where((i) => owned(i.restaurantId))
              .toList()
            ..sort(CaseOrdering.inspections);
      final candidates =
          <
            ({DashboardNextAction action, int priority, String date, String id})
          >[];
      void add(ComplaintModel? c, InspectionModel? i) {
        if (i?.enforcementStatus == EnforcementStatus.completed ||
            RestaurantStoreService.isCaseClosed(
              inspectionId: i?.id,
              complaintId: c?.id ?? i?.complaintId,
            )) {
          return;
        }
        final sourceCase = c ?? ComplaintStoreService.complaintsNotifier.value.where((row) => row.id == i?.complaintId).firstOrNull;
        if (sourceCase != null && (sourceCase.isFlaggedForReview || [ComplaintStatus.submitted, ComplaintStatus.rejected, ComplaintStatus.resolved].contains(sourceCase.status))) return;
        final restId = c?.restaurantId ?? i!.restaurantId;
        final submitted = RestaurantStoreService.isRectificationSubmitted(
          restId,
          complaintId: c?.id ?? i?.complaintId,
          inspectionId: i?.id,
          noticeId: c?.id,
        );
        final reviewed = RestaurantStoreService.isRectificationAdminVerified(
          restaurantId: restId,
          complaintId: c?.id ?? i?.complaintId,
          inspectionId: i?.id,
        );
        final scheduled = i != null && i.outcome == InspectionOutcome.pending;
        final unpaid =
            !scheduled &&
            i != null &&
            i.isAdminApproved &&
            i.fineAmount > 0 &&
            !i.isFinePaid &&
            !RestaurantStoreService.isOutletFinePaid(
              restId,
              complaintId: c?.id ?? i.complaintId,
              inspectionId: i.id,
            );
        final workflow = c == null
            ? null
            : WorkflowService.getCachedWorkflow(c.id);
        final deadline = workflow?.rectificationDeadline;
        final canUpload =
            c != null &&
            !scheduled &&
            !submitted &&
            workflow?.isOwnerRectificationActive == true &&
            deadline != null &&
            deadline.isAfter(DateTime.now().toUtc());
        final title = unpaid
            ? 'Review outstanding payment'
            : canUpload
            ? 'Upload rectification photos'
            : scheduled
            ? 'Prepare for the scheduled visit'
            : submitted
            ? (reviewed ? 'Track final case closure' : 'Track evidence review')
            : 'Review rectification requirements';
        final detail = unpaid
            ? 'RM ${i.fineAmount.toStringAsFixed(2)} • Open the notice to review payment.'
            : canUpload
            ? 'Due ${GovernmentRecordDate.format(deadline.toIso8601String())}'
            : scheduled
            ? 'Visit: ${GovernmentRecordDate.format(i.scheduledDate)}'
            : submitted
            ? 'Your evidence is submitted; check the latest authority decision.'
            : 'Open the notice for available actions and the submission deadline.';
        candidates.add((
          action: DashboardNextAction(
            title: title,
            detail: '${c?.restaurantName ?? i!.restaurantName} • $detail',
            onOpen: () async {
              await Navigator.pushNamed(
                context,
                AppRoutes.noticeDetail,
                arguments: c ?? i,
              );
            },
          ),
          priority: unpaid
              ? 0
              : canUpload
              ? 1
              : submitted
              ? 3
              : 2,
          date:
              deadline?.toIso8601String() ??
              i?.dueDate ??
              i?.scheduledDate ??
              c?.submittedAt ??
              '',
          id: c?.id ?? i!.id,
        ));
      }

      final represented = <String>{};
      for (final c in complaints) {
        final i = inspections
            .where(
              (i) =>
                  i.complaintId.toLowerCase() == c.id.toLowerCase() ||
                  i.id == c.id,
            )
            .firstOrNull;
        if (i != null) represented.add(i.id);
        add(c, i);
      }
      for (final i in inspections.where((i) => !represented.contains(i.id))) {
        // A linked case is represented only by its latest inspection.
        if (i.complaintId.isNotEmpty &&
            inspections.any(
              (newer) =>
                  newer.complaintId == i.complaintId &&
                  inspections.indexOf(newer) < inspections.indexOf(i),
            )) {
          continue;
        }
        if (complaints.any(
          (c) => c.id.toLowerCase() == i.complaintId.toLowerCase(),
        )) {
          continue;
        }
        add(null, i);
      }
      candidates.sort((a, b) {
        final priority = a.priority.compareTo(b.priority);
        final date = GovernmentRecordDate.compare(a.date, b.date, true);
        return priority != 0
            ? priority
            : date != 0
            ? date
            : a.id.compareTo(b.id);
      });
      return DashboardNextActions(
        sessionKey: 'owner_next_actions',
        actions: candidates.take(3).map((c) => c.action).toList(),
        emptyMessage: ownedIds.isEmpty
            ? 'Register an outlet in My Restaurants to get started.'
            : 'No pending compliance actions in the loaded records for this outlet.',
      );
    },
  );
}

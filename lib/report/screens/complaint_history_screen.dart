import '../../core/widgets/customer_refresh_indicator.dart';
import 'package:flutter/material.dart';
import '../../core/models/complaint_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/customer_store_service.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/shimmer_skeletons.dart';
import '../../core/widgets/status_badge.dart';


class ComplaintHistoryScreen extends StatefulWidget {
  const ComplaintHistoryScreen({super.key});

  @override
  State<ComplaintHistoryScreen> createState() => _ComplaintHistoryScreenState();
}

class _ComplaintHistoryScreenState extends State<ComplaintHistoryScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    await ComplaintStoreService.fetchAllComplaints(forceRefresh: true);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _handleRefresh() async {
    await ComplaintStoreService.fetchAllComplaints(forceRefresh: true);
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: ComplaintStoreService.complaintsNotifier,
      builder: (context, _) {
        final allComplaints = ComplaintStoreService.complaintsNotifier.value.isNotEmpty
            ? ComplaintStoreService.complaintsNotifier.value
            : RestaurantStoreService.complaintsNotifier.value;

        final currentCustomer = CustomerStoreService.currentCustomer;
        final authUser = SupabaseService.client.auth.currentUser;

        final String currentUserId = (currentCustomer?.id ?? authUser?.id ?? '').trim().toLowerCase();
        final String currentUserEmail = (currentCustomer?.email ?? authUser?.email ?? '').trim().toLowerCase();
        final String currentUserName = (currentCustomer?.name ?? '').trim().toLowerCase();

        final List<ComplaintModel> myComplaints;

        if (currentUserId.isNotEmpty || currentUserEmail.isNotEmpty || currentUserName.isNotEmpty) {
          myComplaints = allComplaints.where((c) {
            final cUserId = c.userId.trim().toLowerCase();
            final cUserName = c.userName.trim().toLowerCase();

            if (currentUserId.isNotEmpty && cUserId == currentUserId) {
              return true;
            }
            if (currentUserEmail.isNotEmpty && (cUserId == currentUserEmail || cUserName == currentUserEmail)) {
              return true;
            }
            if (currentUserName.isNotEmpty && cUserName == currentUserName) {
              return true;
            }
            return false;
          }).toList();
        } else {
          // Unauthenticated or new guest session with no submissions
          myComplaints = [];
        }

        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
          appBar: const CustomAppBar(title: 'My Reports'),
          body: SafeArea(
            top: false,
            bottom: true,
            child: _isLoading
                ? const ComplaintHistorySkeleton()
                : CustomerRefreshIndicator(
                  onRefresh: _handleRefresh,
                  child: myComplaints.isEmpty
                  ? SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
                      child: Container(
                        height: MediaQuery.of(context).size.height * 0.65,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFE0F2FE),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.assignment_turned_in_outlined,
                                size: 56,
                                color: Color(0xFF0284C7),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'No Reports Filed Yet',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : AppTheme.navyColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'You have not submitted any hygiene or food safety complaints yet. All incident reports you file will be tracked here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white60 : Colors.grey.shade600,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0284C7),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () {
                                Navigator.pushNamed(context, AppRoutes.submitComplaint);
                              },
                              icon: const Icon(Icons.add_comment_rounded, size: 18),
                              label: const Text('Submit a Report', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      padding: const EdgeInsets.all(12),
                      itemCount: myComplaints.length,
                      itemBuilder: (context, index) {
                        final c = myComplaints[index];
                        return Card(
                          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200),
                          ),
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            title: Text(
                              c.restaurantName,
                              style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 2),
                                Text(
                                  'ID: ${c.id.startsWith('CMP-') ? c.id : 'CMP-${c.id.length > 8 ? c.id.substring(0, 8).toUpperCase() : c.id.toUpperCase()}'} • ${c.category}',
                                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 12.5),
                                ),
                                const SizedBox(height: 2),
                                Text('Submitted: ${c.submittedAt}', style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.grey)),
                                const SizedBox(height: 6),
                                StatusBadge.fromStatus(c.status.name),
                              ],
                            ),
                            trailing: Icon(Icons.arrow_forward_ios, size: 14, color: isDark ? Colors.white38 : Colors.grey),
                            onTap: () {
                              Navigator.pushNamed(
                                context,
                                AppRoutes.complaintStatusDetail,
                                arguments: c,
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
}

import '../../core/models/user_model.dart';
import 'package:flutter/material.dart';
import '../../core/models/restaurant_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/customer_store_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/restaurant_store_service.dart';
import '../models/notification_model.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/widgets/shimmer_skeletons.dart';
import '../../core/widgets/hygiene_pull_to_refresh.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _activeTabIndex = 0;
  bool _isLoading = true;
  bool _showOnlyUnread = false;

  final List<Map<String, dynamic>> _categories = [
    {'id': 'all', 'label': 'All', 'icon': Icons.all_inbox_rounded},
    {'id': 'alerts', 'label': 'Safety Alerts', 'icon': Icons.shield_outlined},
    {'id': 'reviews', 'label': 'Reviews', 'icon': Icons.rate_review_outlined},
    {'id': 'complaints', 'label': 'Complaints', 'icon': Icons.report_problem_outlined},
    {'id': 'system', 'label': 'System', 'icon': Icons.campaign_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _activeTabIndex = _tabController.index);
      }
    });
    _loadNotifications();
  }

  Future<void> _loadNotifications({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
    final user = CustomerStoreService.currentCustomer;
    await Future.wait([
      NotificationService.fetchNotifications(
        userId: user?.id,
        userEmail: user?.email,
        userRole: user?.role.name,
      ),
      RestaurantStoreService.fetchAllComplaints(forceRefresh: true),
      RestaurantStoreService.fetchAllInspections(forceRefresh: true),
    ]);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackgroundColor : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: ValueListenableBuilder<List<AppNotificationModel>>(
          valueListenable: NotificationService.notificationsNotifier,
          builder: (context, notifs, _) {
            final unreadTotal = notifs.where((n) => !n.isRead).length;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Notifications',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: isDark ? AppTheme.darkTextColor : AppTheme.navyColor,
                  ),
                ),
                if (unreadTotal > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$unreadTotal new',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDark ? Colors.white : AppTheme.navyColor,
            size: 19,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Theme(
            data: Theme.of(context).copyWith(
              cardColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
              popupMenuTheme: PopupMenuThemeData(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0),
                    width: 1.2,
                  ),
                ),
                elevation: 12,
                shadowColor: Colors.black.withValues(alpha: isDark ? 0.6 : 0.15),
              ),
            ),
            child: PopupMenuButton<String>(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSecondarySurface : const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.more_vert_rounded,
                  color: isDark ? Colors.white : AppTheme.navyColor,
                  size: 20,
                ),
              ),
              offset: const Offset(0, 48),
              onSelected: (val) async {
                final user = CustomerStoreService.currentCustomer;
                if (val == 'mark_all_read') {
                  await NotificationService.markAllAsRead(userId: user?.id, userEmail: user?.email);
                  if (context.mounted) {
                    HygieneFeedback.showSuccess(context, 'All notifications marked as read');
                  }
                } else if (val == 'clear_all') {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (dCtx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      backgroundColor: isDark ? AppTheme.darkSurfaceColor : Colors.white,
                      title: const Row(
                        children: [
                          Icon(Icons.delete_sweep_rounded, color: Color(0xFFDC2626)),
                          SizedBox(width: 8),
                          Text('Clear Notifications', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      content: const Text(
                        'Are you sure you want to remove all notifications? This action cannot be undone.',
                        style: TextStyle(fontSize: 13.5, height: 1.4),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dCtx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(dCtx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Clear All'),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await NotificationService.clearAll(userId: user?.id);
                    if (context.mounted) {
                      HygieneFeedback.showSuccess(context, 'All notifications cleared');
                    }
                  }
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'mark_all_read',
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.done_all_rounded,
                          size: 17,
                          color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Mark all as read',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'Clear unread badges',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: isDark ? Colors.white60 : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(height: 12),
                PopupMenuItem(
                  value: 'clear_all',
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.delete_sweep_rounded,
                          size: 17,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Clear all',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                          Text(
                            'Remove all activity alerts',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: isDark ? Colors.white60 : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Category Bar TabBar with scrollable tabs & live badges
            _buildCategoryBar(isDark),

            // Category Subheader with quick filters
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compactActions = constraints.maxWidth < 430;

                  return Row(
                    children: [
                      Container(
                        width: 4,
                        height: 16,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _getCategoryTitle(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isDark
                                ? AppTheme.darkTextColor
                                : AppTheme.navyColor,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          setState(() => _showOnlyUnread = !_showOnlyUnread);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: EdgeInsets.symmetric(
                            horizontal: compactActions ? 8 : 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: _showOnlyUnread
                                ? (isDark
                                      ? const Color(
                                          0xFF0F766E,
                                        ).withValues(alpha: 0.3)
                                      : const Color(0xFFCCFBF1))
                                : (isDark
                                      ? AppTheme.darkSecondarySurface
                                      : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _showOnlyUnread
                                  ? (isDark
                                        ? const Color(0xFF14B8A6)
                                        : const Color(0xFF0D9488))
                                  : (isDark
                                        ? AppTheme.darkBorderColor
                                        : const Color(0xFFE2E8F0)),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _showOnlyUnread
                                    ? Icons.filter_alt_rounded
                                    : Icons.filter_alt_outlined,
                                size: 13,
                                color: _showOnlyUnread
                                    ? const Color(0xFF0F766E)
                                    : (isDark
                                          ? Colors.white60
                                          : Colors.grey.shade700),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Unread',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: _showOnlyUnread
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  color: _showOnlyUnread
                                      ? const Color(0xFF0F766E)
                                      : (isDark
                                            ? Colors.white70
                                            : Colors.grey.shade700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Mark all as read',
                        child: InkWell(
                          onTap: () async {
                            final user = CustomerStoreService.currentCustomer;
                            await NotificationService.markAllAsRead(
                              userId: user?.id,
                              userEmail: user?.email,
                            );
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: compactActions ? 8 : 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white12
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.done_all_rounded,
                                  size: 13,
                                  color: AppTheme.primaryColor,
                                ),
                                if (!compactActions) ...[
                                  const SizedBox(width: 4),
                                  const Text(
                                    'Read all',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.primaryColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // Notifications TabBarView
            Expanded(
              child: _isLoading
                  ? const NotificationListSkeleton()
                  : ValueListenableBuilder<List<AppNotificationModel>>(
                      valueListenable: NotificationService.notificationsNotifier,
                      builder: (context, notifs, _) {
                        return TabBarView(
                          controller: _tabController,
                          children: _categories.map((cat) {
                            final filtered = notifs.where((n) {
                              if (_showOnlyUnread && n.isRead) return false;
                              final catId = cat['id'];
                              if (catId == 'alerts') return n.type == NotificationType.hygieneAlert;
                              if (catId == 'reviews') return n.type == NotificationType.review;
                              if (catId == 'complaints') return n.type == NotificationType.complaint;
                              if (catId == 'system') return n.type == NotificationType.system || n.type == NotificationType.outlet;
                              return true;
                            }).toList();

                            if (filtered.isEmpty) {
                              return HygienePullToRefresh(customerMode: CustomerStoreService.currentCustomer?.role == UserRole.user,
                                onRefresh: () => _loadNotifications(showLoading: !(CustomerStoreService.currentCustomer?.role == UserRole.user)),
                                child: SingleChildScrollView(
                                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                  child: Container(
                                    height: MediaQuery.of(context).size.height * 0.65,
                                    alignment: Alignment.center,
                                    child: _buildEmptyState(isDark, cat['label']),
                                  ),
                                ),
                              );
                            }

                            return HygienePullToRefresh(customerMode: CustomerStoreService.currentCustomer?.role == UserRole.user,
                              onRefresh: () => _loadNotifications(showLoading: !(CustomerStoreService.currentCustomer?.role == UserRole.user)),
                              child: ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final item = filtered[index];
                                  return _buildNotificationCard(item, isDark);
                                },
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _getCategoryTitle() {
    switch (_activeTabIndex) {
      case 0:
        return 'All Activity';
      case 1:
        return 'Safety & Outbreak Alerts';
      case 2:
        return 'Customer Review Responses';
      case 3:
        return 'Hygiene Complaint Updates';
      case 4:
        return 'System & Inspection Notices';
      default:
        return 'Notifications';
    }
  }

  Widget _buildCategoryBar(bool isDark) {
    return ValueListenableBuilder<List<AppNotificationModel>>(
      valueListenable: NotificationService.notificationsNotifier,
      builder: (context, notifs, _) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                width: 1,
              ),
            ),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            indicatorColor: AppTheme.primaryColor,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor: isDark ? Colors.white54 : Colors.grey.shade600,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            labelPadding: const EdgeInsets.symmetric(horizontal: 10),
            tabs: _categories.map((cat) {
              final int index = _categories.indexOf(cat);
              final bool isSelected = _activeTabIndex == index;
              final catId = cat['id'];

              final count = notifs.where((n) {
                if (catId == 'alerts') return n.type == NotificationType.hygieneAlert;
                if (catId == 'reviews') return n.type == NotificationType.review;
                if (catId == 'complaints') return n.type == NotificationType.complaint;
                if (catId == 'system') return n.type == NotificationType.system || n.type == NotificationType.outlet;
                return true;
              }).length;

              final unreadCount = notifs.where((n) {
                if (n.isRead) return false;
                if (catId == 'alerts') return n.type == NotificationType.hygieneAlert;
                if (catId == 'reviews') return n.type == NotificationType.review;
                if (catId == 'complaints') return n.type == NotificationType.complaint;
                if (catId == 'system') return n.type == NotificationType.system || n.type == NotificationType.outlet;
                return true;
              }).length;

              return Tab(
                height: 64,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            cat['icon'] as IconData,
                            size: 20,
                            color: isSelected
                                ? AppTheme.primaryColor
                                : (isDark ? Colors.white54 : Colors.grey.shade600),
                          ),
                          if (unreadCount > 0)
                            Positioned(
                              top: -2,
                              right: -4,
                              child: Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEF4444),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            cat['label'] as String,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                          if (count > 0) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.primaryColor.withValues(alpha: 0.15)
                                    : (isDark ? Colors.white12 : const Color(0xFFF1F5F9)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? AppTheme.primaryColor
                                      : (isDark ? Colors.white70 : Colors.grey.shade700),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildNotificationCard(AppNotificationModel item, bool isDark) {
    Color typeColor = AppTheme.primaryColor;
    IconData typeIcon = Icons.notifications_active_outlined;
    String typeLabel = 'System';

    switch (item.type) {
      case NotificationType.complaint:
        typeColor = const Color(0xFFDC2626); // Crimson Red
        typeIcon = Icons.report_problem_rounded;
        typeLabel = 'Complaint Update';
        break;
      case NotificationType.outlet:
        typeColor = const Color(0xFF0F766E); // Deep Teal
        typeIcon = Icons.storefront_rounded;
        typeLabel = 'Premises Notice';
        break;
      case NotificationType.review:
        typeColor = const Color(0xFF9333EA); // Purple
        typeIcon = Icons.rate_review_rounded;
        typeLabel = 'Review Response';
        break;
      case NotificationType.hygieneAlert:
        typeColor = const Color(0xFFD97706); // Amber
        typeIcon = Icons.shield_rounded;
        typeLabel = 'Safety Alert';
        break;
      case NotificationType.system:
        typeColor = AppTheme.navyColor;
        typeIcon = Icons.campaign_rounded;
        typeLabel = 'System Notice';
        break;
    }

    final timeStr = _formatDateTime(item.createdAt);

    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red.shade600,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
            SizedBox(width: 6),
            Text('Dismiss', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
      onDismissed: (_) {
        final user = CustomerStoreService.currentCustomer;
        NotificationService.deleteNotification(item.id, userId: user?.id);
        HygieneFeedback.showSuccess(context, 'Notification removed');
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: !item.isRead
              ? (isDark ? const Color(0xFF0F766E).withValues(alpha: 0.12) : const Color(0xFFF0FDFA))
              : (isDark ? AppTheme.darkSurfaceColor : Colors.white),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: !item.isRead
                ? (isDark ? const Color(0xFF14B8A6).withValues(alpha: 0.5) : const Color(0xFF99F6E4))
                : (isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0)),
            width: !item.isRead ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _handleNotificationClick(item),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(typeIcon, color: typeColor, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        typeLabel,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: typeColor,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (!item.isRead) ...[
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: const BoxDecoration(
                          color: Color(0xFF0F766E),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppTheme.darkSubtitleColor : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  item.title,
                  style: TextStyle(
                    fontWeight: !item.isRead ? FontWeight.bold : FontWeight.w600,
                    fontSize: 14.5,
                    color: isDark ? AppTheme.darkTextColor : AppTheme.navyColor,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.message,
                  style: TextStyle(
                    color: isDark ? AppTheme.darkSubtitleColor : Colors.grey.shade700,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      item.type == NotificationType.review
                          ? 'View review & reply'
                          : (item.type == NotificationType.complaint
                              ? 'View report details'
                              : 'View details'),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F766E),
                      ),
                    ),
                    const SizedBox(width: 3),
                    const Icon(Icons.arrow_forward_rounded, size: 13, color: Color(0xFF0F766E)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final m = months[dt.month - 1];
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$m $d, $h:$min';
  }

  String _formatFullDateTime(DateTime dt) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    final m = months[dt.month - 1];
    final d = dt.day;
    final year = dt.year;
    final hour = dt.hour > 12 ? (dt.hour - 12) : (dt.hour == 0 ? 12 : dt.hour);
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$m $d, $year at $hour:$min $ampm';
  }

  Widget _buildEmptyState(bool isDark, String categoryLabel) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurfaceColor : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: 44,
                color: isDark ? Colors.white38 : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No $categoryLabel Found',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: isDark ? AppTheme.darkTextColor : AppTheme.navyColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'You are all caught up! Realtime updates for $categoryLabel will appear here instantly.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? AppTheme.darkSubtitleColor : Colors.grey.shade600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleNotificationClick(AppNotificationModel item) async {
    final user = CustomerStoreService.currentCustomer;
    if (!item.isRead) {
      await NotificationService.markAsRead(item.id, userId: user?.id, userEmail: user?.email);
    }

    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (item.type) {
      case NotificationType.review:
        // Extract restaurant ID / Name from data, actionUrl or message
        String? restId = item.data['restaurant_id']?.toString() ??
            item.data['restaurantId']?.toString() ??
            item.data['id']?.toString();
        String? restName = item.data['restaurant_name']?.toString() ??
            item.data['restaurantName']?.toString();

        final rawAction = item.actionUrl ?? '';
        if (rawAction.isNotEmpty) {
          if (rawAction.startsWith('outlet_')) {
            restId ??= rawAction.replaceFirst('outlet_', '');
          } else if (rawAction.startsWith('restaurant_')) {
            restId ??= rawAction.replaceFirst('restaurant_', '');
          } else {
            restId ??= rawAction;
          }
        }

        // Try extracting quoted restaurant name e.g. Owner of "testing" replied...
        if (restName == null || restName.isEmpty) {
          final match = RegExp(r'"([^"]+)"').firstMatch(item.message);
          if (match != null) {
            restName = match.group(1);
          }
        }

        // Search in loaded restaurants
        final allRestaurants = RestaurantStoreService.restaurantsNotifier.value;
        RestaurantModel? targetRestaurant;

        if (restId != null && restId.isNotEmpty) {
          targetRestaurant = allRestaurants
              .where((r) => r.id == restId || r.name.toLowerCase() == restId!.toLowerCase())
              .firstOrNull;
        }
        if (targetRestaurant == null && restName != null && restName.isNotEmpty) {
          targetRestaurant = allRestaurants
              .where((r) => r.name.toLowerCase() == restName!.toLowerCase())
              .firstOrNull;
        }

        // Fallback to first available restaurant if memory not populated
        if (targetRestaurant == null && allRestaurants.isNotEmpty) {
          targetRestaurant = allRestaurants.first;
        }

        if (targetRestaurant != null) {
          Navigator.pushNamed(
            context,
            AppRoutes.restaurantDetail,
            arguments: {
              'restaurant': targetRestaurant,
              'scrollToReviews': true,
            },
          );
        } else {
          _showNotificationDetailBottomSheet(
            context,
            item,
            isDark,
            actionButtonLabel: 'View Restaurant Outlets',
            onActionPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, AppRoutes.restaurantMap);
            },
          );
        }
        break;

      case NotificationType.complaint:
        String? rawCompId = item.data['complaint_id']?.toString() ??
            item.data['complaintId']?.toString() ??
            item.data['id']?.toString() ??
            item.actionUrl;

        // Extract CMP code if present in title (e.g. #CMP-FDB70E4D) or message
        if (rawCompId == null || rawCompId.isEmpty) {
          final regex = RegExp(r'#?CMP-([A-Za-z0-9]+)', caseSensitive: false);
          final match = regex.firstMatch(item.title) ?? regex.firstMatch(item.message);
          if (match != null) {
            rawCompId = match.group(1);
          }
        }

        final allComplaints = ComplaintStoreService.complaintsNotifier.value;
        final targetComplaint = allComplaints.where((c) {
          if (rawCompId == null || rawCompId.isEmpty) return false;
          final cleanTarget = rawCompId
              .replaceAll('#', '')
              .replaceAll('CMP-', '')
              .replaceAll('cmp-', '')
              .replaceAll('cmp_', '')
              .trim()
              .toLowerCase();
          final cleanId = c.id
              .replaceAll('#', '')
              .replaceAll('CMP-', '')
              .replaceAll('cmp-', '')
              .replaceAll('cmp_', '')
              .trim()
              .toLowerCase();

          return cleanId == cleanTarget ||
              cleanId.startsWith(cleanTarget) ||
              cleanTarget.startsWith(cleanId) ||
              c.id.toLowerCase() == rawCompId.toLowerCase();
        }).firstOrNull;

        if (targetComplaint != null) {
          Navigator.pushNamed(context, AppRoutes.complaintStatusDetail, arguments: targetComplaint);
        } else if (rawCompId != null && rawCompId.isNotEmpty) {
          Navigator.pushNamed(context, AppRoutes.complaintStatusDetail, arguments: rawCompId);
        } else {
          Navigator.pushNamed(context, AppRoutes.complaintHistory);
        }
        break;

      case NotificationType.hygieneAlert:
        _showNotificationDetailBottomSheet(
          context,
          item,
          isDark,
          actionButtonLabel: 'Explore Safe Food Hub',
          onActionPressed: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, AppRoutes.recommendationHome);
          },
        );
        break;

      case NotificationType.outlet:
        String? restId = item.data['restaurant_id']?.toString() ?? item.actionUrl;
        final allRestaurants = RestaurantStoreService.restaurantsNotifier.value;
        final targetRestaurant =
            allRestaurants.where((r) => r.id == restId || r.name == restId).firstOrNull;
        if (targetRestaurant != null) {
          Navigator.pushNamed(context, AppRoutes.restaurantDetail, arguments: targetRestaurant);
        } else {
          _showNotificationDetailBottomSheet(context, item, isDark);
        }
        break;

      case NotificationType.system:
        _showNotificationDetailBottomSheet(context, item, isDark);
        break;
    }
  }

  void _showNotificationDetailBottomSheet(
    BuildContext context,
    AppNotificationModel item,
    bool isDark, {
    String? actionButtonLabel,
    VoidCallback? onActionPressed,
  }) {
    Color typeColor = AppTheme.primaryColor;
    IconData typeIcon = Icons.notifications_active_outlined;
    String typeLabel = 'System Notice';

    switch (item.type) {
      case NotificationType.complaint:
        typeColor = const Color(0xFFDC2626);
        typeIcon = Icons.report_problem_rounded;
        typeLabel = 'Complaint Update';
        break;
      case NotificationType.outlet:
        typeColor = const Color(0xFF0F766E);
        typeIcon = Icons.storefront_rounded;
        typeLabel = 'Premises Notice';
        break;
      case NotificationType.review:
        typeColor = const Color(0xFF9333EA);
        typeIcon = Icons.rate_review_rounded;
        typeLabel = 'Review Response';
        break;
      case NotificationType.hygieneAlert:
        typeColor = const Color(0xFFD97706);
        typeIcon = Icons.shield_rounded;
        typeLabel = 'Hygiene & Safety Alert';
        break;
      case NotificationType.system:
        typeColor = AppTheme.primaryColor;
        typeIcon = Icons.campaign_rounded;
        typeLabel = 'System Announcement';
        break;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: EdgeInsets.only(
            top: 14,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurfaceColor : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: isDark ? AppTheme.darkBorderColor : const Color(0xFFE2E8F0),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Header Badge & Close Button
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: isDark ? 0.22 : 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(typeIcon, color: typeColor, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: typeColor.withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            typeLabel,
                            style: TextStyle(
                              color: typeColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 13,
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDateTime(item.createdAt),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Notification Title
              Text(
                item.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.navyColor,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),

              // Full Message Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF252525) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? const Color(0xFF383838) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Text(
                  item.message,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? const Color(0xFFF3F4F6) : const Color(0xFF334155),
                    height: 1.5,
                  ),
                ),
              ),

              // Timestamp & Channel info
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(
                    Icons.verified_outlined,
                    size: 14,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Dispatched on ${_formatFullDateTime(item.createdAt)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Action Buttons
              if (actionButtonLabel != null && onActionPressed != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onActionPressed,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text(actionButtonLabel),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : AppTheme.navyColor,
                    side: BorderSide(
                      color: isDark ? AppTheme.darkBorderColor : const Color(0xFFCBD5E1),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Dismiss', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

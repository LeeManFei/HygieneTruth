import '../../core/services/restaurant_store_service.dart';
import 'package:flutter/material.dart';
import '../../core/routes/app_routes.dart';
import '../../core/widgets/custom_app_bar.dart';

class RestaurantValidationQueueScreen extends StatelessWidget {
  const RestaurantValidationQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final list = RestaurantStoreService.restaurantsNotifier.value;

    return Scaffold(
      appBar: const CustomAppBar(title: 'Restaurant Validation Queue'),
      body: SafeArea(
        top: false,
        bottom: true,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          itemBuilder: (context, index) {
            final r = list[index];
            return Card(
              child: ListTile(
                leading: CircleAvatar(backgroundImage: NetworkImage(r.imageUrl)),
                title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${r.category} • Violations: ${r.violationCount}'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: () {
                  Navigator.pushNamed(context, AppRoutes.restaurantVerificationDetail, arguments: r);
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

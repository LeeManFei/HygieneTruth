import '../../core/services/restaurant_store_service.dart';
import 'package:flutter/material.dart';
import '../../core/models/restaurant_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/wireframe_box.dart';

class HygieneHeatmapScreen extends StatefulWidget {
  const HygieneHeatmapScreen({super.key});

  @override
  State<HygieneHeatmapScreen> createState() => _HygieneHeatmapScreenState();
}

class _HygieneHeatmapScreenState extends State<HygieneHeatmapScreen> {
  RestaurantModel? _selectedZone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final restaurants = RestaurantStoreService.restaurantsNotifier.value;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
      appBar: const CustomAppBar(title: 'Risk Heatmap'),
      body: Stack(
        children: [
          // Wireframe Heatmap Map Box Layer
          Positioned.fill(
            child: Container(
              color: isDark ? const Color(0xFF121212) : const Color(0xFFF8FAFC),
              child: Stack(
                children: [
                  const WireframeBox(
                    height: double.infinity,
                    icon: Icons.local_fire_department,
                    label: 'Risk Heatmap Layer',
                    sublabel: 'Red areas indicate high complaint density',
                  ),

                  // Heatmap Overlay Blobs
                  Positioned(
                    top: 140,
                    right: 60,
                    child: _buildHeatmapBlob(context, restaurants[1], radius: 90, color: Colors.red.withValues(alpha: 0.5)),
                  ),
                  Positioned(
                    bottom: 140,
                    right: 70,
                    child: _buildHeatmapBlob(context, restaurants[4], radius: 80, color: Colors.red.withValues(alpha: 0.45)),
                  ),
                  Positioned(
                    bottom: 200,
                    left: 100,
                    child: _buildHeatmapBlob(context, restaurants[2], radius: 60, color: Colors.amber.withValues(alpha: 0.4)),
                  ),
                  Positioned(
                    top: 120,
                    left: 70,
                    child: _buildHeatmapBlob(context, restaurants[0], radius: 50, color: Colors.green.withValues(alpha: 0.35)),
                  ),
                ],
              ),
            ),
          ),

          // Legend Card Header
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              color: isDark ? const Color(0xFF1E1E1E).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _legendItem('High Risk Zone', Colors.red, isDark),
                    _legendItem('Moderate Zone', Colors.amber, isDark),
                    _legendItem('Safe Zone', Colors.green, isDark),
                  ],
                ),
              ),
            ),
          ),

          // Selected Zone Detail Bottom Card
          if (_selectedZone != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: SafeArea(
                top: false,
                bottom: true,
                child: Card(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning, color: Colors.red),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedZone!.name,
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black87),
                                ),
                                Text(
                                  'Score: ${_selectedZone!.hygieneRiskScore.toStringAsFixed(1)} • ${_selectedZone!.violationCount} Violations',
                                  style: const TextStyle(fontSize: 12, color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.grey),
                            onPressed: () => setState(() => _selectedZone = null),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(40),
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.pushNamed(
                            context,
                            AppRoutes.restaurantRiskDetail,
                            arguments: _selectedZone,
                          );
                        },
                        child: const Text('Risk Details'),
                      ),
                    ],
                  ),
                ),
              ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color, bool isDark) {
    return Row(
      children: [
        CircleAvatar(radius: 6, backgroundColor: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
        ),
      ],
    );
  }

  Widget _buildHeatmapBlob(BuildContext context, RestaurantModel r, {required double radius, required Color color}) {
    return GestureDetector(
      onTap: () => setState(() => _selectedZone = r),
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.6),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              r.name,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

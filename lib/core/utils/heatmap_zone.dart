import '../models/restaurant_model.dart';

class HeatmapZone {
  static double radiusMeters(RestaurantModel outlet) =>
      120 + outlet.hygieneRiskScore.clamp(0, 100) * 2.5;
}

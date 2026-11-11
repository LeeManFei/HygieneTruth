import '../../core/utils/outlet_image_provider.dart';
import '../../core/utils/heatmap_zone.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../core/config/app_env.dart';
import '../../core/models/restaurant_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/gps_service.dart';
import '../../core/services/language_manager.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/services/routing_service.dart';
import '../../core/theme/app_map_theme.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/utils/translations.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/shimmer_skeletons.dart';
import '../../core/widgets/voice_search_modal.dart';

class RestaurantMapScreen extends StatefulWidget {
  final bool showAppBar;
  const RestaurantMapScreen({super.key, this.showAppBar = true});

  @override
  State<RestaurantMapScreen> createState() => _RestaurantMapScreenState();
}

class _RestaurantMapScreenState extends State<RestaurantMapScreen> {
  GoogleMapController? _mapController;
  late PageController _pageController;

  RestaurantModel? _focusedRestaurant;
  RestaurantModel? _targetRestaurant;
  bool _isNavigationMode = false;
  bool _isActiveDrivingNavigation = false;
  bool _isRoutePreviewExpanded = false;
  bool _hasParsedArguments = false;
  Set<Polyline> _polylines = {};
  int _etaMinutes = 5;
  String _routeDistanceStr = '';

  RouteResult? _currentRouteResult;
  int _currentNavigationStepIndex = 0;
  String _transportMode = 'driving'; // 'driving', 'motorcycle', 'walking'
  bool _isVoiceMuted = false;
  StreamSubscription<Position>? _positionStreamSub;
  double _currentBearing = 0.0;

  Position? _userPosition;
  bool _showHeatmap = true; // Toggle for Risk Heatmap Layer
  MapType _currentMapType = MapType.normal; // Default 3D Vector Map with 3D Buildings & Tilt
  int _currentPageIndex = 0;

  String _filterRisk = 'All'; // 'All', 'Safe', 'Moderate', 'High Risk'
  final TextEditingController _listSearchCtrl = TextEditingController();

  final stt.SpeechToText _speechToText = stt.SpeechToText();

  Set<Marker> _markers = {};
  Set<Circle> _heatmapCircles = {};
  List<RestaurantModel> _allRestaurants = [];
  List<RestaurantModel> _filteredList = [];

  static const LatLng _defaultCenter = LatLng(3.1466, 101.6958);

  bool _isMapLoading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasParsedArguments) {
      _hasParsedArguments = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is RestaurantModel) {
        _targetRestaurant = args;
        _isNavigationMode = false;
      } else if (args is Map) {
        _targetRestaurant = args['restaurant'] is RestaurantModel ? args['restaurant'] as RestaurantModel : null;
        _isNavigationMode = args['showDirections'] == true;
      }

      if (_targetRestaurant != null) {
        _filteredList = [_targetRestaurant!];
        _focusedRestaurant = _targetRestaurant;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.88, initialPage: 0);
    _loadRestaurantsFromSupabase();
    _fetchUserLocation();

    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() {
          _isMapLoading = false;
        });
      }
    });
  }

  Future<void> _loadRestaurantsFromSupabase() async {
    final list = await RestaurantStoreService.fetchAllRestaurants(forceRefresh: true);
    await RestaurantStoreService.preloadRestaurants(list);
    if (mounted) {
      setState(() {
        _allRestaurants = list;
        if (_targetRestaurant != null) {
          final matched = list.where((r) => r.id == _targetRestaurant!.id).toList();
          _filteredList = matched.isNotEmpty ? matched : [_targetRestaurant!];
          _focusedRestaurant = _targetRestaurant;
        } else {
          _filteredList = List.from(list);
          if (_userPosition != null) {
            _filteredList.sort((a, b) {
              final distA = Geolocator.distanceBetween(_userPosition!.latitude, _userPosition!.longitude, a.latitude, a.longitude);
              final distB = Geolocator.distanceBetween(_userPosition!.latitude, _userPosition!.longitude, b.latitude, b.longitude);
              return distA.compareTo(distB);
            });
          }
          if (_filteredList.isNotEmpty) {
            _focusedRestaurant = _filteredList.first;
          }
        }
      });
      _initMapMarkersAndHeatmap();
      if (_targetRestaurant != null && _isNavigationMode) {
        _buildNavigationRoute(_targetRestaurant!);
      } else if (_targetRestaurant != null) {
        _animateMapToLocation(_targetRestaurant!.latitude, _targetRestaurant!.longitude);
      }
    }
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    _pageController.dispose();
    _listSearchCtrl.dispose();
    super.dispose();
  }

  bool get _isSatellite => _currentMapType == MapType.hybrid;

  void _toggleMapType() {
    setState(() {
      if (_currentMapType == MapType.normal) {
        _currentMapType = MapType.hybrid;
      } else {
        _currentMapType = MapType.normal;
      }
    });
  }

  void _showMapTypeOptionsSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Drag Handle Bar
                  Center(
                    child: Container(
                      width: 44,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppTheme.primaryColor, Color(0xFF14B8A6)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.layers_rounded, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select Google Map View',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : AppTheme.navyColor,
                                ),
                              ),
                              Text(
                                'Switch rendering mode and satellite layers',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: isDark ? Colors.white70 : Colors.grey.shade700),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMapTypeCard('3D Vector', MapType.normal, Icons.view_in_ar_rounded, isDark),
                      _buildMapTypeCard('Satellite', MapType.hybrid, Icons.satellite_alt_rounded, isDark),
                      _buildMapTypeCard('Terrain', MapType.terrain, Icons.terrain_rounded, isDark),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMapTypeCard(String label, MapType type, IconData icon, bool isDark) {
    final isSelected = _currentMapType == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentMapType = type;
        });
        Navigator.pop(context);
      },
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: isSelected
                  ? const LinearGradient(
                      colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isSelected
                  ? null
                  : (isDark ? const Color(0xFF282828) : const Color(0xFFF1F5F9)),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSelected
                    ? AppTheme.primaryColor
                    : (isDark ? Colors.white12 : Colors.grey.shade300),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.grey.shade700),
              size: 30,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? AppTheme.primaryColor
                  : (isDark ? Colors.white70 : AppTheme.navyColor),
            ),
          ),
        ],
      ),
    );
  }



  void _startVoiceSearch() {
    VoiceSearchModal.show(
      context: context,
      initialText: _listSearchCtrl.text,
      speechToText: _speechToText,
      suggestions: const [
        'Golden Dragon',
        'Halal Bistro',
        'Dim Sum',
        'Noodles',
        'Mamak',
        'Café',
        'Bakery',
      ],
      onResult: (text) {
        if (mounted) {
          setState(() {
            _listSearchCtrl.text = text;
            _filterRestaurantList();
          });
        }
      },
    );
  }

  Future<void> _fetchUserLocation({bool showFeedback = false, bool shouldAnimate = false}) async {
    final pos = await GpsService.getCurrentLocation();
    if (pos != null && mounted) {
      setState(() {
        _userPosition = pos;
      });
      _initMapMarkersAndHeatmap();

      // ONLY animate to user location if explicitly requested by tapping the GPS button
      if (shouldAnimate) {
        if (_targetRestaurant == null && _filteredList.isNotEmpty) {
          _filteredList.sort((a, b) {
            final distA = Geolocator.distanceBetween(pos.latitude, pos.longitude, a.latitude, a.longitude);
            final distB = Geolocator.distanceBetween(pos.latitude, pos.longitude, b.latitude, b.longitude);
            return distA.compareTo(distB);
          });
          _focusedRestaurant = _filteredList.first;
          _currentPageIndex = 0;
          if (_pageController.hasClients) {
            _pageController.jumpToPage(0);
          }
        }
        _animateMapToLocation(pos.latitude, pos.longitude);
      }

      if (showFeedback) {
        final source = GpsService.lastLocationSource;
        final city = GpsService.lastKnownCity;
        final locationLabel = city != null ? '$city ($source)' : source;
        HygieneFeedback.showSuccess(context, 'Location updated: $locationLabel');
      }
    }
  }

  void _initMapMarkersAndHeatmap() {
    final Set<Marker> newMarkers = {};
    final Set<Circle> newHeatmapCircles = {};

    for (var i = 0; i < _filteredList.length; i++) {
      final r = _filteredList[i];
      final pos = LatLng(r.latitude, r.longitude);
      final isDest = _targetRestaurant?.id == r.id;

      // Marker Icon Color based on Hygiene Risk Category
      BitmapDescriptor markerColor;
      switch (r.riskCategory) {
        case RiskCategory.safe:
          markerColor = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
          break;
        case RiskCategory.moderate:
          markerColor = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
          break;
        case RiskCategory.high:
          markerColor = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
          break;
      }

      newMarkers.add(
        Marker(
          markerId: MarkerId(r.id),
          position: pos,
          icon: isDest ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose) : markerColor,
          infoWindow: InfoWindow(
            title: isDest ? '🏁 ${r.name}' : r.name,
            snippet: isDest ? 'Destination • Tap to view details' : 'Risk: ${r.hygieneRiskScore.toStringAsFixed(1)} | ${r.category}',
            onTap: () {
              Navigator.pushNamed(context, AppRoutes.restaurantDetail, arguments: r);
            },
          ),
          onTap: () {
            _onMarkerTapped(i, r);
          },
        ),
      );

      // Semi-transparent Risk Heatmap Zone Circle (only in exploration mode)
      if (!_isNavigationMode) {
        Color circleColor;
        switch (r.riskCategory) {
          case RiskCategory.safe:
            circleColor = Colors.green.withValues(alpha: 0.18);
            break;
          case RiskCategory.moderate:
            circleColor = Colors.orange.withValues(alpha: 0.22);
            break;
          case RiskCategory.high:
            circleColor = Colors.red.withValues(alpha: 0.28);
            break;
        }

        newHeatmapCircles.add(
          Circle(
            circleId: CircleId('circle_${r.id}'),
            center: pos,
            radius: HeatmapZone.radiusMeters(r),
            fillColor: circleColor,
            strokeColor: circleColor.withValues(alpha: 0.6),
            strokeWidth: 1,
          ),
        );
      }
    }

    setState(() {
      _markers = newMarkers;
      _heatmapCircles = newHeatmapCircles;
    });

    if (_isNavigationMode && _targetRestaurant != null && _currentRouteResult == null) {
      _buildNavigationRoute(_targetRestaurant!);
    }
  }

  Future<void> _buildNavigationRoute(RestaurantModel dest) async {
    Position? currentPos = _userPosition;
    if (currentPos == null) {
      try {
        currentPos = await GpsService.getCurrentLocation();
        if (currentPos != null && mounted) {
          setState(() {
            _userPosition = currentPos;
          });
        }
      } catch (_) {}
    }

    final double startLat = currentPos?.latitude ?? _userPosition?.latitude ?? AppEnv.defaultLatitude;
    final double startLng = currentPos?.longitude ?? _userPosition?.longitude ?? AppEnv.defaultLongitude;
    final double endLat = dest.latitude;
    final double endLng = dest.longitude;

    final origin = LatLng(startLat, startLng);
    final destination = LatLng(endLat, endLng);

    // Initial instant distance calculation while real road route loads
    final double distanceMeters = Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
    final double distanceKm = distanceMeters / 1000.0;
    final int minutes = math.max(2, (distanceKm / 0.45).round() + 1);

    if (mounted) {
      setState(() {
        _etaMinutes = minutes;
        _routeDistanceStr = distanceKm < 1 ? '${distanceMeters.round()} m' : '${distanceKm.toStringAsFixed(1)} km';
      });
    }

    // Fetch real road turn-by-turn navigation following actual streets
    final route = await RoutingService.getRealRoadRoute(
      origin: origin,
      destination: destination,
    );

    if (mounted) {
      final newPolylines = <Polyline>{};

      // 1. Alternative Route if available (Grey color #94A3B8)
      if (route.alternativePoints.isNotEmpty) {
        newPolylines.add(
          Polyline(
            polylineId: const PolylineId('navigation_alternative_route'),
            points: route.alternativePoints,
            color: const Color(0xFF94A3B8).withValues(alpha: 0.75),
            width: 5,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            zIndex: 10,
          ),
        );
      }

      // 2. Glow / Outline for premium Google / Waze Navigation Look
      newPolylines.add(
        Polyline(
          polylineId: const PolylineId('navigation_active_route_outline'),
          points: route.points,
          color: const Color(0xFF1E3A8A), // Deep navy blue border
          width: 8,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          zIndex: 14,
        ),
      );

      // 3. Core bright Google Blue route line
      newPolylines.add(
        Polyline(
          polylineId: const PolylineId('navigation_active_route'),
          points: route.points,
          color: const Color(0xFF2563EB), // Google Maps vibrant blue
          width: 6,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          zIndex: 15,
        ),
      );

      setState(() {
        _currentRouteResult = route;
        _currentBearing = route.initialBearing;
        _etaMinutes = route.durationMinutes;
        _routeDistanceStr = route.distanceText;
        _polylines = newPolylines;
      });

      _fitRouteBounds(origin, destination, routePoints: route.points);
    }
  }

  void _fitRouteBounds(LatLng p1, LatLng p2, {List<LatLng>? routePoints}) {
    double minLat = math.min(p1.latitude, p2.latitude);
    double maxLat = math.max(p1.latitude, p2.latitude);
    double minLng = math.min(p1.longitude, p2.longitude);
    double maxLng = math.max(p1.longitude, p2.longitude);

    if (routePoints != null && routePoints.isNotEmpty) {
      for (final pt in routePoints) {
        if (pt.latitude < minLat) minLat = pt.latitude;
        if (pt.latitude > maxLat) maxLat = pt.latitude;
        if (pt.longitude < minLng) minLng = pt.longitude;
        if (pt.longitude > maxLng) maxLng = pt.longitude;
      }
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat - 0.003, minLng - 0.003),
      northeast: LatLng(maxLat + 0.003, maxLng + 0.003),
    );

    Future.delayed(const Duration(milliseconds: 300), () {
      _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    });
  }

  void _startJourney() {
    if (_targetRestaurant == null || _currentRouteResult == null || _currentRouteResult!.points.isEmpty) return;

    final origin = _userPosition != null
        ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
        : _defaultCenter;

    setState(() {
      _isActiveDrivingNavigation = true;
      _currentNavigationStepIndex = 0;
    });

    // 1. Camera 3D Driving Perspective Animation
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: origin,
          zoom: 19.0,
          tilt: 58.0,
          bearing: _currentRouteResult!.initialBearing,
        ),
      ),
    );

    // 2. Play subtle feedback
    HygieneFeedback.showSuccess(
      context,
      'Starting journey to ${_targetRestaurant!.name}. Follow route.',
    );

    // 3. Track Real Live Device GPS Movement
    _positionStreamSub?.cancel();
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2,
    );

    _positionStreamSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position pos) {
      if (!_isActiveDrivingNavigation || _targetRestaurant == null || !mounted) {
        return;
      }

      final newLatLng = LatLng(pos.latitude, pos.longitude);
      final double heading = pos.heading > 0 ? pos.heading : _currentBearing;

      // Update remaining distance & dynamic ETA in real time
      final double remainingMeters = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        _targetRestaurant!.latitude,
        _targetRestaurant!.longitude,
      );
      final int remMins = math.max(1, (remainingMeters / 450).round());
      final String remDistStr = remainingMeters < 1000
          ? '${remainingMeters.round()} m'
          : '${(remainingMeters / 1000).toStringAsFixed(1)} km';

      // Check next turn instruction step progress
      final steps = _currentRouteResult?.steps ?? [];
      int stepIdx = _currentNavigationStepIndex;
      if (steps.isNotEmpty && stepIdx < steps.length - 1) {
        final distToNextStep = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          steps[stepIdx + 1].location.latitude,
          steps[stepIdx + 1].location.longitude,
        );
        if (distToNextStep < 30) {
          stepIdx++;
        }
      }

      setState(() {
        _userPosition = pos;
        _currentBearing = heading;
        _currentNavigationStepIndex = stepIdx;
        _etaMinutes = remMins;
        _routeDistanceStr = remDistStr;
      });

      // Smoothly follow user movement with 3D camera
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: newLatLng,
            zoom: 19.0,
            tilt: 58.0,
            bearing: heading,
          ),
        ),
      );

      // Check arrival condition (sub-25m to destination)
      if (remainingMeters < 25) {
        _positionStreamSub?.cancel();
        _onArrivedAtDestination();
      }
    });
  }

  void _onArrivedAtDestination() {
    if (!mounted) return;
    setState(() {
      _isActiveDrivingNavigation = false;
    });
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.sports_score_rounded, color: Color(0xFF059669), size: 28),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('You Have Arrived!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
            ],
          ),
          content: Text(
            'You have arrived at ${_targetRestaurant?.name ?? "destination"}.',
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _exitNavigationMode();
              },
              child: const Text('Done', style: TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _reCenterNavigationCamera() {
    final target = _userPosition != null
        ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
        : _defaultCenter;
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          zoom: 19.0,
          tilt: 58.0,
          bearing: _currentBearing,
        ),
      ),
    );
  }

  void _toggleVoiceMute() {
    setState(() {
      _isVoiceMuted = !_isVoiceMuted;
    });
    HygieneFeedback.showSuccess(
      context,
      _isVoiceMuted ? 'Voice Guidance Muted' : 'Voice Guidance Enabled',
      duration: const Duration(seconds: 2),
    );
  }

  String _calculateArrivalTime(int minutes) {
    final now = DateTime.now().add(Duration(minutes: minutes));
    final hour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final minuteStr = now.minute.toString().padLeft(2, '0');
    final period = now.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minuteStr $period';
  }

  IconData _getManeuverIcon(String maneuver) {
    final m = maneuver.toLowerCase();
    if (m.contains('right') || m.contains('fork-right')) return Icons.turn_right_rounded;
    if (m.contains('left') || m.contains('fork-left')) return Icons.turn_left_rounded;
    if (m.contains('u-turn') || m.contains('uturn')) return Icons.u_turn_left_rounded;
    if (m.contains('roundabout') || m.contains('rotary')) return Icons.roundabout_right_rounded;
    if (m.contains('arrive')) return Icons.sports_score_rounded;
    return Icons.straight_rounded;
  }

  String _getNextInstruction() {
    if (_currentRouteResult != null &&
        _currentNavigationStepIndex + 1 < _currentRouteResult!.steps.length) {
      return _currentRouteResult!.steps[_currentNavigationStepIndex + 1].instruction;
    }
    return 'Continue on destination road';
  }

  void _openStepListModal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        final steps = _currentRouteResult?.steps ?? [];
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 44,
                height: 4.5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Turn-by-Turn Directions',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppTheme.navyColor,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: isDark ? Colors.white70 : Colors.black87),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: steps.isEmpty
                    ? Center(
                        child: Text(
                          'Calculating step-by-step turns...',
                          style: TextStyle(color: isDark ? Colors.white60 : Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: steps.length,
                        separatorBuilder: (ctx, i) => const Divider(height: 16),
                        itemBuilder: (ctx, i) {
                          final step = steps[i];
                          final isCurrent = i == _currentNavigationStepIndex && _isActiveDrivingNavigation;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? const Color(0xFF059669)
                                      : (isDark ? const Color(0xFF282828) : const Color(0xFFF1F5F9)),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _getManeuverIcon(step.maneuver),
                                  color: isCurrent ? Colors.white : (isDark ? Colors.white70 : AppTheme.navyColor),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      step.instruction,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      step.distanceText,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _exitNavigationMode() {
    _positionStreamSub?.cancel();
    setState(() {
      _isNavigationMode = false;
      _isActiveDrivingNavigation = false;
      _isRoutePreviewExpanded = false;
      _currentRouteResult = null;
      _polylines.clear();
      _targetRestaurant = null;
      _filteredList = _allRestaurants;
    });
    _initMapMarkersAndHeatmap();
    if (_userPosition != null) {
      _animateMapToLocation(_userPosition!.latitude, _userPosition!.longitude);
    }
  }

  void _onMarkerTapped(int index, RestaurantModel restaurant) {
    setState(() {
      _focusedRestaurant = restaurant;
      _currentPageIndex = index;
    });

    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
    _animateMapToLocation(restaurant.latitude, restaurant.longitude);
  }

  void _onPageChanged(int index) {
    if (index >= 0 && index < _filteredList.length) {
      final restaurant = _filteredList[index];
      setState(() {
        _focusedRestaurant = restaurant;
        _currentPageIndex = index;
      });
      _animateMapToLocation(restaurant.latitude, restaurant.longitude);
    }
  }

  void _animateMapToLocation(double lat, double lng) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(lat, lng),
          zoom: 17.5,
          tilt: 60.0,
          bearing: 45.0,
        ),
      ),
    );
  }

  void _filterRestaurantList() {
    final query = _listSearchCtrl.text.toLowerCase().trim();
    List<RestaurantModel> temp = List.from(_allRestaurants);

    if (query.isNotEmpty) {
      temp = temp.where((r) {
        return r.name.toLowerCase().contains(query) ||
            r.category.toLowerCase().contains(query) ||
            r.address.toLowerCase().contains(query);
      }).toList();
    }

    if (_filterRisk != 'All') {
      temp = temp.where((r) {
        if (_filterRisk == 'Safe') return r.riskCategory == RiskCategory.safe;
        if (_filterRisk == 'Moderate') return r.riskCategory == RiskCategory.moderate;
        if (_filterRisk == 'High Risk') return r.riskCategory == RiskCategory.high;
        return true;
      }).toList();
    }

    setState(() {
      _filteredList = temp;
      _currentPageIndex = 0;
    });

    _initMapMarkersAndHeatmap();

    if (_filteredList.isNotEmpty && _mapController != null) {
      _animateMapToLocation(_filteredList[0].latitude, _filteredList[0].longitude);
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    }
  }

  String _calculateDistanceText(double lat, double lng) {
    if (_userPosition != null) {
      final meters = Geolocator.distanceBetween(_userPosition!.latitude, _userPosition!.longitude, lat, lng);
      if (meters < 1000) {
        return '${meters.round()} m away';
      }
      final km = meters / 1000.0;
      return '${km.toStringAsFixed(1)} km away';
    }
    return '0.3 km away';
  }

  Color _getRiskColor(RiskCategory category) {
    switch (category) {
      case RiskCategory.safe:
        return const Color(0xFF10B981);
      case RiskCategory.moderate:
        return const Color(0xFFF59E0B);
      case RiskCategory.high:
        return const Color(0xFFEF4444);
    }
  }

  void _showFilterBottomSheet() {
    String tempFilter = _filterRisk;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Drag Handle Bar
                      Center(
                        child: Container(
                          width: 44,
                          height: 4.5,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white24 : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Header Title & Reset Button Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [AppTheme.primaryColor, Color(0xFF14B8A6)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryColor.withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.filter_list_rounded, color: Colors.white, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t('filter_by_hygiene'),
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : AppTheme.navyColor,
                                    ),
                                  ),
                                  Text(
                                    'Filter outlets by health inspection level',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () {
                              setSheetState(() => tempFilter = 'All');
                            },
                            child: Text(t('reset'), style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Choice Chips / Filter Cards
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          {'raw': 'All', 'label': t('all'), 'desc': 'All ratings'},
                          {'raw': 'Safe', 'label': t('safe'), 'desc': 'Grade A (0-30 Risk)'},
                          {'raw': 'Moderate', 'label': t('moderate'), 'desc': 'Grade B (31-60 Risk)'},
                          {'raw': 'High Risk', 'label': t('high_risk'), 'desc': 'Grade C (>60 Risk)'},
                        ].map((item) {
                          final filterKey = item['raw']!;
                          final displayLabel = item['label']!;
                          final isSelected = tempFilter == filterKey;
                          Color chipColor = AppTheme.primaryColor;
                          if (filterKey == 'Safe') chipColor = const Color(0xFF10B981);
                          if (filterKey == 'Moderate') chipColor = const Color(0xFFF59E0B);
                          if (filterKey == 'High Risk') chipColor = const Color(0xFFEF4444);

                          return ChoiceChip(
                            label: Text(displayLabel),
                            selected: isSelected,
                            selectedColor: chipColor,
                            backgroundColor: isDark ? const Color(0xFF282828) : Colors.grey.shade100,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              fontSize: 13,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isSelected ? chipColor : (isDark ? Colors.white12 : Colors.grey.shade300),
                              ),
                            ),
                            onSelected: (val) {
                              if (val) {
                                setSheetState(() => tempFilter = filterKey);
                              }
                            },
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 22),

                      // Apply Filter Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () {
                            setState(() {
                              _filterRisk = tempFilter;
                              _filterRestaurantList();
                            });
                            Navigator.pop(ctx);
                          },
                          child: Text(
                            t('apply_filter'),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: languageManager,
      builder: (context, _) {
        if (_isMapLoading) {
          return Scaffold(
            appBar: widget.showAppBar ? CustomAppBar(title: t('map'), showBackButton: Navigator.canPop(context)) : null,
            body: const MapSkeletonLoader(),
          );
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final initialTarget = _focusedRestaurant != null
            ? LatLng(_focusedRestaurant!.latitude, _focusedRestaurant!.longitude)
            : (_userPosition != null
                ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
                : _defaultCenter);

        // Dynamically apply current theme to active map controller on rebuild
        AppMapTheme.applyTheme(_mapController, isDark);

        return Scaffold(
          appBar: widget.showAppBar ? CustomAppBar(title: t('map'), showBackButton: Navigator.canPop(context)) : null,
          body: Stack(
            children: [
              // 1. FULL-SCREEN GOOGLE MAP BACKGROUND
              GoogleMap(
                mapType: _currentMapType,
                style: AppMapTheme.getMapStyle(isDark),
                initialCameraPosition: CameraPosition(
                  target: initialTarget,
                  zoom: 17.5,
                  tilt: 60.0,
                  bearing: 45.0,
                ),
                buildingsEnabled: true,
                onMapCreated: (controller) {
                  _mapController = controller;
                  AppMapTheme.applyTheme(controller, isDark);
                  if (_targetRestaurant != null && _isNavigationMode) {
                    _buildNavigationRoute(_targetRestaurant!);
                  } else if (_targetRestaurant != null) {
                    _animateMapToLocation(_targetRestaurant!.latitude, _targetRestaurant!.longitude);
                  } else if (_focusedRestaurant != null) {
                    _animateMapToLocation(_focusedRestaurant!.latitude, _focusedRestaurant!.longitude);
                  }
                },
                markers: _markers,
                polylines: _polylines,
                circles: {
                  if (_showHeatmap && !_isNavigationMode) ..._heatmapCircles,
                },
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
              ),

              // 2. TOP OVERLAYS: ROUTE PREVIEW HEADER, ACTIVE DRIVING HUD, OR EXPLORATION SEARCH BAR
              if (_isActiveDrivingNavigation && _targetRestaurant != null)
                _buildActiveNavigationTopHUD(isDark)
              else if (_isNavigationMode && _targetRestaurant != null)
                _buildRoutePreviewHeader(isDark)
              else if (_targetRestaurant != null)
                Positioned(
                  top: widget.showAppBar ? 8 : 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.storefront_rounded, color: AppTheme.primaryColor, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Outlet: ${_targetRestaurant!.name}',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : AppTheme.navyColor),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          onTap: _exitNavigationMode,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text('View All', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Positioned(
                  top: widget.showAppBar ? 2 : 12,
                  left: 16,
                  right: 16,
                  child: Column(
                    children: [
                      // Floating Search Input Bar with Speech-to-Text Mic Icon in front of Filter Button
                      ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E1E1E).withValues(alpha: 0.92) : Colors.white.withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(color: isDark ? Colors.white24 : Colors.white.withValues(alpha: 0.6)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.10),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: _listSearchCtrl,
                              onChanged: (_) => _filterRestaurantList(),
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: t('search_map_hint'),
                                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade500, fontSize: 14),
                                prefixIcon: Icon(Icons.search, color: isDark ? Colors.white70 : AppTheme.navyColor),
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_listSearchCtrl.text.isNotEmpty)
                                      IconButton(
                                        icon: Icon(Icons.clear, size: 18, color: isDark ? Colors.white60 : Colors.grey),
                                        onPressed: () {
                                          _listSearchCtrl.clear();
                                          _filterRestaurantList();
                                        },
                                      ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.mic_rounded,
                                        color: AppTheme.primaryColor,
                                      ),
                                      tooltip: 'Voice Search',
                                      onPressed: _startVoiceSearch,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.tune, color: AppTheme.primaryColor),
                                      tooltip: 'Filter Outlets',
                                      onPressed: _showFilterBottomSheet,
                                    ),
                                  ],
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Floating Risk Heatmap Legend Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E1E1E).withValues(alpha: 0.92) : Colors.white.withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: isDark ? Colors.white24 : Colors.white.withValues(alpha: 0.5)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildLegendDot(t('safe'), Colors.green, isDark: isDark),
                                _buildLegendDot(t('moderate'), Colors.amber, isDark: isDark),
                                _buildLegendDot(t('high_risk'), Colors.red, isDark: isDark),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // 3. MAP CONTROLS: GOOGLE SATELLITE LAYER, HEATMAP TOGGLE & MY LOCATION BUTTONS
              Positioned(
                right: 16,
                bottom: _isNavigationMode ? 140 : 260,
                child: Column(
                  children: [
                    GestureDetector(
                      onLongPress: _showMapTypeOptionsSheet,
                      child: FloatingActionButton.small(
                        heroTag: 'btn_satellite',
                        onPressed: _toggleMapType,
                        backgroundColor: _isSatellite ? AppTheme.navyColor : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
                        foregroundColor: _isSatellite ? Colors.white : (isDark ? Colors.white : AppTheme.navyColor),
                        tooltip: 'Toggle Satellite / Map Layer',
                        child: Icon(_isSatellite ? Icons.satellite_alt : Icons.layers_outlined, size: 20),
                      ),
                    ),
                    if (!_isNavigationMode) ...[
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'btn_heatmap',
                        onPressed: () {
                          setState(() {
                            _showHeatmap = !_showHeatmap;
                          });
                        },
                        backgroundColor: _showHeatmap ? Colors.red.shade600 : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
                        foregroundColor: _showHeatmap ? Colors.white : (isDark ? Colors.white : AppTheme.navyColor),
                        tooltip: 'Toggle Heatmap',
                        child: const Icon(Icons.local_fire_department, size: 20),
                      ),
                    ],
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'btn_gps',
                      onPressed: () {
                        if (_isActiveDrivingNavigation) {
                          _reCenterNavigationCamera();
                        } else {
                          _fetchUserLocation(showFeedback: true, shouldAnimate: true);
                        }
                      },
                      backgroundColor: const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      tooltip: _isActiveDrivingNavigation ? 'Re-center 3D Navigation' : 'Locate My Exact Position',
                      child: Icon(_isActiveDrivingNavigation ? Icons.navigation_rounded : Icons.my_location_rounded, size: 20),
                    ),
                  ],
                ),
              ),

              // 4. BOTTOM OVERLAYS: ACTIVE DRIVING HUD, ROUTE PREVIEW SHEET, OR RESTAURANT CARDS
              if (_isActiveDrivingNavigation && _targetRestaurant != null)
                _buildActiveNavigationBottomHUD(isDark)
              else if (_isNavigationMode && _targetRestaurant != null)
                _buildRoutePreviewBottomCard(isDark)
              else
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 16,
                  child: SafeArea(
                    top: false,
                    bottom: true,
                    child: SizedBox(
                      height: 235,
                    child: _filteredList.isEmpty
                        ? Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E1E1E).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: isDark ? Colors.white12 : Colors.transparent),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: Text(
                                'No outlets match your search filter',
                                style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ),
                          )
                        : PageView.builder(
                            controller: _pageController,
                            itemCount: _filteredList.length,
                            onPageChanged: _onPageChanged,
                            itemBuilder: (context, index) {
                              final restaurant = _filteredList[index];
                              final isSelectedCard = index == _currentPageIndex;
                              final distanceText = _calculateDistanceText(restaurant.latitude, restaurant.longitude);
                              final riskColor = _getRiskColor(restaurant.riskCategory);

                              return GestureDetector(
                                onTap: () {
                                  Navigator.pushNamed(context, AppRoutes.restaurantDetail, arguments: restaurant);
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                                    borderRadius: BorderRadius.circular(24),
                                    border: isSelectedCard
                                        ? Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.8), width: 2)
                                        : Border.all(color: isDark ? Colors.white12 : Colors.transparent),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: isSelectedCard ? (isDark ? 0.35 : 0.18) : (isDark ? 0.25 : 0.10)),
                                        blurRadius: isSelectedCard ? 18 : 12,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(24),
                                    child: Stack(
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Top Image Container with Badge
                                            SizedBox(
                                              height: 125,
                                              width: double.infinity,
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  Image(
                        image: outletImageProvider(restaurant.imageUrl),
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (ctx, err, stack) => Container(
                                                      color: isDark ? const Color(0xFF282828) : Colors.grey.shade300,
                                                      child: Icon(Icons.restaurant, size: 40, color: isDark ? Colors.white38 : Colors.grey),
                                                    ),
                                                  ),
                                                  // Top Right Hygiene Risk Chip Badge
                                                  Positioned(
                                                    top: 8,
                                                    right: 8,
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: riskColor,
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Text(
                                                        restaurant.riskCategory.name.toUpperCase(),
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 10,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Card Body Container with Backdrop Filter Blur
                                            Expanded(
                                              child: ClipRRect(
                                                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                                                child: BackdropFilter(
                                                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                                    color: isDark ? const Color(0xFF1E1E1E).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.88),
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                      children: [
                                                        Text(
                                                          restaurant.name,
                                                          style: TextStyle(
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 15,
                                                            color: isDark ? Colors.white : AppTheme.navyColor,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                        Builder(
                                                          builder: (context) {
                                                            final ratingInfo = RestaurantStoreService.getRatingSync(
                                                              restaurant.id,
                                                              restaurantName: restaurant.name,
                                                            );
                                                            return Row(
                                                              children: [
                                                                Icon(
                                                                  ratingInfo.hasReviews ? Icons.star_rounded : Icons.star_border_rounded,
                                                                  color: ratingInfo.hasReviews ? Colors.amber : (isDark ? Colors.white38 : Colors.grey.shade400),
                                                                  size: 16,
                                                                ),
                                                                const SizedBox(width: 3),
                                                                Text(
                                                                  ratingInfo.ratingText,
                                                                  style: TextStyle(
                                                                    fontWeight: FontWeight.bold,
                                                                    fontSize: 12,
                                                                    color: ratingInfo.hasReviews
                                                                        ? (isDark ? Colors.white : Colors.black87)
                                                                        : (isDark ? Colors.white54 : Colors.grey.shade600),
                                                                  ),
                                                                ),
                                                                const SizedBox(width: 4),
                                                                Text(
                                                                  ratingInfo.hasReviews ? '(${ratingInfo.totalReviews})' : '(No Review)',
                                                                  style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 11),
                                                                ),
                                                                const SizedBox(width: 6),
                                                                Text('\u2022', style: TextStyle(color: isDark ? Colors.white30 : Colors.grey.shade400)),
                                                                const SizedBox(width: 6),
                                                                Icon(Icons.location_on_outlined, size: 13, color: isDark ? Colors.white54 : Colors.grey),
                                                                const SizedBox(width: 2),
                                                                Expanded(
                                                                  child: Text(
                                                                    distanceText,
                                                                    style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700, fontSize: 11, fontWeight: FontWeight.w500),
                                                                    maxLines: 1,
                                                                    overflow: TextOverflow.ellipsis,
                                                                  ),
                                                                ),
                                                              ],
                                                            );
                                                          },
                                                        ),
                                                        Row(
                                                          children: [
                                                            _buildCardTag(
                                                              restaurant.category,
                                                              isDark ? Colors.pink.shade900.withValues(alpha: 0.4) : Colors.pink.shade50,
                                                              isDark ? Colors.pink.shade200 : Colors.pink.shade700,
                                                            ),
                                                            const SizedBox(width: 6),
                                                            _buildCardTag(
                                                              'Indoor Seating',
                                                              isDark ? Colors.blue.shade900.withValues(alpha: 0.4) : Colors.blue.shade50,
                                                              isDark ? Colors.blue.shade200 : Colors.blue.shade700,
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

  Widget _buildRoutePreviewHeader(bool isDark) {
    return Positioned(
      top: widget.showAppBar ? 8 : 16,
      left: 14,
      right: 14,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF1A73E8),
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Your location',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : const Color(0xFF1E293B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 4.5, top: 2, bottom: 2),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 3,
                            height: 12,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white24 : Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.location_pin, color: Color(0xFFEA4335), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _targetRestaurant?.name ?? 'Destination',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : AppTheme.navyColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    IconButton(
                      icon: Icon(Icons.swap_vert_rounded, color: isDark ? Colors.white70 : AppTheme.navyColor, size: 22),
                      tooltip: 'Swap Route',
                      onPressed: () {
                        if (_targetRestaurant != null) _buildNavigationRoute(_targetRestaurant!);
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: isDark ? Colors.white60 : Colors.grey.shade600, size: 20),
                      tooltip: 'Exit Navigation',
                      onPressed: _exitNavigationMode,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTransportTab('driving', Icons.directions_car_rounded, '$_etaMinutes min', isDark),
                _buildTransportTab('motorcycle', Icons.two_wheeler_rounded, '${math.max(1, (_etaMinutes * 0.8).round())} min', isDark),
                _buildTransportTab('walking', Icons.directions_walk_rounded, '${_etaMinutes * 4} min', isDark),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransportTab(String mode, IconData icon, String timeStr, bool isDark) {
    final isSelected = _transportMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _transportMode = mode;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF0F766E).withValues(alpha: 0.25) : const Color(0xFFCCFBF1))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F766E) : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? const Color(0xFF0F766E) : (isDark ? Colors.white54 : Colors.grey.shade600),
            ),
            const SizedBox(width: 6),
            Text(
              timeStr,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? const Color(0xFF0F766E) : (isDark ? Colors.white70 : Colors.grey.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveNavigationTopHUD(bool isDark) {
    final steps = _currentRouteResult?.steps ?? [];
    final step = (steps.isNotEmpty && _currentNavigationStepIndex < steps.length)
        ? steps[_currentNavigationStepIndex]
        : null;

    final maneuver = step?.maneuver ?? 'straight';
    final instruction = step?.instruction ?? 'Proceed to destination';
    final distanceText = step?.distanceText ?? _routeDistanceStr;

    return Positioned(
      top: widget.showAppBar ? 8 : 16,
      left: 14,
      right: 14,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF064E3B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF059669), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF059669),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(_getManeuverIcon(maneuver), color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'In $distanceText',
                        style: const TextStyle(
                          color: Color(0xFF6EE7B7),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.circle, color: Color(0xFF6EE7B7), size: 4),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Then: ${_getNextInstruction()}',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    instruction,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.list_alt_rounded, color: Colors.white70, size: 22),
              tooltip: 'Turn by turn steps',
              onPressed: _openStepListModal,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoutePreviewBottomCard(bool isDark) {
    if (_targetRestaurant == null) return const SizedBox.shrink();

    final restaurant = _targetRestaurant!;
    final riskColor = _getRiskColor(restaurant.riskCategory);

    return Positioned(
      left: 14,
      right: 14,
      bottom: 16,
      child: SafeArea(
        top: false,
        bottom: true,
        child: GestureDetector(
          onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null) {
            if (details.primaryVelocity! < -80) {
              if (!_isRoutePreviewExpanded) {
                setState(() => _isRoutePreviewExpanded = true);
              }
            } else if (details.primaryVelocity! > 80) {
              if (_isRoutePreviewExpanded) {
                setState(() => _isRoutePreviewExpanded = false);
              }
            }
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.14),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _isRoutePreviewExpanded = !_isRoutePreviewExpanded;
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Column(
                  children: [
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () {
                        Navigator.pushNamed(context, AppRoutes.restaurantDetail, arguments: restaurant);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: SizedBox(
                                width: 68,
                                height: 68,
                                child: Image(
                        image: outletImageProvider(restaurant.imageUrl),
                                  fit: BoxFit.cover,
                                  errorBuilder: (ctx, err, stack) => Container(
                                    color: isDark ? const Color(0xFF282828) : Colors.grey.shade300,
                                    child: Icon(Icons.restaurant, size: 28, color: isDark ? Colors.white38 : Colors.grey),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    restaurant.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: isDark ? Colors.white : AppTheme.navyColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Builder(
                                    builder: (context) {
                                      final ratingInfo = RestaurantStoreService.getRatingSync(
                                        restaurant.id,
                                        restaurantName: restaurant.name,
                                      );
                                      return Row(
                                        children: [
                                          Icon(
                                            ratingInfo.hasReviews ? Icons.star_rounded : Icons.star_border_rounded,
                                            color: ratingInfo.hasReviews ? Colors.amber : (isDark ? Colors.white38 : Colors.grey.shade400),
                                            size: 16,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            ratingInfo.ratingText,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: ratingInfo.hasReviews
                                                  ? (isDark ? Colors.white : Colors.black87)
                                                  : (isDark ? Colors.white54 : Colors.grey.shade600),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            ratingInfo.hasReviews ? '(${ratingInfo.totalReviews})' : '(No Review)',
                                            style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 11),
                                          ),
                                          const SizedBox(width: 6),
                                          Text('•', style: TextStyle(color: isDark ? Colors.white30 : Colors.grey.shade400)),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              restaurant.category,
                                              style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700, fontSize: 11, fontWeight: FontWeight.w500),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: riskColor,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          restaurant.riskCategory.name.toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 9.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Tap to view outlet details',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? Colors.white38 : Colors.grey.shade500,
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
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                  ],
                ),
                crossFadeState: _isRoutePreviewExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 280),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '$_etaMinutes min',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF059669),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '($_routeDistanceStr)',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF059669)),
                          const SizedBox(width: 3),
                          Text(
                            'Fastest route now • Usual traffic',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white54 : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF282828) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Arrival ${_calculateArrivalTime(_etaMinutes)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : AppTheme.navyColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: ElevatedButton.icon(
                      onPressed: _startJourney,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 3,
                      ),
                      icon: const Icon(Icons.navigation_rounded, size: 20),
                      label: const Text(
                        'Start',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: OutlinedButton.icon(
                      onPressed: _openStepListModal,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? Colors.white : AppTheme.navyColor,
                        side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.alt_route_rounded, size: 18),
                      label: const Text('Steps', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _exitNavigationMode,
                    style: IconButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF282828) : const Color(0xFFF1F5F9),
                      padding: const EdgeInsets.all(12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: Icon(Icons.close_rounded, color: isDark ? Colors.white70 : Colors.black87, size: 20),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildActiveNavigationBottomHUD(bool isDark) {
    return Positioned(
      left: 14,
      right: 14,
      bottom: 16,
      child: SafeArea(
        top: false,
        bottom: true,
        child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        '$_etaMinutes min',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF059669),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _routeDistanceStr,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ETA: ${_calculateArrivalTime(_etaMinutes)} • Navigating',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.explore_rounded, color: Color(0xFF0F766E), size: 24),
              tooltip: 'Re-center 3D View',
              onPressed: _reCenterNavigationCamera,
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(
                _isVoiceMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: isDark ? Colors.white70 : Colors.grey.shade700,
                size: 22,
              ),
              tooltip: 'Audio guidance',
              onPressed: _toggleVoiceMute,
            ),
            const SizedBox(width: 6),
            ElevatedButton(
              onPressed: _exitNavigationMode,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.close_rounded, size: 16),
                  SizedBox(width: 4),
                  Text('End', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildCardTag(String label, Color bg, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: text),
      ),
    );
  }

  Widget _buildLegendDot(String label, Color color, {bool isDark = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.navyColor),
        ),
      ],
    );
  }
}

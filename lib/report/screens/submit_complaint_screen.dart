import '../../core/widgets/app_search_field.dart';
import '../../core/widgets/app_select_field.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/models/complaint_model.dart';
import '../../core/models/restaurant_model.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/language_manager.dart';
import '../../core/services/places_location_service.dart';
import '../../core/services/restaurant_store_service.dart';
import '../../core/services/customer_store_service.dart';
import '../../core/services/notification_service.dart';
import '../../notifications/models/notification_model.dart';
import '../../core/theme/app_map_theme.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/utils/translations.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../widgets/complaint_step_tracker.dart';

class SubmitComplaintScreen extends StatefulWidget {
  const SubmitComplaintScreen({super.key});

  @override
  State<SubmitComplaintScreen> createState() => _SubmitComplaintScreenState();
}

class _SubmitComplaintScreenState extends State<SubmitComplaintScreen> {
  int _currentStep = 0;
  bool _isInitialized = false;

  RestaurantModel? _selectedRestaurant;
  double _selectedLat = 3.1466;
  double _selectedLong = 101.6958;

  String _selectedCategory = 'Pest Infestation';
  final List<String> _selectedIssues = [];
  String _description = '';
  final _descriptionController = TextEditingController();

  final List<File> _attachedPhotoFiles = [];
  final List<String> _attachedPhotoUrls = [];
  final ImagePicker _picker = ImagePicker();

  final _customNameController = TextEditingController();
  final _customAddressController = TextEditingController();
  String _customCategory = 'Malay Local';

  Timer? _customAddressDebounce;
  PlaceSearchRequest? _customAddressRequest;
  List<PlaceSuggestion> _customAddressSuggestions = [];
  bool _isSearchingCustomAddress = false;
  final FocusNode _customAddressFocusNode = FocusNode();

  static const _otherRestaurantOption = RestaurantModel(
    id: 'other_new',
    name: 'Other (Add New Premises)',
    address: 'Custom Location',
    category: 'Other',
    latitude: 3.1466,
    longitude: 101.6958,
    hygieneRiskScore: 0,
    riskCategory: RiskCategory.safe,
    status: RestaurantStatus.approved,
    violationCount: 0,
    imageUrl: '',
    lastUpdated: '',
  );

  String _reverseGeocodeLocation(double lat, double lng) {
    return PlacesLocationService.reverseGeocode(lat, lng);
  }

  final List<String> _stepTitles = [
    'Choose Outlet',
    'Hygiene Issues',
    'Report Details',
    'Review Check',
  ];

  final List<String> _categories = [
    'Pest Infestation',
    'Food Quality & Poisoning',
    'Unclean Utensils',
    'Poor Staff Hygiene',
    'Employee Rudeness & Service',
    'Waste & Drainage',
    'Other Issue',
  ];

  final Map<String, IconData> _categoryIcons = {
    'Pest Infestation': Icons.pest_control_rounded,
    'Food Quality & Poisoning': Icons.sick_rounded,
    'Unclean Utensils': Icons.flatware_rounded,
    'Poor Staff Hygiene': Icons.clean_hands_rounded,
    'Employee Rudeness & Service': Icons.record_voice_over_rounded,
    'Waste & Drainage': Icons.delete_sweep_rounded,
    'Other Issue': Icons.report_problem_rounded,
  };

  final Map<String, Color> _categoryColors = {
    'Pest Infestation': const Color(0xFFDC2626),
    'Food Quality & Poisoning': const Color(0xFFE11D48),
    'Unclean Utensils': const Color(0xFFD97706),
    'Poor Staff Hygiene': const Color(0xFF0D9488),
    'Employee Rudeness & Service': const Color(0xFFEA580C),
    'Waste & Drainage': const Color(0xFF4B5563),
    'Other Issue': const Color(0xFF6366F1),
  };

  final Map<String, String> _categorySubtitles = {
    'Pest Infestation': 'Cockroaches, rats, flies & pests',
    'Food Quality & Poisoning': 'Food poisoning, rotten or raw food',
    'Unclean Utensils': 'Dirty cutlery, oily plates & ice',
    'Poor Staff Hygiene': 'No gloves, bare hands, dirty attire',
    'Employee Rudeness & Service': 'Rude staff, abusive or hostile',
    'Waste & Drainage': 'Overflowing grease trap & drains',
    'Other Issue': 'Facility damage & general issues',
  };

  final Map<String, List<String>> _issueChecklistMap = {
    'Pest Infestation': [
      'Cockroaches near food prep area',
      'Rats / Mice droppings spotted',
      'Flies or maggots on ready-to-eat food',
      'Ants / insects crawling on tables',
      'Uncovered open trash attracting pests',
    ],
    'Food Quality & Poisoning': [
      'Severe food poisoning / stomach illness',
      'Undercooked raw poultry or meat served',
      'Foul / sour rotten odor from food',
      'Expired fridge ingredients or mold',
      'Foreign objects (plastic, hair, metal) in dish',
    ],
    'Unclean Utensils': [
      'Oily cups, stained glasses & residue',
      'Dirty cutlery with dried food stains',
      'Moldy ice machine / drink dispenser',
      'Unsanitized serving trays / chopsticks',
    ],
    'Poor Staff Hygiene': [
      'No gloves, hairnets or masks worn',
      'Staff coughing or sneezing over food',
      'Bare unwashed hands touching food',
      'Handling money/trash then touching food',
    ],
    'Employee Rudeness & Service': [
      'Rude, shouting or abusive staff behavior',
      'Dismissed hygiene concerns with hostility',
      'Refused refund / exchange for contaminated food',
      'Unprofessional customer service attitude',
    ],
    'Waste & Drainage': [
      'Overflowing / clogged grease trap',
      'Foul sewer wastewater on floor',
      'Dirty, unsanitary restroom near dining area',
      'Overfilled trash bin emitting stench',
    ],
    'Other Issue': [
      'Poor kitchen ventilation & smoke',
      'Damaged ceiling or dripping water over food',
      'Unsafe premises / sanitation breach',
    ],
  };

  final Map<String, List<String>> _categoryTagsMap = {
    'Pest Infestation': [
      '#Cockroach',
      '#CockroachSpotted',
      '#RatDroppings',
      '#FliesOnFood',
      '#PestInKitchen',
      '#Maggots',
      '#AntsInfestation',
    ],
    'Food Quality & Poisoning': [
      '#Poison',
      '#FoodPoisoning',
      '#Rotten',
      '#RottenSmell',
      '#RawMeat',
      '#ExpiredFood',
      '#StomachAche',
      '#MoldyFood',
      '#ForeignObject',
    ],
    'Unclean Utensils': [
      '#DirtyUtensils',
      '#OilyPlates',
      '#MoldyIce',
      '#StainedCutlery',
      '#UnwashedCups',
      '#GreasyBowl',
      '#LipstickOnGlass',
    ],
    'Poor Staff Hygiene': [
      '#NoGloves',
      '#NoHairnet',
      '#DirtyApron',
      '#SneezingOverFood',
      '#UnwashedHands',
      '#SmokingInKitchen',
    ],
    'Employee Rudeness & Service': [
      '#Rude',
      '#HarshAttitude',
      '#Unprofessional',
      '#DisrespectfulStaff',
      '#RefusedAssistance',
      '#IgnoredCustomer',
      '#HostileBehavior',
    ],
    'Waste & Drainage': [
      '#GreaseTrap',
      '#DrainageSmell',
      '#DirtyRestroom',
      '#TrashOverflow',
      '#StagnantWater',
      '#FoulOdor',
    ],
    'Other Issue': [
      '#PoorVentilation',
      '#DirtyTables',
      '#SafetyHazard',
      '#GeneralHygiene',
      '#PremisesDamage',
    ],
  };

  @override
  void dispose() {
    _descriptionController.dispose();
    _customAddressRequest?.cancel();
    _customAddressDebounce?.cancel();
    _customAddressFocusNode.dispose();
    _customNameController.dispose();
    _customAddressController.dispose();
    super.dispose();
  }

  List<RestaurantModel> get _availableRestaurants {
    final List<RestaurantModel> list = [];
    final Set<String> seenIds = {};

    if (_selectedRestaurant != null && _selectedRestaurant!.id != 'other_new') {
      seenIds.add(_selectedRestaurant!.id);
      list.add(_selectedRestaurant!);
    }

    for (final r in RestaurantStoreService.restaurantsNotifier.value) {
      if (!seenIds.contains(r.id)) {
        seenIds.add(r.id);
        list.add(r);
      }
    }

    return list;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _isInitialized = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is RestaurantModel) {
        final existingIndex = RestaurantStoreService.restaurantsNotifier.value
            .indexWhere((r) => r.id == args.id);
        if (existingIndex != -1) {
          _selectedRestaurant =
              RestaurantStoreService.restaurantsNotifier.value[existingIndex];
        } else {
          _selectedRestaurant = args;
        }
        _selectedLat = _selectedRestaurant!.latitude;
        _selectedLong = _selectedRestaurant!.longitude;
      } else if (args is Map && args['restaurant'] is RestaurantModel) {
        _selectedRestaurant = args['restaurant'];
        _selectedLat = _selectedRestaurant!.latitude;
        _selectedLong = _selectedRestaurant!.longitude;
      } else {
        // Opened without specific arguments (e.g. from Home Screen "Report" button):
        // Leave unselected so user is prompted with "Please select the restaurant"
        _selectedRestaurant = null;
      }
    }
  }

  bool get _isOtherSelected => _selectedRestaurant?.id == 'other_new';

  bool get _hasPhotoAttached =>
      _attachedPhotoFiles.isNotEmpty || _attachedPhotoUrls.isNotEmpty;

  int get _totalPhotoCount =>
      _attachedPhotoFiles.length + _attachedPhotoUrls.length;

  bool get _hasRequiredReportInputs =>
      (_isOtherSelected
          ? _customNameController.text.trim().isNotEmpty && _customAddressController.text.trim().isNotEmpty
          : _selectedRestaurant != null) &&
      _selectedIssues.isNotEmpty && _description.trim().isNotEmpty && _hasPhotoAttached;

  bool _canProceedCurrentStep() {
    switch (_currentStep) {
      case 0:
        if (_isOtherSelected) {
          return _customNameController.text.trim().isNotEmpty &&
              _customAddressController.text.trim().isNotEmpty;
        }
        return _selectedRestaurant != null;
      case 1:
        return _selectedIssues.isNotEmpty;
      case 2:
        return _description.trim().isNotEmpty && _hasPhotoAttached;
      case 3:
        return _hasRequiredReportInputs;
      default:
        return false;
    }
  }

  // Validation Warning Message shown when Next button is disabled
  String _getValidationHint() {
    switch (_currentStep) {
      case 0:
        if (_isOtherSelected) {
          return 'Please fill in both the new restaurant name and address.';
        }
        return 'Please select an outlet premises to proceed.';
      case 1:
        return 'Please check at least 1 observed hygiene issue to proceed.';
      case 2:
        return 'Please add a description and at least one evidence photo to proceed.';
      default:
        return '';
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        setState(() {
          if (_totalPhotoCount < 4) {
            _attachedPhotoFiles.add(File(pickedFile.path));
          }
        });
      }
    } catch (e) {
      if (mounted) {
        HygieneFeedback.showError(context, 'Could not access image: $e');
      }
    }
  }

  void _showPhotoPickerOptionsModal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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

                  // Header with Icon & Close Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppTheme.primaryColor,
                                  Color(0xFF14B8A6),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryColor.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.add_a_photo_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Attach Photo Evidence',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.white
                                      : AppTheme.navyColor,
                                ),
                              ),
                              Text(
                                'Max 4 high-resolution photos',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],
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
                  const SizedBox(height: 10),
                  Text(
                    'Clear photos of food, utensils, or premises help health inspectors investigate and verify complaints quickly.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Option 1: Camera Card
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickImage(ImageSource.camera);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF282828)
                              : const Color(0xFFF0FDFA),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF0F766E).withValues(alpha: 0.4)
                                : const Color(
                                    0xFF0F766E,
                                  ).withValues(alpha: 0.25),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF0F766E),
                                    Color(0xFF14B8A6),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF0F766E,
                                    ).withValues(alpha: 0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Take Photo with Camera',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: isDark
                                              ? Colors.white
                                              : AppTheme.navyColor,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF0F766E,
                                          ).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: const Text(
                                          'Instant',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0F766E),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Capture live evidence on the spot with device camera',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Color(0xFF0F766E),
                              size: 15,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Option 2: Gallery Card
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickImage(ImageSource.gallery);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF282828)
                              : const Color(0xFFF0F9FF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF0284C7).withValues(alpha: 0.4)
                                : const Color(
                                    0xFF0284C7,
                                  ).withValues(alpha: 0.25),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF0284C7),
                                    Color(0xFF38BDF8),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF0284C7,
                                    ).withValues(alpha: 0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.photo_library_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Choose from Gallery',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: isDark
                                              ? Colors.white
                                              : AppTheme.navyColor,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF0284C7,
                                          ).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: const Text(
                                          'Albums',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0284C7),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Select existing photos or screenshots from device',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Color(0xFF0284C7),
                              size: 15,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Privacy & Security Trust Badge Footer
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF121212)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.grey.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.verified_user_rounded,
                          size: 18,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Evidence photos are encrypted and reviewed strictly by accredited public health officers.',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _isSubmitting = false;

  void _onNextPressed() {
    if (_isSubmitting) return;
    if (!_canProceedCurrentStep()) {
      HygieneFeedback.showWarning(context, _getValidationHint());
      return;
    }
    if (_currentStep < 3) {
      setState(() => _currentStep++);
    } else {
      _submitReport();
    }
  }

  void _onBackPressed() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _submitReport() async {
    if (_isSubmitting) return;
    if (!_hasRequiredReportInputs) {
      HygieneFeedback.showWarning(context, 'Complete the outlet, issues, description and photo evidence before submitting.');
      return;
    }
    final effectiveOutlet = _isOtherSelected
        ? _customNameController.text.trim()
        : (_selectedRestaurant?.name ?? 'Selected Premises');

    final effectiveAddress = _isOtherSelected
        ? _customAddressController.text.trim()
        : (_selectedRestaurant?.address ?? 'Location not provided');

    setState(() => _isSubmitting = true);

    final List<String> allPhotos = [
      ..._attachedPhotoFiles.map((f) => f.path),
      ..._attachedPhotoUrls,
    ];

    final evidenceContext = <String, dynamic>{'outlet_registered': !_isOtherSelected};
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
        evidenceContext.addAll({'reporter_latitude': position.latitude, 'reporter_longitude': position.longitude,
          'accuracy_meters': position.accuracy, 'location_captured_at': position.timestamp.toUtc().toIso8601String(), 'is_mocked': position.isMocked});
      }
    } catch (e) { debugPrint('Reporter GPS unavailable; report will require verification: $e'); }
    ComplaintModel? createdComplaint;
    try {
      createdComplaint = await ComplaintStoreService.submitComplaint(
        restaurantId: _isOtherSelected
            ? 'custom_${DateTime.now().millisecondsSinceEpoch}'
            : (_selectedRestaurant?.id ?? 'rest_001'),
        restaurantName: effectiveOutlet,
        restaurantAddress: effectiveAddress,
        category: _selectedCategory,
        issues: _selectedIssues,
        description: _description.trim(),
        photoUrls: allPhotos,
        evidenceContext: evidenceContext,
        latitude: _isOtherSelected
            ? _selectedLat
            : (_selectedRestaurant?.latitude ?? _selectedLat),
        longitude: _isOtherSelected
            ? _selectedLong
            : (_selectedRestaurant?.longitude ?? _selectedLong),
      );
    } catch (err) {
      if (mounted) {
        HygieneFeedback.showError(
          context,
          'Failed to submit report. Please check connection and try again.',
        );
      }
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (createdComplaint == null) return;

    final displayTicketId =
        createdComplaint.id.length >= 8
        ? '#CMP-${createdComplaint.id.substring(0, 8).toUpperCase()}'
        : '#CMP-2026-8842';

    final currentUser = CustomerStoreService.currentCustomer;
    NotificationService.sendNotification(
      userId: currentUser?.id ?? 'usr_current',
      userEmail: currentUser?.email,
      title: '📋 Complaint Submitted: $displayTicketId',
      message:
          'Your report for "$effectiveOutlet" has been received and queued for review.',
      type: NotificationType.complaint,
      actionUrl: createdComplaint.id,
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Dialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          elevation: 16,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. TOP HERO GRADIENT HEADER WITH CONCENTRIC GLOWING CHECKMARK
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF0F766E),
                          Color(0xFF059669),
                          Color(0xFF10B981),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      children: [
                        // Layered Concentric Rings
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Color(0xFF059669),
                              size: 34,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Report Lodged Successfully!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.shield_rounded,
                                size: 12,
                                color: Color(0xFFA7F3D0),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Official MOH & Municipal Health Dispatch',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFA7F3D0),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 2. BODY CONTENT
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Target Premise & Category Card
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF161616)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white10
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF0F766E,
                                  ).withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.storefront_rounded,
                                  color: Color(0xFF0F766E),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      effectiveOutlet,
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF0F172A),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$_selectedCategory • ${_selectedIssues.length} issues reported',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: isDark
                                            ? Colors.white60
                                            : const Color(0xFF64748B),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Ticket ID & Status Highlight Box
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF161616)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white10
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Tracking Reference ID',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? Colors.white60
                                              : Colors.grey.shade600,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        displayTicketId,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: isDark
                                              ? const Color(0xFF5EEAD4)
                                              : const Color(0xFF0F766E),
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                  InkWell(
                                    onTap: () {
                                      Clipboard.setData(
                                        ClipboardData(text: displayTicketId),
                                      );
                                      HygieneFeedback.showSuccess(
                                        context,
                                        'Copied $displayTicketId to clipboard!',
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white10
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isDark
                                              ? Colors.white12
                                              : const Color(0xFFCBD5E1),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.copy_rounded,
                                            size: 13,
                                            color: isDark
                                                ? Colors.white70
                                                : const Color(0xFF475569),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Copy',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: isDark
                                                  ? Colors.white70
                                                  : const Color(0xFF475569),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 20, thickness: 0.8),
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFF59E0B),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'Current Status: Pending Inspection Review',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFD97706),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Mini 3-Step Milestone Indicator
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF0F766E,
                            ).withValues(alpha: isDark ? 0.15 : 0.05),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(
                                0xFF0F766E,
                              ).withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _milestoneStep(
                                Icons.check_circle_rounded,
                                'Submitted',
                                const Color(0xFF10B981),
                                isDark,
                              ),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 13,
                                color: Colors.grey.shade400,
                              ),
                              _milestoneStep(
                                Icons.pending_actions_rounded,
                                'Audit Review',
                                const Color(0xFFF59E0B),
                                isDark,
                              ),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 13,
                                color: Colors.grey.shade400,
                              ),
                              _milestoneStep(
                                Icons.local_shipping_outlined,
                                'Dispatch',
                                Colors.grey,
                                isDark,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Action Buttons
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F766E),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 2,
                            ),
                            icon: const Icon(
                              Icons.receipt_long_rounded,
                              size: 18,
                            ),
                            label: const Text(
                              'Track in Complaint History',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              Navigator.pop(context);
                              Navigator.pushNamed(
                                context,
                                AppRoutes.complaintHistory,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark
                                  ? Colors.white70
                                  : const Color(0xFF475569),
                              side: BorderSide(
                                color: isDark
                                    ? Colors.white12
                                    : const Color(0xFFCBD5E1),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              Navigator.pop(context);
                            },
                            child: const Text(
                              'Back to Home',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _milestoneStep(IconData icon, String label, Color color, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color == Colors.grey
                ? (isDark ? Colors.white38 : Colors.grey.shade500)
                : (isDark ? Colors.white : const Color(0xFF0F172A)),
          ),
        ),
      ],
    );
  }

  // Google Map Interactive Location Picker Modal
  void _openGoogleMapPickerModal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    LatLng tempPickedLocation = LatLng(_selectedLat, _selectedLong);
    RestaurantModel? tempSelectedRestaurant = _selectedRestaurant;
    bool isCustomPin = _isOtherSelected;
    GoogleMapController? mapCtrl;
    final searchCtrl = TextEditingController();
    List<PlaceSuggestion> modalSuggestions = [];
    bool isSearchingModal = false;
    bool isMapDragging = false;
    String currentReverseAddress = PlacesLocationService.reverseGeocode(
      tempPickedLocation.latitude,
      tempPickedLocation.longitude,
    );
    Timer? modalDebounce;
    PlaceSearchRequest? modalRequest;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final allRestaurants =
                RestaurantStoreService.restaurantsNotifier.value;

            // Generate map markers for existing restaurants
            final Set<Marker> markers = {};

            for (final r in allRestaurants) {
              final isTarget =
                  tempSelectedRestaurant?.id == r.id && !isCustomPin;
              markers.add(
                Marker(
                  markerId: MarkerId('rest_${r.id}'),
                  position: LatLng(r.latitude, r.longitude),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    isTarget
                        ? BitmapDescriptor.hueAzure
                        : BitmapDescriptor.hueRed,
                  ),
                  infoWindow: InfoWindow(
                    title: r.name,
                    snippet: '${r.category} • Tap to select',
                  ),
                  onTap: () {
                    setModalState(() {
                      tempSelectedRestaurant = r;
                      tempPickedLocation = LatLng(r.latitude, r.longitude);
                      isCustomPin = false;
                      currentReverseAddress = r.address;
                    });
                    mapCtrl?.animateCamera(
                      CameraUpdate.newLatLng(LatLng(r.latitude, r.longitude)),
                    );
                  },
                ),
              );
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.90,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  // Modal Header Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      children: [
                        Center(
                          child: Container(
                            width: 44,
                            height: 4.5,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white24
                                  : Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.map_rounded,
                                    color: AppTheme.primaryColor,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Google Map Location Finder',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Colors.white
                                            : AppTheme.navyColor,
                                      ),
                                    ),
                                    Text(
                                      'Search, drag map or tap any location',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey.shade700,
                              ),
                              onPressed: () {
                                modalDebounce?.cancel();
                              modalRequest?.cancel();
                                Navigator.pop(ctx);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Real-Time Google Maps Style Search Bar inside Modal
                        Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF282828)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white12
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: AppSearchField(
                            controller: searchCtrl,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 13,
                            ),
                            onChanged: (val) {
                              final request = PlaceSearchRequest();
                              modalDebounce?.cancel();
                              modalRequest?.cancel();
                              modalRequest = request;
                              if (val.trim().isEmpty) {
                                setModalState(() {
                                  modalSuggestions = [];
                                  isSearchingModal = false;
                                });
                                return;
                              }
                              setModalState(() => isSearchingModal = true);
                              modalDebounce = Timer(
                                const Duration(milliseconds: 250),
                                () async {
                                  final res =
                                      await PlacesLocationService.searchPlaces(
                                        val,
                                        userLat: tempPickedLocation.latitude,
                                        userLng: tempPickedLocation.longitude,
                                  cancellation: request,
                                      );
                                  if (request.isCancelled) return;
                                  setModalState(() {
                                    modalSuggestions = res;
                                    isSearchingModal = false;
                                  });
                                },
                              );
                            },
                            decoration: InputDecoration(
                              hintText:
                                  'Search city, street or landmark (e.g. Melaka, Jonker, KLCC)...',
                              hintStyle: TextStyle(
                                fontSize: 12.5,
                                color: isDark
                                    ? Colors.white38
                                    : Colors.grey.shade500,
                              ),
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                color: AppTheme.primaryColor,
                                size: 20,
                              ),
                              suffixIcon: isSearchingModal
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppTheme.primaryColor,
                                        ),
                                      ),
                                    )
                                  : searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.clear,
                                        size: 18,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.grey,
                                      ),
                                      onPressed: () {
                                        modalRequest?.cancel();
                                            modalDebounce?.cancel();
                                            searchCtrl.clear();
                                        setModalState(() {
                                          modalSuggestions = [];
                                          isSearchingModal = false;
                                        });
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Area Shortcut Quick Chips
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _buildAreaPill(
                          '📍 Melaka',
                          2.1953,
                          102.2482,
                          mapCtrl,
                          setModalState,
                          (lat, lng) {
                            tempPickedLocation = LatLng(lat, lng);
                            isCustomPin = true;
                            currentReverseAddress =
                                PlacesLocationService.reverseGeocode(lat, lng);
                          },
                          isDark,
                        ),
                        _buildAreaPill(
                          '📍 Jonker Walk',
                          2.1953,
                          102.2482,
                          mapCtrl,
                          setModalState,
                          (lat, lng) {
                            tempPickedLocation = LatLng(lat, lng);
                            isCustomPin = true;
                            currentReverseAddress =
                                PlacesLocationService.reverseGeocode(lat, lng);
                          },
                          isDark,
                        ),
                        _buildAreaPill(
                          '📍 Bukit Bintang',
                          3.1488,
                          101.7133,
                          mapCtrl,
                          setModalState,
                          (lat, lng) {
                            tempPickedLocation = LatLng(lat, lng);
                            isCustomPin = true;
                            currentReverseAddress =
                                PlacesLocationService.reverseGeocode(lat, lng);
                          },
                          isDark,
                        ),
                        _buildAreaPill(
                          '📍 KLCC',
                          3.1579,
                          101.7123,
                          mapCtrl,
                          setModalState,
                          (lat, lng) {
                            tempPickedLocation = LatLng(lat, lng);
                            isCustomPin = true;
                            currentReverseAddress =
                                PlacesLocationService.reverseGeocode(lat, lng);
                          },
                          isDark,
                        ),
                        _buildAreaPill(
                          '📍 Bangsar',
                          3.1315,
                          101.6705,
                          mapCtrl,
                          setModalState,
                          (lat, lng) {
                            tempPickedLocation = LatLng(lat, lng);
                            isCustomPin = true;
                            currentReverseAddress =
                                PlacesLocationService.reverseGeocode(lat, lng);
                          },
                          isDark,
                        ),
                        _buildAreaPill(
                          '📍 Petaling Jaya SS2',
                          3.1189,
                          101.6214,
                          mapCtrl,
                          setModalState,
                          (lat, lng) {
                            tempPickedLocation = LatLng(lat, lng);
                            isCustomPin = true;
                            currentReverseAddress =
                                PlacesLocationService.reverseGeocode(lat, lng);
                          },
                          isDark,
                        ),
                        _buildAreaPill(
                          '📍 Penang Gurney',
                          5.4375,
                          100.3098,
                          mapCtrl,
                          setModalState,
                          (lat, lng) {
                            tempPickedLocation = LatLng(lat, lng);
                            isCustomPin = true;
                            currentReverseAddress =
                                PlacesLocationService.reverseGeocode(lat, lng);
                          },
                          isDark,
                        ),
                        _buildAreaPill(
                          '📍 Johor Bahru',
                          1.4623,
                          103.7638,
                          mapCtrl,
                          setModalState,
                          (lat, lng) {
                            tempPickedLocation = LatLng(lat, lng);
                            isCustomPin = true;
                            currentReverseAddress =
                                PlacesLocationService.reverseGeocode(lat, lng);
                          },
                          isDark,
                        ),
                        _buildAreaPill(
                          '📍 Ipoh Old Town',
                          4.5968,
                          101.0778,
                          mapCtrl,
                          setModalState,
                          (lat, lng) {
                            tempPickedLocation = LatLng(lat, lng);
                            isCustomPin = true;
                            currentReverseAddress =
                                PlacesLocationService.reverseGeocode(lat, lng);
                          },
                          isDark,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Live Interactive Google Map
                  Expanded(
                    child: Stack(
                      children: [
                        GoogleMap(
                          style: AppMapTheme.getMapStyle(isDark),
                          initialCameraPosition: CameraPosition(
                            target: tempPickedLocation,
                            zoom: 15.5,
                            tilt: 35.0,
                          ),
                          onMapCreated: (controller) {
                            mapCtrl = controller;
                            AppMapTheme.applyTheme(controller, isDark);
                          },
                          markers: markers,
                          gestureRecognizers:
                              <Factory<OneSequenceGestureRecognizer>>{
                                Factory<OneSequenceGestureRecognizer>(
                                  () => EagerGestureRecognizer(),
                                ),
                              },
                          scrollGesturesEnabled: true,
                          zoomGesturesEnabled: true,
                          tiltGesturesEnabled: true,
                          rotateGesturesEnabled: true,
                          onCameraMove: (position) {
                            tempPickedLocation = position.target;
                            if (!isMapDragging) {
                              setModalState(() {
                                isMapDragging = true;
                                isCustomPin = true;
                                tempSelectedRestaurant = _otherRestaurantOption;
                              });
                            }
                          },
                          onCameraIdle: () {
                            final addr = PlacesLocationService.reverseGeocode(
                              tempPickedLocation.latitude,
                              tempPickedLocation.longitude,
                            );
                            setModalState(() {
                              isMapDragging = false;
                              currentReverseAddress = addr;
                            });
                          },
                          onTap: (point) {
                            setModalState(() {
                              tempPickedLocation = point;
                              isCustomPin = true;
                              tempSelectedRestaurant = _otherRestaurantOption;
                              modalSuggestions = [];
                            });
                            mapCtrl?.animateCamera(
                              CameraUpdate.newLatLng(point),
                            );
                          },
                          myLocationEnabled: true,
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                        ),

                        // Center Interactive Drag Pin with Lift & Shadow (Google Maps Style)
                        Center(
                          child: IgnorePointer(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                bottom: 38,
                              ), // Tip points directly to map center
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                curve: Curves.easeOut,
                                transform: Matrix4.translationValues(
                                  0,
                                  isMapDragging ? -16 : 0,
                                  0,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Live Status Tooltip Pill
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isMapDragging
                                            ? const Color(0xFFD97706)
                                            : AppTheme.primaryColor,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.25,
                                            ),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isMapDragging
                                                ? Icons.open_with_rounded
                                                : Icons.place_rounded,
                                            color: Colors.white,
                                            size: 13,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isMapDragging
                                                ? 'Release to pin destination'
                                                : 'Drag map to move pin',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    // Pin Icon
                                    Stack(
                                      alignment: Alignment.center,
                                      children: const [
                                        Icon(
                                          Icons.location_on,
                                          size: 48,
                                          color: Color(0xFF10B981),
                                        ),
                                        Positioned(
                                          top: 10,
                                          child: Icon(
                                            Icons.circle,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                    // Ground Shadow that shrinks when lifted
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      width: isMapDragging ? 8 : 16,
                                      height: isMapDragging ? 3 : 5,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: isMapDragging ? 0.18 : 0.35,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Suggestions Dropdown Overlay inside Map
                        if (modalSuggestions.isNotEmpty)
                          Positioned(
                            top: 8,
                            left: 12,
                            right: 12,
                            child: Container(
                              constraints: const BoxConstraints(maxHeight: 250),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1E1E1E)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ListView.separated(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                itemCount: modalSuggestions.length,
                                separatorBuilder: (ctx, i) => Divider(
                                  height: 1,
                                  color: isDark
                                      ? Colors.white12
                                      : Colors.grey.shade200,
                                ),
                                itemBuilder: (itemCtx, i) {
                                  final item = modalSuggestions[i];
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(
                                      Icons.place_rounded,
                                      color: AppTheme.primaryColor,
                                      size: 20,
                                    ),
                                    title: Text(
                                      item.title,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: isDark
                                            ? Colors.white
                                            : AppTheme.navyColor,
                                      ),
                                    ),
                                    subtitle: Text(
                                      item.address,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.grey.shade600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: item.distanceKm != null
                                        ? Text(
                                            '${item.distanceKm!.toStringAsFixed(1)} km',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.primaryColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          )
                                        : null,
                                    onTap: () {
                                      final newPos = LatLng(
                                        item.latitude,
                                        item.longitude,
                                      );
                                      setModalState(() {
                                        tempPickedLocation = newPos;
                                        isCustomPin = true;
                                        tempSelectedRestaurant =
                                            _otherRestaurantOption;
                                        modalSuggestions = [];
                                        modalRequest?.cancel();
                                        modalDebounce?.cancel();
                                        isSearchingModal = false;
                                        searchCtrl.text = item.title;
                                        currentReverseAddress =
                                            PlacesLocationService.reverseGeocode(
                                              newPos.latitude,
                                              newPos.longitude,
                                            );
                                      });
                                      mapCtrl?.animateCamera(
                                        CameraUpdate.newLatLngZoom(
                                          newPos,
                                          16.5,
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),

                        // Recenter GPS Button
                        Positioned(
                          bottom: 16,
                          right: 14,
                          child: FloatingActionButton.small(
                            backgroundColor: isDark
                                ? const Color(0xFF282828)
                                : Colors.white,
                            foregroundColor: AppTheme.primaryColor,
                            elevation: 4,
                            onPressed: () {
                              final defaultPos = LatLng(3.1466, 101.6958);
                              setModalState(() {
                                tempPickedLocation = defaultPos;
                                currentReverseAddress =
                                    PlacesLocationService.reverseGeocode(
                                      defaultPos.latitude,
                                      defaultPos.longitude,
                                    );
                              });
                              mapCtrl?.animateCamera(
                                CameraUpdate.newLatLngZoom(defaultPos, 16.0),
                              );
                            },
                            child: const Icon(Icons.my_location),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bottom Confirmation Action Bar
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF282828)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.place_rounded,
                                      color: AppTheme.primaryColor,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        isCustomPin
                                            ? currentReverseAddress
                                            : (tempSelectedRestaurant
                                                      ?.address ??
                                                  currentReverseAddress),
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.grey.shade800,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.black26
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isDark
                                              ? Colors.white12
                                              : Colors.grey.shade300,
                                        ),
                                      ),
                                      child: Text(
                                        'GPS: ${tempPickedLocation.latitude.toStringAsFixed(4)}, ${tempPickedLocation.longitude.toStringAsFixed(4)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontFamily: 'monospace',
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.grey.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      isMapDragging
                                          ? '📍 Moving map...'
                                          : '✓ Drag map to fine-tune',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                        color: isMapDragging
                                            ? Colors.amber
                                            : AppTheme.primaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 2,
                              ),
                              onPressed: () {
                                setState(() {
                                  _selectedLat = tempPickedLocation.latitude;
                                  _selectedLong = tempPickedLocation.longitude;
                                  if (isCustomPin) {
                                    _selectedRestaurant =
                                        _otherRestaurantOption;
                                    _customAddressRequest?.cancel();
                                      _customAddressDebounce?.cancel();
                                      _isSearchingCustomAddress = false;
                                      _customAddressController.text =
                                        currentReverseAddress;
                                    if (_customNameController.text
                                        .trim()
                                        .isEmpty) {
                                      _customNameController.text = '';
                                    }
                                  } else if (tempSelectedRestaurant != null) {
                                    _selectedRestaurant =
                                        tempSelectedRestaurant;
                                  }
                                });
                                modalDebounce?.cancel();
                              modalRequest?.cancel();
                                Navigator.pop(ctx);
                                HygieneFeedback.showSuccess(
                                  context,
                                  isCustomPin
                                      ? 'Custom destination selected & address auto-filled!'
                                      : 'Selected: ${_selectedRestaurant?.name}',
                                );
                              },
                              icon: const Icon(
                                Icons.check_circle_outline,
                                color: Colors.white,
                                size: 20,
                              ),
                              label: Text(
                                isCustomPin
                                    ? 'Confirm Custom Location on Map'
                                    : 'Select This Restaurant',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      modalRequest?.cancel(); modalDebounce?.cancel(); searchCtrl.dispose();
    });
  }

  Widget _buildAreaPill(
    String label,
    double lat,
    double lng,
    GoogleMapController? mapCtrl,
    StateSetter setModalState,
    void Function(double lat, double lng) onSelect,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        backgroundColor: isDark
            ? const Color(0xFF282828)
            : const Color(0xFFF1F5F9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isDark ? Colors.white12 : Colors.grey.shade300,
          ),
        ),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : AppTheme.navyColor,
          ),
        ),
        onPressed: () {
          setModalState(() {
            onSelect(lat, lng);
          });
          mapCtrl?.animateCamera(
            CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16.0),
          );
        },
      ),
    );
  }

  // Active Step Form Controls
  Widget _buildActiveStepContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (_currentStep) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Restaurant / Food Stall Premises:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isDark ? Colors.white : AppTheme.navyColor,
              ),
            ),
            const SizedBox(height: 12),

            // High-Quality Custom Styled Dropdown Container
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: AppSelectField<RestaurantModel>(
                key: ValueKey(_selectedRestaurant?.id ?? 'no_selection'),
                isExpanded: true,
                initialValue: _selectedRestaurant,
                borderRadius: BorderRadius.circular(16),
                dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppTheme.primaryColor,
                  size: 26,
                ),
                hint: Text(
                  'Please select a restaurant / food stall',
                  style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                  ),
                ),
                decoration: InputDecoration(
                  labelText: 'Choose Restaurant / Food Stall',
                  labelStyle: TextStyle(
                    color: isDark ? Colors.white70 : Colors.grey.shade700,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.storefront,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                    ),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                items: [
                  ..._availableRestaurants.map((r) {
                    return DropdownMenuItem<RestaurantModel>(
                      value: r,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isDark
                                    ? Colors.white
                                    : AppTheme.navyColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF282828)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              r.category,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  DropdownMenuItem<RestaurantModel>(
                    value: _otherRestaurantOption,
                    child: Row(
                      children: const [
                        Icon(
                          Icons.add_circle_outline,
                          color: AppTheme.primaryColor,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Other (Add New Premises)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedRestaurant = val;
                    if (val != null && val.id != 'other_new') {
                      _selectedLat = val.latitude;
                      _selectedLong = val.longitude;
                    }
                  });
                },
              ),
            ),

            // Dynamic Custom Fields Container if "Other" is chosen
            if (_isOtherSelected) ...[
              const SizedBox(height: 16),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E1E1E)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(
                      alpha: isDark ? 0.6 : 0.4,
                    ),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.2 : 0.05,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.add_business_rounded,
                              color: AppTheme.primaryColor,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'New Premises Info',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: isDark
                                    ? Colors.white
                                    : AppTheme.navyColor,
                              ),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: _openGoogleMapPickerModal,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.place_rounded,
                                  size: 14,
                                  color: AppTheme.primaryColor,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Pick on Map',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Enter details for the new unlisted food outlet below:',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 1. Restaurant Name Input
                    TextField(
                      controller: _customNameController,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 13.5,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Restaurant / Stall Name *',
                        labelStyle: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey.shade700,
                        ),
                        hintText: 'e.g. Restoran Sin Huat, Stall 12',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white38 : Colors.grey,
                        ),
                        prefixIcon: const Icon(
                          Icons.store,
                          color: AppTheme.primaryColor,
                          size: 20,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark
                                ? Colors.white12
                                : Colors.grey.shade300,
                          ),
                        ),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF121212)
                            : Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 2. Cuisine Category Selector
                    AppSelectField<String>(
                      initialValue: _customCategory,
                      dropdownColor: isDark
                          ? const Color(0xFF1E1E1E)
                          : Colors.white,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Cuisine / Premises Category',
                        labelStyle: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey.shade700,
                        ),
                        prefixIcon: const Icon(
                          Icons.restaurant_menu,
                          color: AppTheme.primaryColor,
                          size: 20,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark
                                ? Colors.white12
                                : Colors.grey.shade300,
                          ),
                        ),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF121212)
                            : Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      items:
                          [
                            'Malay Local',
                            'Chinese Noodle',
                            'Indian Mamak',
                            'Dim Sum',
                            'Western Fast Food',
                            'Cafe & Bakery',
                            'Hawker Stall / Food Court',
                            'Other Cuisine',
                          ].map((cat) {
                            return DropdownMenuItem(
                              value: cat,
                              child: Text(
                                cat,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            );
                          }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _customCategory = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // 3. Address / Landmark Input with Google Places Autocomplete Location Finder
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF121212) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white12 : Colors.grey.shade300,
                        ),
                      ),
                      child: Column(
                        children: [
                          TextField(
                            controller: _customAddressController,
                            focusNode: _customAddressFocusNode,
                            maxLines: 2,
                            minLines: 1,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 13.5,
                            ),
                            onChanged: (val) {
                              _customAddressRequest?.cancel();
                              final request = _customAddressRequest = PlaceSearchRequest();
                              _customAddressDebounce?.cancel();
                              if (val.trim().isEmpty) {
                                setState(() {
                                  _customAddressSuggestions = [];
                                  _isSearchingCustomAddress = false;
                                });
                                return;
                              }
                              setState(() => _isSearchingCustomAddress = true);
                              _customAddressDebounce = Timer(
                                const Duration(milliseconds: 250),
                                () async {
                                  final res =
                                      await PlacesLocationService.searchPlaces(
                                        val,
                                        userLat: _selectedLat,
                                        userLng: _selectedLong,
                                        cancellation: request,
                                      );
                                  if (mounted && !request.isCancelled) {
                                    setState(() {
                                      _customAddressSuggestions = res;
                                      _isSearchingCustomAddress = false;
                                    });
                                  }
                                },
                              );
                            },
                            decoration: InputDecoration(
                              labelText:
                                  'Premises Address & Landmark Details *',
                              labelStyle: TextStyle(
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey.shade700,
                              ),
                              hintText:
                                  'Search or type street/area (e.g. Jonker, SS2, KLCC)...',
                              hintStyle: TextStyle(
                                fontSize: 12.5,
                                color: isDark ? Colors.white38 : Colors.grey,
                              ),
                              prefixIcon: const Icon(
                                Icons.place,
                                color: AppTheme.primaryColor,
                                size: 20,
                              ),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isSearchingCustomAddress)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppTheme.primaryColor,
                                        ),
                                      ),
                                    )
                                  else if (_customAddressController
                                      .text
                                      .isNotEmpty)
                                    IconButton(
                                      icon: Icon(
                                        Icons.clear,
                                        size: 16,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.grey,
                                      ),
                                      onPressed: () {
                                        _customAddressRequest?.cancel();
                                        _customAddressDebounce?.cancel();
                                        _customAddressController.clear();
                                        setState(() {
                                          _customAddressSuggestions = [];
                                          _isSearchingCustomAddress = false;
                                        });
                                      },
                                    ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.map_rounded,
                                      color: AppTheme.primaryColor,
                                      size: 20,
                                    ),
                                    tooltip: 'Pick on Map',
                                    onPressed: _openGoogleMapPickerModal,
                                  ),
                                ],
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                          ),

                          // Live Autocomplete Suggestions dropdown for manual address input
                          if (_customAddressSuggestions.isNotEmpty) ...[
                            Divider(
                              height: 1,
                              color: isDark
                                  ? Colors.white12
                                  : Colors.grey.shade200,
                            ),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 220),
                              child: ListView.separated(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                itemCount: _customAddressSuggestions.length,
                                separatorBuilder: (ctx, i) => Divider(
                                  height: 1,
                                  color: isDark
                                      ? Colors.white12
                                      : Colors.grey.shade100,
                                ),
                                itemBuilder: (ctx, idx) {
                                  final item = _customAddressSuggestions[idx];
                                  return ListTile(
                                    dense: true,
                                    leading: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor.withValues(
                                          alpha: 0.1,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        item.icon,
                                        color: AppTheme.primaryColor,
                                        size: 16,
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.title,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12.5,
                                              color: isDark
                                                  ? Colors.white
                                                  : AppTheme.navyColor,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? const Color(0xFF282828)
                                                : Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            item.category,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? Colors.white70
                                                  : Colors.grey.shade700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      item.address,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.grey.shade600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: item.distanceKm != null
                                        ? Text(
                                            '${item.distanceKm!.toStringAsFixed(1)} km',
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              color: AppTheme.primaryColor,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          )
                                        : null,
                                    onTap: () {
                                      _customAddressRequest?.cancel();
                                      _customAddressDebounce?.cancel();
                                      _isSearchingCustomAddress = false;
                                      _customAddressController.text =
                                          item.address;
                                      setState(() {
                                        _selectedLat = item.latitude;
                                        _selectedLong = item.longitude;
                                        _customAddressSuggestions = [];
                                      });
                                      _customAddressFocusNode.unfocus();
                                      HygieneFeedback.showSuccess(
                                        context,
                                        'Location selected: ${item.title}',
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Restaurant Location Card: Dynamic based on existing vs other unlisted premises
            if (_isOtherSelected) ...[
              if (_customAddressController.text.trim().isNotEmpty)
                // Tagged GPS Card when location has been chosen for unlisted premises
                InkWell(
                  onTap: _openGoogleMapPickerModal,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0C4A6E).withValues(alpha: 0.3)
                          : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF0284C7).withValues(alpha: 0.3)
                            : Colors.blue.shade100,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.gps_fixed,
                          size: 20,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Restaurant Location',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? const Color(0xFF7DD3FC)
                                          : AppTheme.navyColor,
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Change on Map',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isDark
                                              ? const Color(0xFF38BDF8)
                                              : AppTheme.primaryColor,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 10,
                                        color: isDark
                                            ? const Color(0xFF38BDF8)
                                            : AppTheme.primaryColor,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_selectedLat.toStringAsFixed(4)}, ${_selectedLong.toStringAsFixed(4)} (${_customAddressController.text.trim()})',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.grey.shade700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                // Empty state when location has not been selected yet for unlisted premises
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E1E1E)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_off_outlined,
                        size: 18,
                        color: isDark ? Colors.white38 : Colors.grey.shade400,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Restaurant Location',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.white60
                                    : Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'No location selected yet. Search address above or tap "Pick on Map".',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.white38
                                    : Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ] else if (_selectedRestaurant != null)
              // Read-only Verified GPS Card for existing registered restaurants
              InkWell(
                onTap: () {
                  HygieneFeedback.showWarning(
                    context,
                    'This registered restaurant\'s location is verified and cannot be changed. Select "Other (Add New Premises)" to tag a custom location.',
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkSecondarySurface
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? AppTheme.darkBorderColor
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.verified_rounded,
                          size: 18,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Restaurant Location',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.white
                                        : AppTheme.navyColor,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF282828)
                                        : Colors.grey.shade200,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.lock_outline_rounded,
                                    size: 13,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_selectedLat.toStringAsFixed(4)}, ${_selectedLong.toStringAsFixed(4)} (${_selectedRestaurant?.address ?? _reverseGeocodeLocation(_selectedLat, _selectedLong)})',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.white60
                                    : Colors.grey.shade700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              // Placeholder state when no restaurant is selected yet
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.darkSecondarySurface
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? AppTheme.darkBorderColor
                        : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF282828)
                            : Colors.grey.shade200,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.storefront_outlined,
                        size: 20,
                        color: isDark ? Colors.white38 : Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Restaurant Location',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.white70
                                  : AppTheme.navyColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Please select a restaurant or food stall above to view premises location.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );

      case 1:
        final currentChecklist = _issueChecklistMap[_selectedCategory] ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Main Issue Category:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14.5,
                color: isDark ? Colors.white : AppTheme.navyColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose the primary violation type for official KKM inspection priority.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 12),

            // 2-Column Rich Aesthetic Visual Category Grid Cards
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.55,
              ),
              itemCount: _categories.length,
              itemBuilder: (context, idx) {
                final cat = _categories[idx];
                final isSelected = (_selectedCategory == cat);
                final icon =
                    _categoryIcons[cat] ?? Icons.report_problem_rounded;
                final color = _categoryColors[cat] ?? AppTheme.primaryColor;
                final subtitle = _categorySubtitles[cat] ?? '';

                return InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedCategory = cat;
                      _selectedIssues.clear();
                    });
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withValues(alpha: isDark ? 0.22 : 0.08)
                          : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? color
                            : (isDark
                                  ? Colors.white12
                                  : const Color(0xFFE2E8F0)),
                        width: isSelected ? 2.0 : 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isSelected
                              ? color.withValues(alpha: 0.15)
                              : Colors.black.withValues(
                                  alpha: isDark ? 0.15 : 0.02,
                                ),
                          blurRadius: isSelected ? 8 : 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? color.withValues(alpha: 0.22)
                                    : (isDark
                                          ? Colors.white10
                                          : color.withValues(alpha: 0.1)),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                icon,
                                size: 18,
                                color: isSelected
                                    ? color
                                    : (isDark ? Colors.white70 : color),
                              ),
                            ),
                            if (isSelected)
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  size: 10,
                                  color: Colors.white,
                                ),
                              ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cat,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? (isDark ? Colors.white : color)
                                    : (isDark
                                          ? Colors.white
                                          : AppTheme.navyColor),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark
                                    ? Colors.white54
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Observed Hygiene Issues:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white : AppTheme.navyColor,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _selectedIssues.isNotEmpty
                        ? AppTheme.primaryColor.withValues(alpha: 0.12)
                        : (isDark ? Colors.white10 : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_selectedIssues.length} selected',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: _selectedIssues.isNotEmpty
                          ? AppTheme.primaryColor
                          : (isDark ? Colors.white60 : Colors.grey.shade600),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Check specific violations for $_selectedCategory:',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 12),

            // Checklist Items Card List
            ...currentChecklist.map((issue) {
              final isChecked = _selectedIssues.contains(issue);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isChecked
                      ? (isDark
                            ? AppTheme.primaryColor.withValues(alpha: 0.15)
                            : AppTheme.primaryColor.withValues(alpha: 0.06))
                      : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isChecked
                        ? AppTheme.primaryColor
                        : (isDark ? Colors.white12 : Colors.grey.shade200),
                    width: isChecked ? 1.4 : 1,
                  ),
                ),
                child: CheckboxListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 0,
                  ),
                  activeColor: AppTheme.primaryColor,
                  dense: true,
                  title: Text(
                    issue,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isChecked
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isChecked
                          ? (isDark ? Colors.white : AppTheme.navyColor)
                          : (isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                  value: isChecked,
                  onChanged: (val) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (val == true) {
                        _selectedIssues.add(issue);
                      } else {
                        _selectedIssues.remove(issue);
                      }
                    });
                  },
                ),
              );
            }),
          ],
        );

      case 2:
        final suggestedTags =
            _categoryTagsMap[_selectedCategory] ??
            [
              '#Cockroach',
              '#DirtyUtensils',
              '#FoulOdor',
              '#UncoveredFood',
              '#GreasyFloor',
            ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Description & Location Notes *',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isDark ? Colors.white : AppTheme.navyColor,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _descriptionController,
                maxLines: 3,
                minLines: 2,
                style: TextStyle(
                  fontSize: 13.5,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  hintText:
                      'Describe observations (e.g. time of visit, table area, kitchen counter cleanliness, staff response)...',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white38 : Colors.grey,
                    fontSize: 12.5,
                  ),
                  contentPadding: const EdgeInsets.all(14),
                  border: InputBorder.none,
                ),
                onChanged: (val) => setState(() => _description = val),
              ),
            ),
            const SizedBox(height: 12),

            // Dynamic Context-Aware Quick Tag Chips matching Selected Category
            Row(
              children: [
                Icon(
                  Icons.tag_rounded,
                  size: 14,
                  color: isDark
                      ? const Color(0xFF5EEAD4)
                      : const Color(0xFF0F766E),
                ),
                const SizedBox(width: 4),
                Text(
                  'Suggested Tags for $_selectedCategory:',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? const Color(0xFF5EEAD4)
                        : const Color(0xFF0F766E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: suggestedTags.map((tag) => _quickTagChip(tag)).toList(),
            ),
            const SizedBox(height: 24),

            // Photo Evidence Section Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Upload Photo Evidence *',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white : AppTheme.navyColor,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _hasPhotoAttached
                        ? AppTheme.primaryColor.withValues(alpha: 0.12)
                        : (isDark
                              ? const Color(0xFF282828)
                              : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$_totalPhotoCount / 4 Attached',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: _hasPhotoAttached
                          ? AppTheme.primaryColor
                          : (isDark ? Colors.white70 : Colors.grey.shade700),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Attach photos of food, utensils, or premises for inspection validation.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 12),

            // Photo Grid / Upload Trigger
            _buildPhotoEvidenceGrid(),
          ],
        );

      case 3:
        final effectiveOutletName = _isOtherSelected
            ? '${_customNameController.text.trim()} (New Unlisted Outlet)'
            : (_selectedRestaurant?.name ?? 'None');

        final effectiveAddress = _isOtherSelected
            ? _customAddressController.text.trim()
            : (_selectedRestaurant?.address ?? 'None');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Review Report Before Submission:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isDark ? Colors.white : AppTheme.navyColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Please confirm that all details are accurate before lodging formal complaint.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildReviewRow('Target Outlet:', effectiveOutletName),
                  _buildReviewRow('Address:', effectiveAddress),
                  if (_isOtherSelected)
                    _buildReviewRow('Category:', _customCategory),
                  _buildReviewRow('Main Category:', _selectedCategory),
                  _buildReviewRow(
                    'Violations Checked:',
                    '${_selectedIssues.length} items selected',
                  ),
                  if (_selectedIssues.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 120, bottom: 10),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: _selectedIssues.map((issue) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(
                                      0xFF7F1D1D,
                                    ).withValues(alpha: 0.35)
                                  : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isDark
                                    ? const Color(
                                        0xFFDC2626,
                                      ).withValues(alpha: 0.5)
                                    : const Color(0xFFFECACA),
                              ),
                            ),
                            child: Text(
                              '• $issue',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? const Color(0xFFFCA5A5)
                                    : const Color(0xFFDC2626),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                  _buildReviewRow(
                    'Notes Details:',
                    _description.isEmpty ? 'None provided' : _description,
                  ),
                  _buildReviewRow(
                    'Photo Evidence:',
                    _hasPhotoAttached
                        ? 'Attached ($_totalPhotoCount photos)'
                        : 'No photos attached',
                  ),

                  // Photo Evidence Thumbnails Preview in Review Step
                  if (_hasPhotoAttached) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 70,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          ..._attachedPhotoFiles.map((file) {
                            return Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white24
                                      : Colors.grey.shade300,
                                ),
                                image: DecorationImage(
                                  image: FileImage(file),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            );
                          }),
                          ..._attachedPhotoUrls.map((url) {
                            return Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white24
                                      : Colors.grey.shade300,
                                ),
                                image: DecorationImage(
                                  image: NetworkImage(url),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Official Guarantee Notice Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF064E3B).withValues(alpha: 0.35)
                    : const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF059669).withValues(alpha: 0.5)
                      : const Color(0xFF86EFAC),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    color: Color(0xFF16A34A),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your report will be securely dispatched to authorized municipal health inspectors for investigation.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? const Color(0xFFA7F3D0)
                            : Colors.green.shade900,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _quickTagChip(String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isContained = _description.contains(label);

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          if (!isContained) {
            if (_description.trim().isEmpty) {
              _description = label;
            } else {
              _description = '$_description $label';
            }
          } else {
            _description = _description
                .replaceAll(label, '')
                .replaceAll('  ', ' ')
                .trim();
          }
          _descriptionController.text = _description;
          _descriptionController.selection = TextSelection.fromPosition(
            TextPosition(offset: _descriptionController.text.length),
          );
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isContained
              ? const Color(0xFF0F766E).withValues(alpha: isDark ? 0.35 : 0.15)
              : (isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isContained
                ? const Color(0xFF0F766E)
                : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
            width: isContained ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isContained ? FontWeight.bold : FontWeight.w500,
                color: isContained
                    ? (isDark
                          ? const Color(0xFF5EEAD4)
                          : const Color(0xFF0F766E))
                    : (isDark ? Colors.white70 : const Color(0xFF475569)),
              ),
            ),
            if (isContained) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.check,
                size: 12,
                color: isDark
                    ? const Color(0xFF5EEAD4)
                    : const Color(0xFF0F766E),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoEvidenceGrid() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_hasPhotoAttached) {
      return InkWell(
        onTap: _showPhotoPickerOptionsModal,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(
                alpha: isDark ? 0.5 : 0.35,
              ),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_a_photo_rounded,
                  size: 30,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Tap to Upload Photo Evidence',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14.5,
                  color: isDark ? Colors.white : AppTheme.navyColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Camera • Gallery (Max 4)',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              // 1. Files Picked
              ..._attachedPhotoFiles.asMap().entries.map((entry) {
                final idx = entry.key;
                final file = entry.value;
                return Stack(
                  children: [
                    Container(
                      width: 95,
                      height: 95,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white24 : Colors.grey.shade300,
                        ),
                        image: DecorationImage(
                          image: FileImage(file),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _attachedPhotoFiles.removeAt(idx);
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),

              // 2. Preset URLs Added
              ..._attachedPhotoUrls.asMap().entries.map((entry) {
                final idx = entry.key;
                final url = entry.value;
                return Stack(
                  children: [
                    Container(
                      width: 95,
                      height: 95,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white24 : Colors.grey.shade300,
                        ),
                        image: DecorationImage(
                          image: NetworkImage(url),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _attachedPhotoUrls.removeAt(idx);
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),

              // 3. Add More Tile
              if (_totalPhotoCount < 4)
                InkWell(
                  onTap: _showPhotoPickerOptionsModal,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 95,
                    height: 95,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF121212)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.4),
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          color: AppTheme.primaryColor,
                          size: 26,
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Add More',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '✓ Evidence attached for health officer review',
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark
                      ? const Color(0xFF6EE7B7)
                      : Colors.green.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton(
                onPressed: _showPhotoPickerOptionsModal,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text(
                  'Change',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReviewRow(String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isDark ? Colors.white : AppTheme.navyColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: languageManager,
      builder: (context, _) {
        final canProceed = _canProceedCurrentStep();

        return Scaffold(
          backgroundColor: isDark
              ? const Color(0xFF121212)
              : const Color(0xFFF8FAFC),
          appBar: CustomAppBar(title: t('submit_hygiene_report')),
          body: Column(
            children: [
              // Horizontal Step Process Header Tracker
              HorizontalStepTracker(
                currentStep: _currentStep,
                stepTitles: _stepTitles,
              ),

              // Main Step Form Body
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildActiveStepContent(),
                ),
              ),

              // Validation Warning Message Banner
              if (!canProceed)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: isDark
                      ? const Color(0xFF78350F).withValues(alpha: 0.3)
                      : Colors.amber.shade50,
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: isDark
                            ? Colors.amber.shade300
                            : Colors.amber.shade900,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _getValidationHint(),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.amber.shade200
                                : Colors.amber.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Bottom Step Navigation Control Buttons
              SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    border: Border(
                      top: BorderSide(
                        color: isDark ? Colors.white12 : Colors.grey.shade200,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.2 : 0.05,
                        ),
                        blurRadius: 10,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      if (_currentStep > 0) ...[
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              foregroundColor: isDark
                                  ? Colors.white
                                  : AppTheme.navyColor,
                              side: BorderSide(
                                color: isDark
                                    ? Colors.white24
                                    : Colors.grey.shade300,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _onBackPressed,
                            child: const Text('Back'),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: canProceed && !_isSubmitting
                                ? AppTheme.primaryColor
                                : (isDark
                                      ? const Color(0xFF282828)
                                      : Colors.grey.shade300),
                            foregroundColor: canProceed && !_isSubmitting
                                ? Colors.white
                                : (isDark
                                      ? Colors.white38
                                      : Colors.grey.shade500),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: (canProceed && !_isSubmitting)
                              ? _onNextPressed
                              : null,
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _currentStep == _stepTitles.length - 1
                                      ? 'Submit Report'
                                      : 'Next Step',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

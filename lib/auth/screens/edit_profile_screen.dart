import '../../core/widgets/app_select_field.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/services/customer_store_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/hygiene_feedback.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/user_banner.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late String _selectedGender;
  late String _selectedCountry;
  late String _selectedState;

  late String _avatarUrl;
  late String _bannerUrl;
  bool _isSaving = false;
  bool _isUploadingBanner = false;

  final List<Map<String, String>> _presetBanners = [
    {
      'name': 'Emerald Flow',
      'url': 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=1200&q=80',
    },
    {
      'name': 'Dark Charcoal',
      'url': 'https://images.unsplash.com/photo-1550684848-fac1c5b4e853?w=1200&q=80',
    },
    {
      'name': 'Sunset Horizon',
      'url': 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=1200&q=80',
    },
    {
      'name': 'Cyberpunk Neon',
      'url': 'https://images.unsplash.com/photo-1509198397868-475647b2a1e5?w=1200&q=80',
    },
    {
      'name': 'Cozy Cafe',
      'url': 'https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?w=1200&q=80',
    },
    {
      'name': 'Ocean Wave',
      'url': 'https://images.unsplash.com/photo-1505118380757-91f5f5632de0?w=1200&q=80',
    },
  ];

  final List<String> _genderOptions = ['Male', 'Female', 'Other'];
  final List<String> _countryOptions = ['Malaysia 🇲🇾', 'Singapore 🇸🇬', 'Indonesia 🇮🇩', 'Thailand 🇹🇭', 'United States 🇺🇸', 'Other'];

  final Map<String, List<String>> _countryStatesMap = {
    'Malaysia 🇲🇾': [
      'Kuala Lumpur',
      'Selangor',
      'Penang',
      'Johor',
      'Perak',
      'Melaka',
      'Kedah',
      'Pahang',
      'Negeri Sembilan',
      'Sabah',
      'Sarawak',
      'Kelantan',
      'Terengganu',
      'Perlis',
      'Putrajaya',
      'Labuan',
    ],
    'Singapore 🇸🇬': [
      'Central Region',
      'East Region',
      'North Region',
      'North-East Region',
      'West Region',
      'Downtown / Marina Bay',
      'Singapore (City)',
    ],
    'Indonesia 🇮🇩': [
      'Jakarta',
      'West Java (Bandung)',
      'Central Java (Semarang)',
      'East Java (Surabaya)',
      'Bali (Denpasar)',
      'North Sumatra (Medan)',
      'Banten',
      'Yogyakarta',
      'Riau',
      'South Sulawesi',
    ],
    'Thailand 🇹🇭': [
      'Bangkok',
      'Chiang Mai',
      'Phuket',
      'Chonburi (Pattaya)',
      'Nonthaburi',
      'Surat Thani (Koh Samui)',
      'Krabi',
      'Khon Kaen',
    ],
    'United States 🇺🇸': [
      'California',
      'New York',
      'Texas',
      'Florida',
      'Washington',
      'Illinois',
      'Massachusetts',
      'Nevada',
      'Georgia',
      'Hawaii',
    ],
    'Other': [
      'Other / International',
    ],
  };

  final List<String> _presetAvatars = [
    'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?q=80&w=200',
    'https://images.unsplash.com/photo-1570295999919-56ceb5ecca61?q=80&w=200',
    'https://images.unsplash.com/photo-1580489944761-15a19d654956?q=80&w=200',
    'https://images.unsplash.com/photo-1534528741775-53994a69daeb?q=80&w=200',
    'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?q=80&w=200',
    'https://images.unsplash.com/photo-1494790108377-be9c29b29330?q=80&w=200',
  ];

  @override
  void initState() {
    super.initState();
    final customer = CustomerStoreService.currentCustomer;
    _nameCtrl = TextEditingController(text: customer?.name ?? '');
    _emailCtrl = TextEditingController(text: customer?.email ?? '');
    _phoneCtrl = TextEditingController(text: customer?.phone ?? '');
    _selectedGender = (customer?.gender != null && _genderOptions.contains(customer!.gender)) ? customer.gender! : 'Male';
    _selectedCountry = (customer?.country != null && _countryOptions.contains(customer!.country)) ? customer.country! : 'Malaysia 🇲🇾';

    final availableStates = _countryStatesMap[_selectedCountry] ?? _countryStatesMap['Malaysia 🇲🇾']!;
    final customerState = customer?.state?.trim();
    if (customerState != null && customerState.isNotEmpty && availableStates.contains(customerState)) {
      _selectedState = customerState;
    } else {
      _selectedState = availableStates.first;
    }

    _avatarUrl = customer?.avatarUrl ?? '';
    _bannerUrl = customer?.bannerUrl ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _showAvatarPickerModal() {
    final customUrlCtrl = TextEditingController(text: _avatarUrl);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add_a_photo_rounded, color: AppTheme.primaryColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Change Profile Picture',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Select Curated Avatar:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 70,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        // Default Clean Silhouette Avatar Option
                        GestureDetector(
                          onTap: () {
                            setModalState(() {
                              _avatarUrl = '';
                              customUrlCtrl.text = '';
                            });
                            setState(() {
                              _avatarUrl = '';
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _avatarUrl.isEmpty ? AppTheme.primaryColor : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: const UserAvatar(
                              avatarUrl: '',
                              radius: 28,
                            ),
                          ),
                        ),
                        ..._presetAvatars.map((url) {
                          final isSelected = (_avatarUrl == url);
                          return GestureDetector(
                            onTap: () {
                              setModalState(() {
                                _avatarUrl = url;
                                customUrlCtrl.text = url;
                              });
                              setState(() {
                                _avatarUrl = url;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              margin: const EdgeInsets.only(right: 12),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                              child: UserAvatar(
                                avatarUrl: url,
                                radius: 28,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Or Enter Custom Image URL:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: customUrlCtrl,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'https://example.com/avatar.jpg',
                      prefixIcon: const Icon(Icons.link_rounded, size: 20, color: AppTheme.primaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        if (customUrlCtrl.text.trim().isNotEmpty) {
                          setState(() {
                            _avatarUrl = customUrlCtrl.text.trim();
                          });
                        }
                        Navigator.pop(ctx);
                      },
                      child: const Text('Apply Avatar Selection', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showBannerPickerModal() {
    final customUrlCtrl = TextEditingController(text: _bannerUrl);
    final picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;

            Future<void> pickAndUploadBanner(ImageSource source) async {
              try {
                final XFile? image = await picker.pickImage(
                  source: source,
                  maxWidth: 1920,
                  maxHeight: 1080,
                  imageQuality: 85,
                );
                if (image != null) {
                  setModalState(() => _isUploadingBanner = true);
                  final uploadedUrl = await CustomerStoreService.uploadBannerImage(image);
                  if (ctx.mounted) {
                    setModalState(() {
                      _bannerUrl = uploadedUrl;
                      _isUploadingBanner = false;
                      customUrlCtrl.text = uploadedUrl;
                    });
                    if (Navigator.canPop(ctx)) {
                      Navigator.pop(ctx);
                    }
                  }
                  if (mounted) {
                    setState(() {
                      _bannerUrl = uploadedUrl;
                    });
                  }
                }
              } catch (_) {
                setModalState(() => _isUploadingBanner = false);
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.panorama_rounded, color: AppTheme.primaryColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Change Banner Background',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Camera & Gallery Upload Buttons Row
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isUploadingBanner ? null : () => pickAndUploadBanner(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined, size: 18),
                          label: const Text('Choose Photo'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? const Color(0xFF282828) : const Color(0xFFF1F5F9),
                            foregroundColor: isDark ? Colors.white : const Color(0xFF0C2340),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isUploadingBanner ? null : () => pickAndUploadBanner(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined, size: 18),
                          label: const Text('Take Photo'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? const Color(0xFF282828) : const Color(0xFFF1F5F9),
                            foregroundColor: isDark ? Colors.white : const Color(0xFF0C2340),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  const Text('Select Preset Background:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 64,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        // Default Minimal Aesthetic Gradient
                        GestureDetector(
                          onTap: () {
                            setModalState(() {
                              _bannerUrl = '';
                              customUrlCtrl.text = '';
                            });
                            setState(() => _bannerUrl = '');
                          },
                          child: Container(
                            width: 100,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _bannerUrl.isEmpty ? AppTheme.primaryColor : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: const UserBanner(bannerUrl: '', height: 64),
                            ),
                          ),
                        ),
                        // Preset options
                        ..._presetBanners.map((p) {
                          final isSelected = (_bannerUrl == p['url']);
                          return GestureDetector(
                            onTap: () {
                              setModalState(() {
                                _bannerUrl = p['url']!;
                                customUrlCtrl.text = p['url']!;
                              });
                              setState(() => _bannerUrl = p['url']!);
                            },
                            child: Container(
                              width: 100,
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Stack(
                                  children: [
                                    UserBanner(bannerUrl: p['url'], height: 64),
                                    Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        color: Colors.black54,
                                        child: Text(
                                          p['name']!,
                                          style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text('Or Enter Custom Image URL:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: customUrlCtrl,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'https://example.com/banner.jpg',
                      prefixIcon: const Icon(Icons.link_rounded, size: 20, color: AppTheme.primaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _bannerUrl = val.trim();
                      });
                    },
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Apply Banner Selection', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    InputDecoration buildInputDecoration({
      required String label,
      required IconData icon,
      bool isReadOnly = false,
      Widget? suffixIcon,
    }) {
      return InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontSize: 13.5,
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
        ),
        prefixIcon: Icon(icon, color: AppTheme.primaryColor, size: 22),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: isReadOnly
            ? (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade100)
            : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade50),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppTheme.primaryColor,
            width: 1.8,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      );
    }

    return Scaffold(
      appBar: const CustomAppBar(title: 'Edit Profile Details'),
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Dynamic Interactive Profile Header (Banner & Avatar)
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                // Top Banner Background with Click-to-Change Button
                GestureDetector(
                  onTap: _showBannerPickerModal,
                  child: Container(
                    height: 140,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        children: [
                          UserBanner(
                            bannerUrl: _bannerUrl,
                            height: 140,
                          ),
                          // "Change Banner" Top-Right Pill
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white30),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.photo_camera_back_outlined, size: 14, color: Colors.white),
                                  SizedBox(width: 5),
                                  Text(
                                    'Change Banner',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Overlapping Avatar Frame
                Positioned(
                  top: 85,
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap: _showAvatarPickerModal,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).cardColor,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: UserAvatar(
                            avatarUrl: _avatarUrl,
                            radius: 46,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: AppTheme.primaryColor,
                            child: IconButton(
                              icon: const Icon(Icons.camera_alt_rounded, size: 13, color: Colors.white),
                              padding: EdgeInsets.zero,
                              onPressed: _showAvatarPickerModal,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 55),

            // Full Name
            TextField(
              controller: _nameCtrl,
              decoration: buildInputDecoration(
                label: 'Full Name',
                icon: Icons.person_outline_rounded,
              ),
            ),
            const SizedBox(height: 16),

            // Email Address (Registered)
            TextField(
              controller: _emailCtrl,
              readOnly: true,
              decoration: buildInputDecoration(
                label: 'Email Address (Registered)',
                icon: Icons.email_outlined,
                isReadOnly: true,
                suffixIcon: const Icon(Icons.lock_outline_rounded, size: 18, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),

            // Phone Number
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: buildInputDecoration(
                label: 'Phone Number',
                icon: Icons.phone_outlined,
              ),
            ),
            const SizedBox(height: 16),

            // Gender Selector
            AppSelectField<String>(
              initialValue: _selectedGender,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.primaryColor, size: 24),
              dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              elevation: 4,
              menuMaxHeight: 260,
              isExpanded: true,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppTheme.navyColor,
              ),
              decoration: buildInputDecoration(
                label: 'Gender',
                icon: Icons.wc_outlined,
              ),
              selectedItemBuilder: (BuildContext context) {
                return _genderOptions.map((g) {
                  IconData gIcon;
                  Color gIconColor;
                  if (g == 'Male') {
                    gIcon = Icons.male_rounded;
                    gIconColor = AppTheme.primaryColor;
                  } else if (g == 'Female') {
                    gIcon = Icons.female_rounded;
                    gIconColor = const Color(0xFFEC4899);
                  } else {
                    gIcon = Icons.transgender_rounded;
                    gIconColor = const Color(0xFF8B5CF6);
                  }
                  return Row(
                    children: [
                      Icon(gIcon, size: 20, color: gIconColor),
                      const SizedBox(width: 10),
                      Text(
                        g,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : AppTheme.navyColor,
                        ),
                      ),
                    ],
                  );
                }).toList();
              },
              items: _genderOptions.map((g) {
                final isSelected = (_selectedGender == g);
                IconData gIcon;
                Color gIconColor;
                if (g == 'Male') {
                  gIcon = Icons.male_rounded;
                  gIconColor = AppTheme.primaryColor;
                } else if (g == 'Female') {
                  gIcon = Icons.female_rounded;
                  gIconColor = const Color(0xFFEC4899);
                } else {
                  gIcon = Icons.transgender_rounded;
                  gIconColor = const Color(0xFF8B5CF6);
                }

                return DropdownMenuItem(
                  value: g,
                  child: Row(
                    children: [
                      Icon(gIcon, size: 20, color: gIconColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          g,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isDark ? Colors.white : AppTheme.navyColor,
                          ),
                        ),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_rounded, size: 18, color: AppTheme.primaryColor),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedGender = val);
              },
            ),
            const SizedBox(height: 16),

            // Country Selector
            AppSelectField<String>(
              initialValue: _selectedCountry,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.primaryColor, size: 24),
              dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              elevation: 4,
              menuMaxHeight: 280,
              isExpanded: true,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppTheme.navyColor,
              ),
              decoration: buildInputDecoration(
                label: 'Country / Region',
                icon: Icons.public_outlined,
              ),
              selectedItemBuilder: (BuildContext context) {
                return _countryOptions.map((c) {
                  return Row(
                    children: [
                      Text(
                        c,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : AppTheme.navyColor,
                        ),
                      ),
                    ],
                  );
                }).toList();
              },
              items: _countryOptions.map((c) {
                final isSelected = (_selectedCountry == c);
                return DropdownMenuItem(
                  value: c,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isDark ? Colors.white : AppTheme.navyColor,
                          ),
                        ),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_rounded, size: 18, color: AppTheme.primaryColor),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedCountry = val;
                    final availableStates = _countryStatesMap[_selectedCountry] ?? ['Other / International'];
                    if (!availableStates.contains(_selectedState)) {
                      _selectedState = availableStates.first;
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 16),

            // State / Region Dropdown Selector
            AppSelectField<String>(
              key: ValueKey('state_dropdown_$_selectedCountry'),
              initialValue: _selectedState,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.primaryColor, size: 24),
              dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              elevation: 4,
              menuMaxHeight: 280,
              isExpanded: true,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppTheme.navyColor,
              ),
              decoration: buildInputDecoration(
                label: 'State / Region',
                icon: Icons.location_city_outlined,
              ),
              selectedItemBuilder: (BuildContext context) {
                final states = _countryStatesMap[_selectedCountry] ?? ['Other / International'];
                return states.map((s) {
                  return Row(
                    children: [
                      Text(
                        s,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : AppTheme.navyColor,
                        ),
                      ),
                    ],
                  );
                }).toList();
              },
              items: (_countryStatesMap[_selectedCountry] ?? ['Other / International']).map((s) {
                final isSelected = (_selectedState == s);
                return DropdownMenuItem(
                  value: s,
                  child: Row(
                    children: [
                      const Icon(Icons.pin_drop_outlined, size: 18, color: AppTheme.primaryColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isDark ? Colors.white : AppTheme.navyColor,
                          ),
                        ),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_rounded, size: 18, color: AppTheme.primaryColor),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedState = val);
              },
            ),
            const SizedBox(height: 28),

            // Primary Save Changes Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
                onPressed: _isSaving
                    ? null
                    : () async {
                        final nav = Navigator.of(context);

                        setState(() => _isSaving = true);
                        await CustomerStoreService.updateCustomerProfile(
                          name: _nameCtrl.text.trim(),
                          phone: _phoneCtrl.text.trim(),
                          gender: _selectedGender,
                          country: _selectedCountry,
                          state: _selectedState,
                          avatarUrl: _avatarUrl,
                          bannerUrl: _bannerUrl,
                        );

                        if (!mounted || !context.mounted) return;
                        setState(() => _isSaving = false);
                        HygieneFeedback.showSuccess(
                          context,
                          'Profile details updated successfully!',
                        );
                        nav.pop();
                      },
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Text(
                        'Save Profile Changes',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

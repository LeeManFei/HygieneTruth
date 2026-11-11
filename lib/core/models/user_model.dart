enum UserRole { user, admin, government, owner }

enum AccountStatus { active, suspended, pendingVerification, deactivated }

class UserModel {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final UserRole role;
  final AccountStatus status;
  final String avatarUrl;
  final String? bannerUrl;
  final String? gender;
  final String? country;
  final String? state;
  final String? joinedDate;
  final String? memberTier;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    required this.role,
    required this.status,
    required this.avatarUrl,
    this.bannerUrl,
    this.gender,
    this.country,
    this.state,
    this.joinedDate,
    this.memberTier,
  });

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    UserRole? role,
    AccountStatus? status,
    String? avatarUrl,
    String? bannerUrl,
    String? gender,
    String? country,
    String? state,
    String? joinedDate,
    String? memberTier,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      status: status ?? this.status,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      gender: gender ?? this.gender,
      country: country ?? this.country,
      state: state ?? this.state,
      joinedDate: joinedDate ?? this.joinedDate,
      memberTier: memberTier ?? this.memberTier,
    );
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    UserRole parseRole(String? r) {
      if (r == null) return UserRole.user;
      final clean = r.toLowerCase().trim();
      if (clean == 'businessman' || clean == 'owner' || clean == 'business') return UserRole.owner;
      if (clean == 'admin' || clean == 'administrator') return UserRole.admin;
      if (clean == 'government' || clean == 'inspector' || clean == 'officer') return UserRole.government;
      return UserRole.user;
    }

    AccountStatus parseStatus(String? s) {
      if (s == 'suspended') return AccountStatus.suspended;
      if (s == 'pending' || s == 'pendingVerification') return AccountStatus.pendingVerification;
      if (s == 'deactivated') return AccountStatus.deactivated;
      return AccountStatus.active;
    }

    String? parseBannerUrl() {
      if (map['banner_url'] != null && map['banner_url'].toString().trim().isNotEmpty) {
        return map['banner_url'].toString().trim();
      }
      if (map['settings'] is Map && map['settings']['banner_url'] != null && map['settings']['banner_url'].toString().trim().isNotEmpty) {
        return map['settings']['banner_url'].toString().trim();
      }
      return null;
    }

    return UserModel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'User',
      email: map['email']?.toString() ?? '',
      phone: map['phone']?.toString(),
      role: parseRole(map['role']?.toString()),
      status: parseStatus(map['status']?.toString()),
      avatarUrl: (map['avatar_url'] != null && map['avatar_url'].toString().isNotEmpty)
          ? map['avatar_url'].toString()
          : '',
      bannerUrl: parseBannerUrl(),
      gender: map['gender']?.toString(),
      country: map['country']?.toString(),
      state: map['state']?.toString(),
      joinedDate: map['created_at']?.toString().split('T').first ?? (map['joined_date']?.toString() ?? '2026-08-08'),
      memberTier: map['member_tier']?.toString() ?? 'Silver Member',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role.name,
      'status': status.name,
      'avatar_url': avatarUrl,
      'banner_url': bannerUrl,
      'gender': gender,
      'country': country,
      'state': state,
      'created_at': joinedDate,
      'joined_date': joinedDate,
      'member_tier': memberTier,
    };
  }
}

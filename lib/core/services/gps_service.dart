import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import '../config/app_env.dart';

class GpsService {
  static String? lastKnownCity;
  static String? lastKnownCountry;
  static String lastLocationSource = 'Default';
  static Position? _cachedPosition;
  static DateTime? _cacheTimestamp;

  /// Fast parallel network / router IP geolocation with 1.5s timeout
  static Future<Position?> getLocationFromIp() async {
    // Check in-memory cache (valid for 5 minutes)
    if (_cachedPosition != null && _cacheTimestamp != null &&
        DateTime.now().difference(_cacheTimestamp!).inMinutes < 5) {
      return _cachedPosition;
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(milliseconds: 1500);

    Future<Position?> queryIpApi() async {
      try {
        final request = await client.getUrl(Uri.parse('http://ip-api.com/json')).timeout(const Duration(milliseconds: 1500));
        final response = await request.close().timeout(const Duration(milliseconds: 1500));
        if (response.statusCode == 200) {
          final responseBody = await response.transform(utf8.decoder).join();
          final data = jsonDecode(responseBody) as Map<String, dynamic>;
          if (data['status'] == 'success' && data['lat'] != null && data['lon'] != null) {
            final lat = (data['lat'] as num).toDouble();
            final lon = (data['lon'] as num).toDouble();
            lastKnownCity = data['city']?.toString();
            lastKnownCountry = data['country']?.toString();
            lastLocationSource = 'Router IP (${data['city'] ?? 'Network'})';
            final pos = _createPosition(lat, lon);
            _cachedPosition = pos;
            _cacheTimestamp = DateTime.now();
            return pos;
          }
        }
      } catch (_) {}
      return null;
    }

    Future<Position?> queryIpWhoIs() async {
      try {
        final request = await client.getUrl(Uri.parse('https://ipwho.is/')).timeout(const Duration(milliseconds: 1500));
        final response = await request.close().timeout(const Duration(milliseconds: 1500));
        if (response.statusCode == 200) {
          final responseBody = await response.transform(utf8.decoder).join();
          final data = jsonDecode(responseBody) as Map<String, dynamic>;
          if (data['success'] == true && data['latitude'] != null && data['longitude'] != null) {
            final lat = (data['latitude'] as num).toDouble();
            final lon = (data['longitude'] as num).toDouble();
            lastKnownCity = data['city']?.toString();
            lastKnownCountry = data['country']?.toString();
            lastLocationSource = 'Router IP (${data['city'] ?? 'Network'})';
            final pos = _createPosition(lat, lon);
            _cachedPosition = pos;
            _cacheTimestamp = DateTime.now();
            return pos;
          }
        }
      } catch (_) {}
      return null;
    }

    Future<Position?> queryFreeIpApi() async {
      try {
        final request = await client.getUrl(Uri.parse('https://freeipapi.com/api/json')).timeout(const Duration(milliseconds: 1500));
        final response = await request.close().timeout(const Duration(milliseconds: 1500));
        if (response.statusCode == 200) {
          final responseBody = await response.transform(utf8.decoder).join();
          final data = jsonDecode(responseBody) as Map<String, dynamic>;
          if (data['latitude'] != null && data['longitude'] != null) {
            final lat = (data['latitude'] as num).toDouble();
            final lon = (data['longitude'] as num).toDouble();
            lastKnownCity = data['cityName']?.toString();
            lastKnownCountry = data['countryName']?.toString();
            lastLocationSource = 'Router IP (${data['cityName'] ?? 'Network'})';
            final pos = _createPosition(lat, lon);
            _cachedPosition = pos;
            _cacheTimestamp = DateTime.now();
            return pos;
          }
        }
      } catch (_) {}
      return null;
    }

    // Run parallel fastest-first query
    final results = await Future.wait([queryIpApi(), queryIpWhoIs(), queryFreeIpApi()]);
    for (final pos in results) {
      if (pos != null) return pos;
    }

    return null;
  }

  /// Check GPS permissions and retrieve exact current device/network position
  static Future<Position?> getCurrentLocation({bool forceIp = false}) async {
    if (_cachedPosition != null && _cacheTimestamp != null &&
        DateTime.now().difference(_cacheTimestamp!).inMinutes < 5) {
      return _cachedPosition;
    }

    if (forceIp) {
      final ipPos = await getLocationFromIp();
      if (ipPos != null) return ipPos;
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        final ipPos = await getLocationFromIp();
        return ipPos ?? _getFallbackPosition();
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          final ipPos = await getLocationFromIp();
          return ipPos ?? _getFallbackPosition();
        }
      }

      if (permission == LocationPermission.deniedForever) {
        final ipPos = await getLocationFromIp();
        return ipPos ?? _getFallbackPosition();
      }

      // Fast check for last known position first
      Position? lastKnown = await Geolocator.getLastKnownPosition();
      
      final devicePos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        ),
      ).catchError((_) => lastKnown ?? _getFallbackPosition());

      final distFromRegionalCenterKm = Geolocator.distanceBetween(
        devicePos.latitude,
        devicePos.longitude,
        AppEnv.defaultLatitude,
        AppEnv.defaultLongitude,
      ) / 1000.0;

      final bool isDistantOrEmulator = distFromRegionalCenterKm > 3000.0 ||
          ((devicePos.latitude - 37.422).abs() < 1.0 && (devicePos.longitude - (-122.084)).abs() < 1.0);

      if (isDistantOrEmulator) {
        final ipPos = await getLocationFromIp();
        if (ipPos != null) {
          final ipDistKm = Geolocator.distanceBetween(
            ipPos.latitude,
            ipPos.longitude,
            AppEnv.defaultLatitude,
            AppEnv.defaultLongitude,
          ) / 1000.0;
          if (ipDistKm < 3000.0) {
            _cachedPosition = ipPos;
            _cacheTimestamp = DateTime.now();
            return ipPos;
          }
        }
        return _getFallbackPosition();
      }

      lastLocationSource = 'Device GPS';
      _cachedPosition = devicePos;
      _cacheTimestamp = DateTime.now();
      return devicePos;
    } catch (e) {
      final ipPos = await getLocationFromIp();
      return ipPos ?? _getFallbackPosition();
    }
  }

  static Position _createPosition(double lat, double lon) {
    return Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.now(),
      accuracy: 25.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );
  }

  static double calculateDistanceMeters(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
  }

  static Position _getFallbackPosition() {
    lastLocationSource = 'Default (Bukit Bintang, KL)';
    return _createPosition(AppEnv.defaultLatitude, AppEnv.defaultLongitude);
  }
}

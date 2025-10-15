import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

/// Google Places API-powered location + POI search service
/// Requires: Maps JavaScript API, Places API, Directions API, Geocoding API
class LocationService {
  final String apiKey;

  LocationService({required this.apiKey});

  static LocationService fromEnv(String apiKey) => LocationService(apiKey: apiKey);

  /// Call this when the user first triggers a location-based chat.
  /// It proactively handles permissions + services toggles.
  Future<bool> ensureLocationReady() async {
    // 1) Permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('User denied location permission.');
        return false;
      }
      if (permission == LocationPermission.deniedForever) {
        debugPrint('Permission permanently denied; open app settings.');
        await Geolocator.openAppSettings();
        return false;
      }
    }

    // 2) Services on?
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      await Future.delayed(const Duration(seconds: 1));
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services still disabled after prompt.');
        return false;
      }
    }

    return true;
  }

  /// Get user's current location (assumes ensureLocationReady() was called first)
  Future<Position?> getCurrentLocation() async {
    try {
      final ready = await ensureLocationReady();
      if (!ready) return null;

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      debugPrint('Error getting location: $e');
      return null;
    }
  }

  /// Convert a location string (e.g., "Patia, Bhubaneswar, Odisha") to coordinates
  /// Uses Geocoding API with fallback to Places API Text Search
  Future<LocationCoordinates?> geocodeLocation(String locationQuery) async {
    try {
      // Try Geocoding API first
      final geocodeUri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json',
      ).replace(queryParameters: {
        'address': locationQuery,
        'key': apiKey,
      });

      final geocodeRes = await http.get(geocodeUri);

      if (geocodeRes.statusCode == 200) {
        final data = jsonDecode(geocodeRes.body) as Map<String, dynamic>;

        if (data['status'] == 'OK') {
          final results = (data['results'] as List?) ?? [];
          if (results.isNotEmpty) {
            final firstResult = results[0] as Map<String, dynamic>;
            final geometry = firstResult['geometry'] as Map<String, dynamic>?;
            final location = geometry?['location'] as Map<String, dynamic>?;

            final lat = (location?['lat'] as num?)?.toDouble();
            final lng = (location?['lng'] as num?)?.toDouble();
            final formattedAddress = firstResult['formatted_address'] as String?;

            if (lat != null && lng != null) {
              return LocationCoordinates(
                latitude: lat,
                longitude: lng,
                formattedAddress: formattedAddress ?? locationQuery,
              );
            }
          }
        } else if (data['status'] == 'REQUEST_DENIED') {
          debugPrint('⚠️ Geocoding API not enabled. Falling back to Places Text Search.');
        }
      }

      // Fallback: Use Places API Text Search (doesn't require Geocoding API)
      debugPrint('Using Places Text Search as fallback for location: $locationQuery');

      final placesUri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/textsearch/json',
      ).replace(queryParameters: {
        'query': locationQuery,
        'key': apiKey,
      });

      final placesRes = await http.get(placesUri);

      if (placesRes.statusCode != 200) {
        debugPrint('Places Text Search error: ${placesRes.statusCode}');
        return null;
      }

      final placesData = jsonDecode(placesRes.body) as Map<String, dynamic>;

      if (placesData['status'] != 'OK' && placesData['status'] != 'ZERO_RESULTS') {
        debugPrint('Places Text Search returned status: ${placesData['status']}');
        return null;
      }

      final results = (placesData['results'] as List?) ?? [];
      if (results.isEmpty) return null;

      final firstResult = results[0] as Map<String, dynamic>;
      final geometry = firstResult['geometry'] as Map<String, dynamic>?;
      final location = geometry?['location'] as Map<String, dynamic>?;

      final lat = (location?['lat'] as num?)?.toDouble();
      final lng = (location?['lng'] as num?)?.toDouble();
      final formattedAddress = firstResult['formatted_address'] as String?;

      if (lat == null || lng == null) return null;

      return LocationCoordinates(
        latitude: lat,
        longitude: lng,
        formattedAddress: formattedAddress ?? locationQuery,
      );
    } catch (e) {
      debugPrint('Error geocoding location: $e');
      return null;
    }
  }

  /// Search for doctors/hospitals near a location using Google Places API
  ///
  /// specialty examples: "gynecologist", "cardiologist", "endocrinologist", "pediatrician"
  /// radius in meters (default 5000, max 50000)
  /// gender: null (all), 'male', or 'female'
  Future<List<DoctorResult>> searchDoctors({
    required String specialty,
    required double latitude,
    required double longitude,
    int radius = 5000,
    String? gender,
  }) async {
    try {
      final lower = specialty.toLowerCase().trim();

      // Map user queries to Google Places types and keywords
      String placeType = 'doctor';
      String keyword = '';

      if (lower.contains('gyn') || lower.contains('gynaec') || lower.contains('gynec')) {
        keyword = 'gynecologist';
      } else if (lower.contains('thyroid') || lower.contains('endocrin')) {
        keyword = 'endocrinologist thyroid';
      } else if (lower.contains('cardio')) {
        keyword = 'cardiologist';
      } else if (lower.contains('derma')) {
        keyword = 'dermatologist';
      } else if (lower.contains('pedi')) {
        keyword = 'pediatrician';
      } else if (lower.contains('ortho')) {
        keyword = 'orthopedic';
      } else if (lower.contains('neuro')) {
        keyword = 'neurologist';
      } else if (lower.contains('psychiatr') || lower.contains('mental')) {
        keyword = 'psychiatrist';
      } else if (lower.contains('dent')) {
        placeType = 'dentist';
        keyword = 'dentist';
      } else if (lower.contains('hospital')) {
        placeType = 'hospital';
        keyword = '';
      } else {
        // Generic doctor search
        keyword = lower.isNotEmpty ? lower : 'doctor';
      }

      // Add gender to keyword if specified
      if (gender != null && (gender == 'male' || gender == 'female')) {
        keyword = keyword.isEmpty ? gender : '$keyword $gender';
      }

      // Build Places API Nearby Search request
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json',
      ).replace(queryParameters: {
        'location': '$latitude,$longitude',
        'radius': radius.toString(),
        'type': placeType,
        if (keyword.isNotEmpty) 'keyword': keyword,
        'key': apiKey,
      });

      final res = await http.get(uri);

      if (res.statusCode != 200) {
        debugPrint('Places API error: ${res.statusCode} ${res.body}');
        throw Exception('Failed to search doctors');
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;

      // Check for API errors
      if (data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS') {
        debugPrint('Places API returned status: ${data['status']}');
        if (data['status'] == 'REQUEST_DENIED') {
          throw Exception('API key invalid or Places API not enabled');
        }
        throw Exception('Places API error: ${data['status']}');
      }

      final results = (data['results'] as List?) ?? [];

      final doctors = <DoctorResult>[];

      for (final result in results) {
        if (result is! Map) continue;

        final name = (result['name'] ?? '').toString();
        final vicinity = (result['vicinity'] ?? '').toString();
        final rating = (result['rating'] as num?)?.toDouble();
        final userRatingsTotal = (result['user_ratings_total'] as num?)?.toInt();
        final placeId = (result['place_id'] ?? '').toString();

        final geometry = result['geometry'] as Map<String, dynamic>?;
        final location = geometry?['location'] as Map<String, dynamic>?;
        final lat = (location?['lat'] as num?)?.toDouble();
        final lon = (location?['lng'] as num?)?.toDouble();

        final businessStatus = result['business_status']?.toString();
        final isOpen = businessStatus != 'CLOSED_PERMANENTLY' &&
            businessStatus != 'CLOSED_TEMPORARILY';

        // Basic gender filtering based on name (not perfect, but helps)
        String? detectedGender;
        if (gender != null) {
          detectedGender = _detectGenderFromName(name);
        }

        doctors.add(DoctorResult(
          name: name,
          address: vicinity,
          rating: rating,
          userRatingsTotal: userRatingsTotal,
          latitude: lat,
          longitude: lon,
          placeId: placeId,
          isOpen: isOpen,
          detectedGender: detectedGender,
        ));
      }

      // Filter by gender if specified (based on detection)
      var filteredDoctors = doctors;
      if (gender != null && (gender == 'male' || gender == 'female')) {
        // Strict filtering: only include if gender matches OR uncertain
        filteredDoctors = doctors.where((d) {
          // If we detected a gender and it doesn't match, exclude it
          if (d.detectedGender != null && d.detectedGender != gender) {
            return false;
          }
          return true;
        }).toList();

        // Prioritize confirmed gender matches
        filteredDoctors.sort((a, b) {
          if (a.detectedGender == gender && b.detectedGender != gender) {
            return -1;
          }
          if (b.detectedGender == gender && a.detectedGender != gender) {
            return 1;
          }
          return 0;
        });
      }

      // Sort by rating (descending), then by number of ratings
      filteredDoctors.sort((a, b) {
        // Prioritize open businesses
        if (a.isOpen != b.isOpen) {
          return a.isOpen ? -1 : 1;
        }

        // Then by rating
        final ratingA = a.rating ?? 0;
        final ratingB = b.rating ?? 0;
        if (ratingA != ratingB) {
          return ratingB.compareTo(ratingA);
        }

        // Then by number of ratings
        final countA = a.userRatingsTotal ?? 0;
        final countB = b.userRatingsTotal ?? 0;
        return countB.compareTo(countA);
      });

      return filteredDoctors.take(15).toList();
    } catch (e) {
      debugPrint('Error searching doctors (Google Places): $e');
      rethrow;
    }
  }

  /// Simple heuristic to detect gender from doctor's name
  /// Returns 'male', 'female', or null if uncertain
  String? _detectGenderFromName(String name) {
    final lower = name.toLowerCase();

    // Common female titles and name patterns (expanded)
    if (lower.contains('dr. (mrs)') ||
        lower.contains('dr. mrs') ||
        lower.contains('dr.(mrs)') ||
        lower.contains('dr mrs') ||
        lower.contains('dr. ms') ||
        lower.contains('dr ms') ||
        lower.contains('dr. (ms)') ||
        lower.contains('dr.(ms)') ||
        lower.contains('(female)') ||
        lower.contains('women') ||
        lower.contains('ladies') ||
        lower.contains('lady doctor') ||
        lower.contains('miss ') ||
        lower.contains('smt.') ||
        lower.contains('smt ') ||
        lower.contains('kumari') ||
        // Common Indian female name endings
        lower.endsWith('devi') ||
        lower.endsWith('bai') ||
        lower.contains(' devi ') ||
        // Common female first names (add more as needed)
        lower.contains(' priya ') ||
        lower.contains(' anjali ') ||
        lower.contains(' kavita ') ||
        lower.contains(' sunita ') ||
        lower.contains(' neeta ') ||
        lower.contains(' meera ') ||
        lower.contains(' geeta ') ||
        lower.contains(' asha ') ||
        lower.contains(' usha ') ||
        lower.contains(' rekha ') ||
        lower.contains(' shilpa ') ||
        lower.contains(' swati ') ||
        lower.contains(' deepika ') ||
        lower.contains(' anita ') ||
        lower.contains(' smita ') ||
        lower.contains(' nisha ') ||
        lower.contains(' pooja ') ||
        lower.contains(' sapna ') ||
        lower.startsWith('dr. priya ') ||
        lower.startsWith('dr. anjali ') ||
        lower.startsWith('dr. kavita ') ||
        lower.startsWith('dr priya ') ||
        lower.startsWith('dr anjali ') ||
        lower.startsWith('dr kavita ')) {
      return 'female';
    }

    // Common male titles
    if (lower.contains('dr. (mr)') ||
        lower.contains('dr. mr') ||
        lower.contains('dr.(mr)') ||
        lower.contains('dr mr') ||
        lower.contains('(male)') ||
        lower.contains('shri ') ||
        lower.contains('sri ') ||
        lower.contains('kumar ') ||
        lower.startsWith('dr. kumar ') ||
        lower.startsWith('dr kumar ')) {
      return 'male';
    }

    return null; // Uncertain
  }

  /// Get detailed information about a place
  Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json',
      ).replace(queryParameters: {
        'place_id': placeId,
        'fields': 'name,formatted_address,formatted_phone_number,rating,user_ratings_total,opening_hours,website,reviews',
        'key': apiKey,
      });

      final res = await http.get(uri);

      if (res.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;

      if (data['status'] != 'OK') {
        return null;
      }

      return data['result'] as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('Error getting place details: $e');
      return null;
    }
  }

  /// Build a Google Maps URL with a marker at the location
  static String getGoogleMapsUrl(DoctorResult doctor) {
    final lat = doctor.latitude;
    final lon = doctor.longitude;
    final placeId = doctor.placeId;

    if (placeId.isNotEmpty) {
      // Use Place ID for most accurate result
      return 'https://www.google.com/maps/search/?api=1&query=Google&query_place_id=$placeId';
    } else if (lat != null && lon != null) {
      // Fallback to coordinates
      return 'https://www.google.com/maps/search/?api=1&query=$lat,$lon';
    } else {
      // Last resort: search by name
      final q = Uri.encodeComponent(doctor.name);
      return 'https://www.google.com/maps/search/?api=1&query=$q';
    }
  }

  /// Get directions URL from user location to doctor
  static String getDirectionsUrl({
    required double fromLat,
    required double fromLon,
    required DoctorResult doctor,
  }) {
    final toLat = doctor.latitude;
    final toLon = doctor.longitude;

    if (toLat != null && toLon != null) {
      return 'https://www.google.com/maps/dir/?api=1&origin=$fromLat,$fromLon&destination=$toLat,$toLon';
    }
    return getGoogleMapsUrl(doctor);
  }
}

class LocationCoordinates {
  final double latitude;
  final double longitude;
  final String formattedAddress;

  LocationCoordinates({
    required this.latitude,
    required this.longitude,
    required this.formattedAddress,
  });
}

class DoctorResult {
  final String name;
  final String address;
  final double? rating;
  final int? userRatingsTotal;
  final double? latitude;
  final double? longitude;
  final String placeId;
  final bool isOpen;
  final String? detectedGender;

  DoctorResult({
    required this.name,
    required this.address,
    this.rating,
    this.userRatingsTotal,
    this.latitude,
    this.longitude,
    required this.placeId,
    this.isOpen = true,
    this.detectedGender,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'rating': rating,
    'user_ratings_total': userRatingsTotal,
    'latitude': latitude,
    'longitude': longitude,
    'place_id': placeId,
    'is_open': isOpen,
    'detected_gender': detectedGender,
  };

  factory DoctorResult.fromJson(Map<String, dynamic> json) => DoctorResult(
    name: json['name'] ?? '',
    address: json['address'] ?? '',
    rating: (json['rating'] as num?)?.toDouble(),
    userRatingsTotal: (json['user_ratings_total'] as num?)?.toInt(),
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    placeId: json['place_id'] ?? '',
    isOpen: json['is_open'] ?? true,
    detectedGender: json['detected_gender'] as String?,
  );
}
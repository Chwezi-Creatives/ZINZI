// lib/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'console_data_models.dart';
import 'package:flutter/foundation.dart';

class BatchUpdateResult {
  final bool success;
  final int successCount;
  final int failureCount;
  final List<BatchUpdateError>? errors;
  final String? message;

  BatchUpdateResult({
    required this.success,
    required this.successCount,
    required this.failureCount,
    this.errors,
    this.message,
  });

  factory BatchUpdateResult.fromJson(Map<String, dynamic> json) {
    return BatchUpdateResult(
      success: json['success'] ?? false,
      successCount: json['success_count'] ?? 0,
      failureCount: json['failure_count'] ?? 0,
      errors: json['errors'] != null
          ? List<BatchUpdateError>.from(
              json['errors'].map((x) => BatchUpdateError.fromJson(x)))
          : null,
      message: json['message'],
    );
  }
}

class BatchUpdateError {
  final String id;
  final String error;

  BatchUpdateError({required this.id, required this.error});

  factory BatchUpdateError.fromJson(Map<String, dynamic> json) {
    return BatchUpdateError(
      id: json['id']?.toString() ?? '',
      error: json['error']?.toString() ?? 'Unknown error',
    );
  }

  @override
  String toString() => 'ID: $id - $error';
}

class LoginResult {
  final bool success;
  final String? error;
  final int? retryAfter; // Duration in seconds

  LoginResult({required this.success, this.error, this.retryAfter});
  
  // Helper method to format the retry after duration
  String get formattedRetryAfter {
    if (retryAfter == null) return '';
    
    if (retryAfter! < 60) {
      return 'Please try again in $retryAfter seconds.';
    } else if (retryAfter! < 3600) {
      final minutes = (retryAfter! / 60).ceil();
      return 'Please try again in $minutes minute${minutes > 1 ? 's' : ''}.';
    } else {
      final hours = (retryAfter! / 3600).ceil();
      return 'Please try again in $hours hour${hours > 1 ? 's' : ''}.';
    }
  }
}

class ApiService {
  final String _baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://localhost:3000';

  // --- Authentication ---
  Future<LoginResult> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/rr/login2'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      if (response.statusCode == 200) {
        return LoginResult(success: true);
      } else if (response.statusCode == 401) {
        return LoginResult(success: false, error: 'Invalid username or password');
      } else if (response.statusCode == 429) {
        // Parse retry-after header if available
        final retryAfter = response.headers['retry-after'] != null 
            ? int.tryParse(response.headers['retry-after'] ?? '') 
            : null;
            
        return LoginResult(
          success: false, 
          error: 'Too many failed attempts. ${retryAfter != null ? 'Please try again later.' : ''}',
          retryAfter: retryAfter,
        );
      } else {
        return LoginResult(success: false, error: 'Login failed with status code: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Login failed: $e');
      return LoginResult(success: false, error: 'Network error. Please check your connection.');
    }
  }

  // --- Generic Fetcher ---
  Future<List<T>> fetchItems<T extends Product> (
    String endpoint, 
    T Function(Map<String, dynamic>) fromJson
  ) async {
    try {
      // Handle endpoint inconsistencies
      final String backendEndpoint = endpoint == 'herbals' ? 'rherbals' : endpoint;
      final response = await http.get(Uri.parse('$_baseUrl/rr/$backendEndpoint'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        final List<dynamic> data = body['data'];
        return data.map((jsonItem) => fromJson(jsonItem)).toList();
      } else {
        throw Exception('Failed to load items from $endpoint');
      }
    } catch (e) {
      debugPrint('Error fetching $endpoint: $e');
      return []; // Return empty list on error
    }
  }
  
  // --- Batch Price Updates ---
  Future<BatchUpdateResult> batchUpdatePrices({
    required String category,
    required List<Map<String, dynamic>> updates,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('$_baseUrl/rr/batch-update-prices'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'category': category,
          'updates': updates,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        
        // Convert backend response to frontend format
        final results = responseData['results'] ?? {};
        final successCount = responseData['success_count'] ?? (results['success'] as List?)?.length ?? 0;
        final errorCount = responseData['error_count'] ?? (results['errors'] as List?)?.length ?? 0;
        
        return BatchUpdateResult(
          success: responseData['status'] == 'completed',
          successCount: successCount,
          failureCount: errorCount,
          errors: (results['errors'] as List?)?.map((e) => BatchUpdateError(
            id: e['id']?.toString() ?? 'unknown',
            error: e['error']?.toString() ?? 'Unknown error',
          )).toList(),
          message: 'Updated $successCount items. ${errorCount > 0 ? '$errorCount items failed to update.' : ''}',
        );
      } else {
        // Handle different error status codes
        String errorMessage = 'Failed to update prices';
        if (response.statusCode == 400) {
          errorMessage = 'Invalid request. Please check the data and try again.';
        } else if (response.statusCode == 404) {
          errorMessage = 'Category not found';
        } else if (response.statusCode >= 500) {
          errorMessage = 'Server error. Please try again later.';
        }
        
        return BatchUpdateResult(
          success: false,
          successCount: 0,
          failureCount: updates.length,
          message: errorMessage,
        );
      }
    } catch (e) {
      debugPrint('Batch update failed: $e');
      return BatchUpdateResult(
        success: false,
        successCount: 0,
        failureCount: updates.length,
        message: 'Network error. Please check your connection.',
      );
    }
  }

  // --- Generic Price Updater ---
  Future<bool> updatePrice(String endpoint, dynamic id, double newPrice) async {
    try {
      // Handle endpoint inconsistencies - meals use 'umeals' for updates
      final String updateEndpoint = endpoint == 'meals' ? 'umeals' : endpoint;
      
      final response = await http.patch(
        Uri.parse('$_baseUrl/rr/$updateEndpoint/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'price': newPrice}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error updating price for $id in $endpoint: $e');
      return false;
    }
  }
}
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  final String baseUrl;
  final Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  ApiService({String? baseUrl}) : baseUrl = baseUrl ?? 'http://localhost:5000';

  // Helper method to handle GET requests
  Future<http.Response> get(
    String path, {
    Map<String, dynamic>? queryParams,
    bool requiresAuth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: queryParams,
    );
    
    final response = await http.get(uri, headers: _headers);
    _checkResponse(response);
    return response;
  }

  // Helper method to handle POST requests
  Future<http.Response> post(
    String path, {
    dynamic body,
    bool requiresAuth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await http.post(
      uri,
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    _checkResponse(response);
    return response;
  }

  // Helper method to handle PUT requests
  Future<http.Response> put(
    String path, {
    dynamic body,
    bool requiresAuth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await http.put(
      uri,
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    _checkResponse(response);
    return response;
  }

  // Helper method to handle DELETE requests
  Future<http.Response> delete(
    String path, {
    bool requiresAuth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await http.delete(
      uri,
      headers: _headers,
    );
    _checkResponse(response);
    return response;
  }

  // Set authentication token
  void setAuthToken(String? token) {
    if (token != null) {
      _headers['Authorization'] = 'Bearer $token';
    } else {
      _headers.remove('Authorization');
    }
  }

  // Check response status code and throw exception if not successful
  void _checkResponse(http.Response response) {
    if (response.statusCode >= 400) {
      throw HttpException(
        'Request failed with status: ${response.statusCode}\n${response.body}',
        uri: response.request?.url,
      );
    }
  }

  // Additional methods needed for console functionality
  Future<List<Map<String, dynamic>>> fetchItems(String category) async {
    final response = await get('/api/$category');
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to load $category');
    }
  }

  Future<bool> batchUpdatePrices(List<Map<String, dynamic>> updates) async {
    final response = await post(
      '/api/items/batch-update-prices',
      body: {'updates': updates},
    );
    return response.statusCode == 200;
  }

  Future<bool> updatePrice(String itemId, double newPrice) async {
    final response = await post(
      '/api/items/$itemId/update-price',
      body: {'price': newPrice},
    );
    return response.statusCode == 200;
  }
}

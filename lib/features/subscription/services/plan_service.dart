import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:zinzi/features/subscription/models/plan_model.dart';
import 'package:zinzi/services/api_service.dart';
import 'package:zinzi/services/storage_service.dart';

class PlanService {
  final ApiService _apiService;
  final StorageService _storageService;

  PlanService({
    required ApiService apiService,
    required StorageService storageService,
  })  : _apiService = apiService,
        _storageService = storageService;

  Future<List<Plan>> getPlans({bool includeInactive = false}) async {
    debugPrint('PlanService: 🔄 Fetching plans with includeInactive=$includeInactive');
    try {
      final response = await _apiService.get(
        '/api/admin/plans',
        queryParams: {'include_inactive': includeInactive.toString()},
        requiresAuth: true,
      );

      debugPrint('PlanService.getPlans: 📥 Received response: ${response.statusCode}\n${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        debugPrint('PlanService: ✅ Successfully parsed ${data.length} plans');
        return data.map((json) => Plan.fromJson(json)).toList();
      } else {
        final error = '❌ Failed to load plans: ${response.statusCode}\n${response.body}';
        debugPrint('PlanService.getPlans: ❌ $error');
        throw Exception(error);
      }
    } catch (e) {
      throw Exception('Failed to load plans: $e');
    }
  }

  Future<Plan> getPlan(int id) async {
    try {
      final response = await _apiService.get(
        '/api/admin/plans/$id',
        requiresAuth: true,
      );

      if (response.statusCode == 200) {
        return Plan.fromJson(jsonDecode(response.body));
      } else if (response.statusCode == 404) {
        throw Exception('Plan not found');
      } else {
        throw Exception('Failed to load plan: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load plan: $e');
    }
  }

  Future<Plan> createPlan(PlanCreateUpdateRequest plan) async {
    debugPrint('PlanService: 🆕 Creating new plan');
    
    try {
      final response = await _apiService.post(
        '/api/admin/plans',
        body: plan.toJson(),
        requiresAuth: true,
      );

      debugPrint('PlanService.createPlan: 📤 Create plan response: ${response.statusCode}');

      if (response.statusCode == 201) {
        final createdPlan = Plan.fromJson(jsonDecode(response.body));
        debugPrint('PlanService: ✅ Created plan: ${createdPlan.id}');
        return createdPlan;
      } else if (response.statusCode == 400 || response.statusCode == 409) {
        final error = jsonDecode(response.body)['detail'] ?? 'Invalid request';
        debugPrint('PlanService.createPlan: ❌ Failed to create plan: $error');
        throw Exception(error);
      } else {
        final error = 'Failed to create plan: ${response.statusCode}';
        debugPrint('PlanService.createPlan: ❌ $error');
        throw Exception(error);
      }
    } catch (e) {
      throw Exception('Failed to create plan: $e');
    }
  }

  Future<Plan> updatePlan(int id, PlanCreateUpdateRequest plan) async {
    debugPrint('PlanService: 🔄 Updating plan $id');
    
    try {
      final response = await _apiService.put(
        '/api/admin/plans/$id',
        body: plan.toJson(),
        requiresAuth: true,
      );

      debugPrint('PlanService.updatePlan: 📤 Update plan response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final updatedPlan = Plan.fromJson(jsonDecode(response.body));
        debugPrint('PlanService: ✅ Updated plan: $id');
        return updatedPlan;
      } else if (response.statusCode == 400 || response.statusCode == 404 || response.statusCode == 409) {
        final error = jsonDecode(response.body)['detail'] ?? 'Invalid request';
        debugPrint('PlanService.updatePlan: ❌ Failed to update plan: $error');
        throw Exception(error);
      } else {
        final error = 'Failed to update plan: ${response.statusCode}';
        debugPrint('PlanService.updatePlan: ❌ $error');
        throw Exception(error);
      }
    } catch (e) {
      throw Exception('Failed to update plan: $e');
    }
  }

  Future<bool> deletePlan(int id) async {
    debugPrint('PlanService: 🗑️  Deleting plan: $id');
    
    try {
      final response = await _apiService.delete(
        '/api/admin/plans/$id',
        requiresAuth: true,
      );

      debugPrint('PlanService.deletePlan: 📤 Delete plan response: ${response.statusCode}');

      if (response.statusCode == 204) {
        debugPrint('PlanService: ✅ Deleted plan: $id');
        return true;
      } else if (response.statusCode == 400 || response.statusCode == 404) {
        final error = jsonDecode(response.body)['detail'] ?? 'Invalid request';
        debugPrint('PlanService.deletePlan: ❌ Failed to delete plan: $error');
        throw Exception(error);
      } else {
        final error = 'Failed to delete plan: ${response.statusCode}';
        debugPrint('PlanService.deletePlan: ❌ $error');
        throw Exception(error);
      }
    } catch (e) {
      final error = 'Failed to delete plan: $e';
      debugPrint('PlanService.deletePlan: ❌ $error');
      throw Exception(error);
    }
  }
}

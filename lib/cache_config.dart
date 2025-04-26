class CacheConfig {
  static const Duration allMealsCacheDuration = Duration(days: 2);
  static const Duration chefNetCacheDuration = Duration(days: 2);
  static const Duration profileCacheDuration = Duration(days: 2);
  static const Duration mealDetailCacheDuration = Duration(days: 2);
  static const Duration chefDashCacheDuration = Duration(days: 1);
  static const Duration producerDashCacheDuration = Duration(days: 2);
  static const Duration transporterDashCacheDuration = Duration(days: 2);

  // --- New Cache Config for Chef/Producer Details ---
  // Duration for how long chef/producer details are considered valid in cache
  static const Duration chefProducerDetailCacheDuration =
      Duration(days: 2); // e.g., 2 days validity

  // --- New for user profile and chef dashboard ---
  static const Duration userProfileCacheDuration = Duration(days: 2);
  static const Duration chefDashboardCacheDuration = Duration(days: 1);

  // Key prefixes for storing chef/producer data in SharedPreferences
  // We'll append the specific ID to these prefixes, e.g., 'chef_detail_123'
  static const String chefDetailCachePrefix = 'chef_detail_';
  static const String producerDetailCachePrefix = 'producer_detail_';
  // Key prefix for the timestamp when the data was cached
  static const String cacheTimestampPrefix = 'cache_ts_';
}

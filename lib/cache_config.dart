class CacheConfig {
  static const Duration allMealsCacheDuration = Duration(days: 2);
  static const Duration chefNetCacheDuration = Duration(minutes: 60);
  static const Duration profileCacheDuration = Duration(minutes: 60);
  static const Duration mealDetailCacheDuration = Duration(minutes: 30);
  static const Duration chefDashCacheDuration = Duration(minutes: 60);
  static const Duration producerDashCacheDuration = Duration(minutes: 60);
  static const Duration transporterDashCacheDuration = Duration(minutes: 60);

  // --- New Cache Config for Chef/Producer Details ---
  // Duration for how long chef/producer details are considered valid in cache
  static const Duration chefProducerDetailCacheDuration = Duration(days: 2); // e.g., 2 days validity

  // Key prefixes for storing chef/producer data in SharedPreferences
  // We'll append the specific ID to these prefixes, e.g., 'chef_detail_123'
  static const String chefDetailCachePrefix = 'chef_detail_';
  static const String producerDetailCachePrefix = 'producer_detail_';
  // Key prefix for the timestamp when the data was cached
  static const String cacheTimestampPrefix = 'cache_ts_';
}

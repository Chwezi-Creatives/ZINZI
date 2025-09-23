from functools import wraps
from typing import Any, Callable, Optional, TypeVar, cast
import json
import hashlib
import time
from fastapi import Request

# Type variable for generic function typing
F = TypeVar('F', bound=Callable[..., Any])

# In-memory cache (simple implementation)
# In production, you might want to use Redis or Memcached instead
_cache = {}
_cache_ttl = {}

# Default TTL in seconds (5 minutes)
DEFAULT_TTL = 300

def generate_cache_key(*args, **kwargs) -> str:
    """Generate a unique cache key from function arguments."""
    # Convert args and kwargs to a string representation
    key_parts = [
        str(arg) for arg in args
    ] + [
        f"{k}={v}" for k, v in sorted(kwargs.items())
    ]
    key_str = "_".join(key_parts)
    
    # Create a hash of the key string
    return hashlib.md5(key_str.encode('utf-8')).hexdigest()

def cached(ttl: int = DEFAULT_TTL):
    """
    Decorator to cache function results with a time-to-live.
    
    Args:
        ttl: Time to live in seconds (default: 300s / 5 minutes)
    """
    def decorator(func: F) -> F:
        @wraps(func)
        async def wrapper(*args, **kwargs) -> Any:
            # Skip caching for non-async functions or if ttl is 0
            if not ttl or not hasattr(func, '__aiter__'):
                return await func(*args, **kwargs)
                
            # Generate cache key
            cache_key = f"{func.__module__}:{func.__name__}:{generate_cache_key(*args, **kwargs)}"
            
            # Check cache
            current_time = time.time()
            if cache_key in _cache:
                # Check if cache entry is still valid
                if _cache_ttl.get(cache_key, 0) > current_time:
                    return _cache[cache_key]
                # Remove expired entry
                _cache.pop(cache_key, None)
                _cache_ttl.pop(cache_key, None)
            
            # Call the function and cache the result
            result = await func(*args, **kwargs)
            _cache[cache_key] = result
            _cache_ttl[cache_key] = current_time + ttl
            
            return result
            
        return cast(F, wrapper)
    return decorator

def invalidate_cache(*cache_keys: str) -> None:
    """Invalidate cache entries by their keys."""
    for key in cache_keys:
        _cache.pop(key, None)
        _cache_ttl.pop(key, None)

def get_cache(key: str) -> Any:
    """Get a value from the cache by key.
    
    Args:
        key: The cache key to look up
        
    Returns:
        The cached value if found and not expired, None otherwise
    """
    if key in _cache and (key not in _cache_ttl or _cache_ttl[key] > time.time()):
        return _cache[key]
    # Remove expired cache entries
    if key in _cache:
        del _cache[key]
    if key in _cache_ttl:
        del _cache_ttl[key]
    return None

def set_cache(key: str, value: Any, ttl: int = DEFAULT_TTL) -> None:
    """Store a value in the cache with an optional time-to-live.
    
    Args:
        key: The cache key to store the value under
        value: The value to cache
        ttl: Time to live in seconds (default: 300s / 5 minutes)
    """
    _cache[key] = value
    if ttl > 0:
        _cache_ttl[key] = time.time() + ttl
    elif key in _cache_ttl:
        del _cache_ttl[key]

def clear_all_caches() -> None:
    """Clear all cached data."""
    _cache.clear()
    _cache_ttl.clear()

# Example usage:
# @cached(ttl=300)  # Cache for 5 minutes
# async def get_expensive_data():
#     # Expensive operation here
#     return data

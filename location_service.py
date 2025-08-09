"""
Location Service for handling geofencing and distance calculations.
"""
import os
import logging
import sys
from typing import List, Dict, Any, Optional, Tuple, TypeVar, Generic, Callable

# Configure logging to output to console
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    stream=sys.stdout
)
logger = logging.getLogger(__name__)

import math
import re
import asyncio
from async_lru import alru_cache  # For async caching

# Type variable for entity type
T = TypeVar('T', Dict[str, Any], Any)

class LocationService:
    """
    Service for handling location-based operations including geofencing.
    This service is fully asynchronous.
    """
    
    # Thread-safe cache for coordinate extraction
    _coord_cache = {}
    _coord_cache_lock = asyncio.Lock()
    
    @classmethod
    async def _extract_coordinates(cls, address: Optional[str]) -> Optional[Tuple[float, float]]:
        """
        Extract latitude and longitude from an address string asynchronously.
        Reuses the same logic as Orders._extract_coordinates.
        
        Args:
            address: The address string potentially containing coordinates
            
        Returns:
            Tuple of (latitude, longitude) or None if not found
        """
        if not address:
            logger.warning("No address provided to _extract_coordinates")
            return None
            
        logger.info(f"Extracting coordinates from: {address}")
            
        # Check cache first in a thread-safe way
        async with cls._coord_cache_lock:
            if address in cls._coord_cache:
                return cls._coord_cache[address]
        
        # Try to extract coordinates from various formats
        # 1. Direct coordinate pair: "-1.2921, 36.8219" or inside parentheses like "(0.3375104, 32.571392)"
        coord_match = re.search(r'(?:\(|\b)(-?\d{1,3}\.\d+),\s*(-?\d{1,3}\.\d+)(?:\)|\b)', address)
        if coord_match:
            try:
                lat = float(coord_match.group(1))
                lng = float(coord_match.group(2))
                logger.info(f"Found coordinates in pattern 1: lat={lat}, lng={lng}")
                if -90 <= lat <= 90 and -180 <= lng <= 180:
                    result = (lat, lng)
                    async with cls._coord_cache_lock:
                        cls._coord_cache[address] = result
                    return result
                else:
                    logger.warning(f"Coordinates out of valid range: lat={lat}, lng={lng}")
            except (ValueError, IndexError) as e:
                logger.warning(f"Error parsing coordinates: {e}")
                pass
                
        # 2. DMS format: "1°17'31.6\"S 36°49'18.8\"E"
        dms_match = re.search(
            r'(\d{1,3})°(\d{1,2})[\'′]?(\d{1,2}(?:\.\d+)?)[\"″]?\s*([NS])\s*' 
            r'(\d{1,3})°(\d{1,2})[\'′]?(\d{1,2}(?:\.\d+)?)[\"″]?\s*([EW])', 
            address, 
            re.IGNORECASE
        )
        
        if dms_match:
            try:
                lat_deg = float(dms_match.group(1))
                lat_min = float(dms_match.group(2))
                lat_sec = float(dms_match.group(3))
                lat_dir = dms_match.group(4).upper()
                
                lng_deg = float(dms_match.group(5))
                lng_min = float(dms_match.group(6))
                lng_sec = float(dms_match.group(7))
                lng_dir = dms_match.group(8).upper()
                
                # Convert DMS to decimal degrees
                lat = lat_deg + lat_min/60 + lat_sec/3600
                if lat_dir == 'S':
                    lat = -lat
                    
                lng = lng_deg + lng_min/60 + lng_sec/3600
                if lng_dir == 'W':
                    lng = -lng
                    
                if -90 <= lat <= 90 and -180 <= lng <= 180:
                    result = (lat, lng)
                    async with cls._coord_cache_lock:
                        cls._coord_cache[address] = result
                    return result
            except (ValueError, IndexError):
                pass
                
        # 3. Other formats could be added here
        
        return None
    
    @staticmethod
    @alru_cache(maxsize=4096)
    async def haversine(coord1: Tuple[float, float], coord2: Tuple[float, float]) -> float:
        """
        Calculate the great circle distance between two points 
        on the earth specified in decimal degrees of latitude and longitude.
        This method is async and uses alru_cache for async caching.
        
        Args:
            coord1: Tuple of (latitude, longitude) for first point
            coord2: Tuple of (latitude, longitude) for second point
            
        Returns:
            Distance in kilometers
        """
        # Convert decimal degrees to radians
        lat1, lon1 = math.radians(coord1[0]), math.radians(coord1[1])
        lat2, lon2 = math.radians(coord2[0]), math.radians(coord2[1])
        
        # Haversine formula
        dlat = lat2 - lat1
        dlon = lon2 - lon1
        a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
        c = 2 * math.asin(math.sqrt(a))
        
        # Radius of earth in kilometers
        r = 6371.0
        return c * r
    
    @classmethod
    async def geo_fence_entities(
        cls,
        entities: List[Dict[str, Any]],
        user_location: str,
        location_field: str = 'location',
        radius_km: Optional[float] = None
    ) -> List[Dict[str, Any]]:
        """
        Asynchronously filter entities based on their proximity to a user's location.
        
        Args:
            entities: List of entity dictionaries, each must contain a location field
            user_location: The user's location as a string (will be parsed for coordinates)
            location_field: The field name in the entity that contains the location string
            radius_km: Optional. Maximum distance in kilometers. If not provided, 
                     will use GEO_RADIUS from .env or default to 5.0km
            
        Returns:
            Filtered list of entities within the specified radius
        """
        if not entities:
            return []
            
        # Get radius from environment variable if not provided
        if radius_km is None:
            try:
                # Using 'geo_radius' to match the .env file
                radius_km = float(os.getenv('geo_radius', '90000'))
            except (ValueError, TypeError):
                radius_km = 90000.0  # Default to 90000km if not set or invalid
        
        # Extract user coordinates
        user_coords = await cls._extract_coordinates(user_location)
        if not user_coords:
            logging.warning(f"Could not extract coordinates from user location: {user_location}")
            return []
        
        filtered_entities = []
        
        # Process entities in parallel for better performance
        tasks = []
        for entity in entities:
            tasks.append(cls._process_entity(
                entity, user_coords, location_field, radius_km
            ))
        
        # Gather all results
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Filter out None results and exceptions
        filtered_entities = [r for r in results if r is not None and not isinstance(r, Exception)]
        
        # Sort by distance if we have distances
        if filtered_entities and '_distance_km' in filtered_entities[0]:
            filtered_entities.sort(key=lambda x: x['_distance_km'])
            
        return filtered_entities
    
    @classmethod
    async def _process_entity(
        cls,
        entity: Dict[str, Any],
        user_coords: Tuple[float, float],
        location_field: str,
        radius_km: float
    ) -> Optional[Dict[str, Any]]:
        """
        Process a single entity to check if it's within the geofence.
        
        Args:
            entity: The entity to process
            user_coords: User's coordinates as (lat, lng)
            location_field: Field name containing location string
            radius_km: Maximum allowed distance in kilometers
            
        Returns:
            Entity with distance if within radius, None otherwise
        """
        entity_location = entity.get(location_field)
        if not entity_location:
            return None
            
        # Extract entity coordinates
        entity_coords = await cls._extract_coordinates(entity_location)
        if not entity_coords:
            return None
            
        # Calculate distance
        try:
            distance = await cls.haversine(user_coords, entity_coords)
            if distance <= radius_km:
                # Create a new dict to avoid modifying the original
                filtered_entity = dict(entity)
                filtered_entity['_distance_km'] = round(distance, 2)
                return filtered_entity
        except (ValueError, TypeError) as e:
            logging.warning(f"Error calculating distance: {e}")
            
        return None

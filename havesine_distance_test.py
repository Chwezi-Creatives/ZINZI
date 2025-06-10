import math

def haversine_distance(lat1, lon1, lat2, lon2, unit='km'):
    """
    Calculate the distance between two points on Earth using the Haversine formula.

    Args:
        lat1 (float): Latitude of the first point in decimal degrees.
        lon1 (float): Longitude of the first point in decimal degrees.
        lat2 (float): Latitude of the second point in decimal degrees.
        lon2 (float): Longitude of the second point in decimal degrees.
        unit (str, optional): The unit for the returned distance.
                              'km' for kilometers (default)
                              'm' for meters
                              'mi' for miles

    Returns:
        float: The distance between the two points in the specified unit.
               Returns None if an invalid unit is provided.
    """
    # Earth's mean radius in different units
    radius_km = 6371.0
    radius_mi = 3958.75
    
    R = 0
    if unit == 'km':
        R = radius_km
    elif unit == 'm':
        R = radius_km * 1000  # Convert km to meters
    elif unit == 'mi':
        R = radius_mi
    else:
        print(f"Error: Invalid unit '{unit}'. Please use 'km', 'm', or 'mi'.")
        return None

    # Convert latitudes and longitudes from degrees to radians
    lat1_rad = math.radians(lat1)
    lon1_rad = math.radians(lon1)
    lat2_rad = math.radians(lat2)
    lon2_rad = math.radians(lon2)

    # Haversine formula
    dlon = lon2_rad - lon1_rad
    dlat = lat2_rad - lat1_rad

    a = math.sin(dlat / 2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlon / 2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    distance = R * c
    return distance

# --- Helper function to parse coordinate string ---
def parse_coords(coord_string):
    """
    Parses a comma-separated coordinate string "latitude,longitude" into two floats.

    Args:
        coord_string (str): A string like "0.3244032,32.571392".

    Returns:
        tuple: A tuple (latitude, longitude) as floats, or (None, None) if parsing fails.
    """
    try:
        parts = coord_string.split(',')
        if len(parts) == 2:
            lat = float(parts[0].strip())
            lon = float(parts[1].strip())
            return lat, lon
        else:
            print("Error: Coordinate string must contain exactly one comma separating latitude and longitude.")
            return None, None
    except ValueError:
        print("Error: Invalid numerical format in coordinates.")
        return None, None
    except Exception as e:
        print(f"An unexpected error occurred during coordinate parsing: {e}")
        return None, None

# --- Example Usage ---
if __name__ == "__main__":
    print("--- Haversine Distance Calculator ---")

    # Point 1: New York City
    lat1_nyc = 40.7128
    lon1_nyc = -74.0060

    # Point 2: London
    lat2_london = 51.5074
    lon2_london = -0.1278

    # Calculate distance in kilometers
    distance_nyc_london_km = haversine_distance(lat1_nyc, lon1_nyc, lat2_london, lon2_london, unit='km')
    if distance_nyc_london_km is not None:
        print(f"Distance between New York City and London (km): {distance_nyc_london_km:.2f} km")

    # Calculate distance in miles
    distance_nyc_london_mi = haversine_distance(lat1_nyc, lon1_nyc, lat2_london, lon2_london, unit='mi')
    if distance_nyc_london_mi is not None:
        print(f"Distance between New York City and London (mi): {distance_nyc_london_mi:.2f} mi")

    # Current location (Kampala, Uganda)
    kampala_lat = 0.3476
    kampala_lon = 32.5825
    print(f"\nYour current context location is Kampala, Uganda: {kampala_lat},{kampala_lon}")

    # You can now get input from the user in the desired format
    try:
        print("\n--- Enter your own coordinates ---")
        
        coords_str1 = input("Enter coordinates for point 1 (e.g., '0.3244032,32.571392'): ")
        lat1, lon1 = parse_coords(coords_str1)
        
        coords_str2 = input("Enter coordinates for point 2 (e.g., '0.3476,32.5825'): ")
        lat2, lon2 = parse_coords(coords_str2)

        if lat1 is None or lon1 is None or lat2 is None or lon2 is None:
            print("Failed to parse one or both coordinate pairs. Please try again.")
        else:
            user_unit = input("Enter desired unit ('km', 'm', or 'mi'): ").lower()

            user_distance = haversine_distance(lat1, lon1, lat2, lon2, unit=user_unit)
            if user_distance is not None:
                print(f"Distance between your points: {user_distance:.2f} {user_unit}")
    except Exception as e:
        print(f"An unexpected error occurred during user input: {e}")
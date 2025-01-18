import os
import requests
import base64
import uuid  # To generate X-Reference-Id
from dotenv import load_dotenv

load_dotenv()

# MTN MoMo API credentials
BASE_URL = os.getenv("MOMO")  # Sandbox URL, replace with production URL for live use
SUBSCRIPTION_KEY = os.getenv("MOMO_SUBSCRIPTION_KEY")  # Your subscription key from MoMo portal
CALLBACK_URL = os.getenv("OR11") 
X_REFERENCE_ID = str(uuid.uuid4())  # Generate a UUID if not set in .env

# -----------------------
# 1. Create API User
# -----------------------
def create_api_user():
    """Step 1: Create an API user to interact with MoMo API."""
    url = f"{BASE_URL}/v1_0/apiuser"
    headers = {
        "Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY,
        "Content-Type": "application/json",
        "X-Reference-Id": X_REFERENCE_ID
    }
    data = {
        "providerCallbackHost": CALLBACK_URL
    }

    # Log the request details
    print("----- API User Creation Request -----")
    print(f"URL: {url}")
    print(f"Headers: {headers}")
    print(f"Data: {data}")
    print(f"X-Reference-Id: {X_REFERENCE_ID}")

    response = requests.post(url, headers=headers, json=data)

    # Log the response details
    print("----- API User Creation Response -----")
    print(f"Status Code: {response.status_code}")
    print(f"Response Text: {response.text}")

    # Handle response
    if response.status_code == 201:
        print("API User created successfully!")
        return X_REFERENCE_ID
    elif response.status_code == 409:
        print(f"Conflict: The X-Reference-Id {X_REFERENCE_ID} is already in use.")
        raise Exception("Duplicate X-Reference-Id error. Please retry with a new UUID.")
    else:
        print("Failed to create API User.")
        response.raise_for_status()

# -----------------------
# 2. Generate API Key
# -----------------------
def generate_api_key(x_reference_id):
    """Step 2: Generate an API Key for the created API user."""
    url = f"{BASE_URL}/v1_0/apiuser/{x_reference_id}/apikey"
    headers = {
        "Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY
    }

    print("----- API Key Generation Request -----")
    print(f"URL: {url}")
    print(f"Headers: {headers}")

    response = requests.post(url, headers=headers)

    # Log the response details
    print("----- API Key Generation Response -----")
    print(f"Status Code: {response.status_code}")
    print(f"Response Text: {response.text}")

    if response.status_code == 201:
        print("API Key generated successfully!")
        return response.json()["apiKey"]
    else:
        print("Failed to generate API Key.")
        response.raise_for_status()

# -----------------------
# 3. Get Access Token
# -----------------------
def get_access_token(x_reference_id, api_key):
    """Step 3: Generate an access token for authentication in MoMo API requests."""
    url = f"{BASE_URL}/collection/token/"
    # Create a Basic Authentication header with user_id and api_key
    auth_header = base64.b64encode(f"{x_reference_id}:{api_key}".encode()).decode()

    headers = {
        "Authorization": f"Basic {auth_header}",
        "Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY,
        "Content-Type": "application/json"
    }

    print("----- Access Token Request -----")
    print(f"URL: {url}")
    print(f"Headers: {headers}")

    response = requests.post(url, headers=headers)

    # Log the response details
    print("----- Access Token Response -----")
    print(f"Status Code: {response.status_code}")
    print(f"Response Text: {response.text}")

    if response.status_code == 200:
        print("Access token retrieved successfully!")
        return response.json()["access_token"]
    else:
        print("Failed to retrieve access token.")
        response.raise_for_status()

# -----------------------
# Workflow Automation
# -----------------------
def provision_momo_api():
    """Automates the full provisioning process:
    1. Create API User.
    2. Generate API Key.
    3. Generate Access Token.
    """
    print("Starting MoMo API provisioning...")

    # Step 1: Create API User
    x_reference_id = create_api_user()
    print("X-Reference-Id:", x_reference_id)

    # Step 2: Generate API Key
    api_key = generate_api_key(x_reference_id)
    print("API Key:", api_key)

    # Step 3: Get Access Token
    access_token = get_access_token(x_reference_id, api_key)
    print("Access Token:", access_token)

    return {
        "x_reference_id": x_reference_id,
        "api_key": api_key,
        "access_token": access_token
    }

if __name__ == "__main__":
    credentials = provision_momo_api()
    print("\n----- Final Credentials -----")
    print(credentials)
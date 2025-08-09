import os
import requests
import base64
import uuid
import time
from dotenv import load_dotenv

load_dotenv()

# MTN MoMo API credentials
BASE_URL = os.getenv("MOMO")  # Sandbox URL
SUBSCRIPTION_KEY = os.getenv("MOMO_SUBSCRIPTION_KEY")
CALLBACK_URL = os.getenv("CALLBACK_URL")

class MoMoProvisioningError(Exception):
    """Custom exception for MoMo provisioning errors"""
    pass

def validate_environment():
    """Validate that all required environment variables are set"""
    required_vars = ["MOMO", "MOMO_SUBSCRIPTION_KEY", "CALLBACK_URL"]
    missing_vars = [var for var in required_vars if not os.getenv(var)]
    
    if missing_vars:
        raise MoMoProvisioningError(f"Missing required environment variables: {', '.join(missing_vars)}")
    
    print("✓ Environment variables validated")

def create_api_user(max_retries=3):
    """Step 1: Create an API user with retry logic for UUID conflicts"""
    
    for attempt in range(max_retries):
        x_reference_id = str(uuid.uuid4())
        url = f"{BASE_URL}/v1_0/apiuser"
        headers = {
            "Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY,
            "Content-Type": "application/json",
            "X-Reference-Id": x_reference_id
        }
        data = {
            "providerCallbackHost": CALLBACK_URL
        }

        print(f"----- API User Creation Request (Attempt {attempt + 1}) -----")
        print(f"URL: {url}")
        print(f"X-Reference-Id: {x_reference_id}")

        try:
            response = requests.post(url, headers=headers, json=data, timeout=30)
            
            print(f"Status Code: {response.status_code}")
            print(f"Response Text: {response.text}")

            if response.status_code == 201:
                print("✓ API User created successfully!")
                return x_reference_id
            elif response.status_code == 409:
                print(f"⚠️ Conflict: X-Reference-Id {x_reference_id} already exists. Retrying...")
                continue
            else:
                print(f"❌ Failed to create API User. Status: {response.status_code}")
                response.raise_for_status()
                
        except requests.exceptions.RequestException as e:
            print(f"❌ Network error during API user creation: {e}")
            if attempt == max_retries - 1:
                raise MoMoProvisioningError(f"Failed to create API user after {max_retries} attempts")
            time.sleep(2)  # Wait before retry
    
    raise MoMoProvisioningError("Failed to create API user: too many UUID conflicts")

def generate_api_key(x_reference_id, max_retries=3):
    """Step 2: Generate an API Key with retry logic"""
    
    for attempt in range(max_retries):
        url = f"{BASE_URL}/v1_0/apiuser/{x_reference_id}/apikey"
        headers = {
            "Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY
        }

        print(f"----- API Key Generation Request (Attempt {attempt + 1}) -----")
        print(f"URL: {url}")

        try:
            # Add a small delay to ensure API user is fully created
            if attempt > 0:
                time.sleep(2)
                
            response = requests.post(url, headers=headers, timeout=30)
            
            print(f"Status Code: {response.status_code}")
            print(f"Response Text: {response.text}")

            if response.status_code == 201:
                print("✓ API Key generated successfully!")
                return response.json()["apiKey"]
            elif response.status_code == 404:
                print("⚠️ API User not found. Retrying...")
                continue
            else:
                print(f"❌ Failed to generate API Key. Status: {response.status_code}")
                response.raise_for_status()
                
        except requests.exceptions.RequestException as e:
            print(f"❌ Network error during API key generation: {e}")
            if attempt == max_retries - 1:
                raise MoMoProvisioningError(f"Failed to generate API key after {max_retries} attempts")
            time.sleep(2)
    
    raise MoMoProvisioningError("Failed to generate API key after maximum retries")

def get_access_token(x_reference_id, api_key, max_retries=3):
    """Step 3: Generate an access token with retry logic"""
    
    for attempt in range(max_retries):
        url = f"{BASE_URL}/collection/token/"
        auth_header = base64.b64encode(f"{x_reference_id}:{api_key}".encode()).decode()

        headers = {
            "Authorization": f"Basic {auth_header}",
            "Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY,
            "Content-Type": "application/json"
        }

        print(f"----- Access Token Request (Attempt {attempt + 1}) -----")
        print(f"URL: {url}")

        try:
            response = requests.post(url, headers=headers, timeout=30)
            
            print(f"Status Code: {response.status_code}")
            print(f"Response Text: {response.text}")

            if response.status_code == 200:
                print("✓ Access token retrieved successfully!")
                return response.json()["access_token"]
            elif response.status_code == 401:
                print("⚠️ Unauthorized. Retrying...")
                time.sleep(2)
                continue
            else:
                print(f"❌ Failed to retrieve access token. Status: {response.status_code}")
                response.raise_for_status()
                
        except requests.exceptions.RequestException as e:
            print(f"❌ Network error during access token retrieval: {e}")
            if attempt == max_retries - 1:
                raise MoMoProvisioningError(f"Failed to get access token after {max_retries} attempts")
            time.sleep(2)
    
    raise MoMoProvisioningError("Failed to get access token after maximum retries")

def provision_momo_api():
    """Automates the full provisioning process with improved error handling"""
    
    try:
        print("🚀 Starting MTN MoMo API provisioning...")
        
        # Validate environment
        validate_environment()
        
        # Step 1: Create API User
        print("\n📝 Step 1: Creating API User...")
        x_reference_id = create_api_user()
        print(f"X-Reference-Id: {x_reference_id}")
        
        # Step 2: Generate API Key
        print("\n🔑 Step 2: Generating API Key...")
        api_key = generate_api_key(x_reference_id)
        print(f"API Key: {api_key}")
        
        # Step 3: Get Access Token
        print("\n🎫 Step 3: Getting Access Token...")
        access_token = get_access_token(x_reference_id, api_key)
        print(f"Access Token: {access_token}")
        
        credentials = {
            "x_reference_id": x_reference_id,
            "api_key": api_key,
            "access_token": access_token
        }
        
        print("\n✅ MTN MoMo API provisioning completed successfully!")
        return credentials
        
    except MoMoProvisioningError as e:
        print(f"\n❌ Provisioning failed: {e}")
        return None
    except Exception as e:
        print(f"\n❌ Unexpected error during provisioning: {e}")
        return None

if __name__ == "__main__":
    credentials = provision_momo_api()
    
    if credentials:
        print("\n----- Final Credentials -----")
        for key, value in credentials.items():
            print(f"{key}: {value}")
    else:
        print("\n❌ Provisioning failed. Please check your configuration and try again.")
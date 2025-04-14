import requests
import json
import uuid
from datetime import datetime
from dotenv import load_dotenv
import os

# Load environment variables from .env file
load_dotenv()

# Function to get OAuth2 access token
def get_access_token(client_id, client_secret):
    url = "https://openapiuat.airtel.africa/auth/oauth2/token"  # Sandbox URL, change to production if needed
    headers = {
        "Content-Type": "application/json"
    }
    payload = {
        "client_id": client_id,
        "client_secret": client_secret,
        "grant_type": "client_credentials"
    }
    
    response = requests.post(url, headers=headers, json=payload)
    
    if response.status_code == 200:
        return response.json()["access_token"]
    else:
        raise Exception(f"Failed to get access token: {response.text}")

# Function to initiate a payment request
def request_payment(access_token, phone_number, amount):
    url = "https://openapiuat.airtel.africa/standard/v2/payments/"  # Sandbox URL, change to production if needed
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-Country": "UG",  # Uganda country code
        "X-Currency": "UGX"  # Uganda Shilling
    }
    
    # Generate a unique transaction ID
    transaction_id = str(uuid.uuid4())
    
    # Payment request payload
    payload = {
        "reference": f"Payment-{datetime.now().strftime('%Y%m%d%H%M%S')}",
        "subscriber": {
            "msisdn": phone_number  # Phone number in format 2567XXXXXXXX
        },
        "transaction": {
            "amount": amount,
            "id": transaction_id
        }
    }
    
    response = requests.post(url, headers=headers, json=payload)
    
    if response.status_code in [200, 202]:
        print("Payment request successful!")
        print(json.dumps(response.json(), indent=4))
    else:
        print(f"Payment request failed: {response.status_code}")
        print(response.text)

# Main execution
if __name__ == "__main__":
    # Load credentials and variables from .env
    CLIENT_ID = os.getenv("AIR_CLIENT_ID")
    CLIENT_SECRET = os.getenv("AIR_CLIENT_SECRET")
    
    # Load transaction variables from .env (or override them here if needed)
    PHONE_NUMBER = "256701234567"
    AMOUNT = 1000  # Convert to int, e.g., 5000
    
    # Optional: Override PHONE_NUMBER and AMOUNT here instead of changing .env
    # PHONE_NUMBER = "256701234567"  # Uncomment and set as needed
    # AMOUNT = 10000                # Uncomment and set as needed
    
    try:
        # Validate that all required variables are set
        if not all([CLIENT_ID, CLIENT_SECRET, PHONE_NUMBER, AMOUNT]):
            raise ValueError("Missing required environment variables. Check your .env file.")
        
        # Step 1: Get access token
        access_token = get_access_token(CLIENT_ID, CLIENT_SECRET)
        print("Access token retrieved successfully!")
        
        # Step 2: Request payment
        request_payment(access_token, PHONE_NUMBER, AMOUNT)
        
    except Exception as e:
        print(f"An error occurred: {str(e)}")
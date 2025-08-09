import os
import httpx
import uuid
import base64
from dotenv import load_dotenv
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s:%(name)s:%(message)s')
logger = logging.getLogger(__name__)

# Load environment variables from .env file
load_dotenv()

# --- Configuration ---
DISBURSEMENT_PRIMARY_KEY = os.getenv("DISBURSEMENT_PRIMARY_KEY")
# This is the host that MoMo will call back to for asynchronous notifications
# For sandbox testing, you might use a local tunneling service like ngrok,
# or a placeholder if you're not immediately testing callbacks.
# IMPORTANT: In a real scenario, this must be a publicly accessible URL.
CALLBACK_HOST = os.getenv("CALLBACK_URL") # <--- **UPDATE THIS**

# MoMo API Endpoints (Sandbox)
BASE_URL = "https://sandbox.momodeveloper.mtn.com"
API_USER_URL = f"{BASE_URL}/v1_0/apiuser"
API_KEY_URL_TEMPLATE = f"{BASE_URL}/v1_0/apiuser/{{x_reference_id}}/apikey"

async def provision_disbursement_api_user():
    if not DISBURSEMENT_PRIMARY_KEY:
        logger.error("DISBURSEMENT_PRIMARY_KEY not found in .env file.")
        return

    logger.info("Starting MoMo Disbursement API User Provisioning...")

    # 1. Generate a unique X-Reference-Id (UUID) for the API User
    x_reference_id = str(uuid.uuid4())
    logger.info(f"Generated X-Reference-Id: {x_reference_id}")

    # 2. Create API User
    headers = {
        "Content-Type": "application/json",
        "Ocp-Apim-Subscription-Key": DISBURSEMENT_PRIMARY_KEY,
        "X-Reference-Id": x_reference_id, # This header is crucial for creating the user
    }
    payload = {
        "providerCallbackHost": CALLBACK_HOST
    }

    logger.info(f"Requesting API User creation at URL: {API_USER_URL}")
    logger.info(f"Headers (partial): Ocp-Apim-Subscription-Key: {DISBURSEMENT_PRIMARY_KEY[:8]}..., X-Reference-Id: {x_reference_id}")
    logger.info(f"Payload: {payload}")

    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(API_USER_URL, headers=headers, json=payload)
            response.raise_for_status() # Raise an exception for bad status codes (4xx or 5xx)

            # MoMo API returns 201 Created with no body if successful
            if response.status_code == 201:
                logger.info(f"API User created successfully for X-Reference-Id: {x_reference_id}")
            else:
                logger.error(f"Failed to create API User. Status Code: {response.status_code}, Response: {response.text}")
                return

            # 3. Request API Key for the newly created API User
            api_key_url = API_KEY_URL_TEMPLATE.format(x_reference_id=x_reference_id)
            logger.info(f"Requesting API Key at URL: {api_key_url}")

            api_key_headers = {
                "Ocp-Apim-Subscription-Key": DISBURSEMENT_PRIMARY_KEY,
                "Content-Type": "application/json" # This might not be strictly needed for GET but good practice
            }

            api_key_response = await client.post(api_key_url, headers=api_key_headers)
            api_key_response.raise_for_status()

            api_key_data = api_key_response.json()
            api_key = api_key_data.get("apiKey")

            if api_key:
                logger.info("API Key generated successfully!")
                logger.info(f"--- Your Disbursement Sandbox Credentials ---")
                logger.info(f"X-Reference-Id (User ID): {x_reference_id}")
                logger.info(f"API Key: {api_key}")

                # Optionally, calculate the Basic Auth string
                basic_auth_string = base64.b64encode(f"{x_reference_id}:{api_key}".encode()).decode('utf-8')
                logger.info(f"Basic Auth Header Value: Basic {basic_auth_string}")
                logger.info(f"---------------------------------------------")
                logger.info("Please save these credentials securely.")
            else:
                logger.error(f"API Key not found in response: {api_key_response.text}")

        except httpx.HTTPStatusError as e:
            logger.error(f"HTTP error occurred: {e.response.status_code} - {e.response.text}")
            logger.error(f"Request URL: {e.request.url}")
            logger.error(f"Request Headers: {e.request.headers}")
        except httpx.RequestError as e:
            logger.error(f"An error occurred while requesting {e.request.url!r}: {e}")
        except Exception as e:
            logger.error(f"An unexpected error occurred: {e}")

if __name__ == "__main__":
    import asyncio
    asyncio.run(provision_disbursement_api_user())
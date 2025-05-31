import os
import httpx
import uuid
import base64
import asyncio
from dotenv import load_dotenv
import logging
import json # For pretty printing JSON responses

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s:%(message)s')
logger = logging.getLogger(__name__)

# Load environment variables from .env file
load_dotenv()

# --- Configuration ---
DISBURSEMENT_PRIMARY_KEY = os.getenv("DISBURSEMENT_PRIMARY_KEY")
DISBURSEMENT_USER_ID = os.getenv("DISBURSEMENT_USER_ID") # This is your X-Reference-Id
DISBURSEMENT_API_KEY = os.getenv("DISBURSEMENT_API_KEY")

# Test Disbursement Details
TEST_RECIPIENT_MSISDN = os.getenv("TEST_RECIPIENT_MSISDN", "256772123456") # Default for testing
TEST_AMOUNT = os.getenv("TEST_AMOUNT", "100") # Default for testing, as string

# MoMo API Endpoints (Sandbox)
BASE_URL = "https://sandbox.momodeveloper.mtn.com"
DISBURSEMENT_TOKEN_URL = f"{BASE_URL}/disbursement/token/"
DISBURSEMENT_TRANSFER_URL = f"{BASE_URL}/disbursement/v1_0/transfer"  # Fixed: changed from 'deposit' to 'transfer'
DISBURSEMENT_REQUEST_TO_PAY_STATUS_URL_TEMPLATE = f"{BASE_URL}/disbursement/v1_0/transfer/{{transaction_id}}"  # Fixed: updated for transfer

# Global variable to store access token and its expiry
disbursement_access_token = None
disbursement_token_expires_at = 0 # Unix timestamp

async def get_disbursement_access_token(session: httpx.AsyncClient):
    global disbursement_access_token, disbursement_token_expires_at

    if disbursement_access_token and (disbursement_token_expires_at > asyncio.get_event_loop().time() + 60):
        # Token is still valid for at least 60 more seconds, no need to refresh
        logger.info("Using existing disbursement access token.")
        return disbursement_access_token

    if not all([DISBURSEMENT_USER_ID, DISBURSEMENT_API_KEY, DISBURSEMENT_PRIMARY_KEY]):
        logger.error("Missing one or more disbursement credentials (User ID, API Key, Primary Key) in .env.")
        return None

    auth_string = f"{DISBURSEMENT_USER_ID}:{DISBURSEMENT_API_KEY}"
    encoded_auth_string = base64.b64encode(auth_string.encode()).decode('utf-8')

    headers = {
        "Authorization": f"Basic {encoded_auth_string}",
        "Ocp-Apim-Subscription-Key": DISBURSEMENT_PRIMARY_KEY,
        "Content-Type": "application/json"
    }

    logger.info("----- Access Token Request (disbursement) -----")
    logger.info(f"URL: {DISBURSEMENT_TOKEN_URL}")
    logger.info(f"Headers: Authorization: Basic {encoded_auth_string[:10]}..., Ocp-Apim-Subscription-Key: {DISBURSEMENT_PRIMARY_KEY[:8]}...")

    try:
        response = await session.post(DISBURSEMENT_TOKEN_URL, headers=headers)
        response.raise_for_status() # Raise an exception for HTTP errors (4xx or 5xx)

        logger.info("----- Access Token Response (disbursement) -----")
        logger.info(f"Status Code: {response.status_code}")
        logger.info(f"Response Text: {response.text}")

        response_data = response.json()
        token = response_data.get("access_token")
        expires_in = response_data.get("expires_in") # typically 3600 seconds

        if token and expires_in:
            disbursement_access_token = token
            # Store expiry time (current time + expires_in - a small buffer)
            disbursement_token_expires_at = asyncio.get_event_loop().time() + expires_in - 120 # 2-minute buffer
            logger.info("Disbursement access token retrieved successfully!")
            return token
        else:
            logger.error("Access token or expiry not found in disbursement token response.")
            return None

    except httpx.HTTPStatusError as e:
        logger.error(f"Failed to retrieve disbursement access token. HTTP Error: {e.response.status_code} - {e.response.text}")
    except httpx.RequestError as e:
        logger.error(f"Network error during disbursement token request: {e}")
    except Exception as e:
        logger.error(f"An unexpected error occurred during disbursement token retrieval: {e}")
    return None

async def perform_disbursement(session: httpx.AsyncClient, recipient_msisdn: str, amount: str, currency: str):  # Changed default currency to eur
    token = await get_disbursement_access_token(session)
    if not token:
        logger.error("Cannot perform disbursement without an access token.")
        return None

    # Generate a unique reference for this specific transaction
    # This is different from the X-Reference-Id for API User
    transaction_reference_id = str(uuid.uuid4())

    headers = {
        "Authorization": f"Bearer {token}",
        "X-Reference-Id": transaction_reference_id,
        "X-Target-Environment": "sandbox", # Essential for sandbox API calls
        "Ocp-Apim-Subscription-Key": DISBURSEMENT_PRIMARY_KEY,
        "Content-Type": "application/json"
    }

    # Fixed payload structure for disbursements
    payload = {
        "amount": amount,
        "currency": currency,
        "externalId": transaction_reference_id, # Can be the same as X-Reference-Id or another unique ID
        "payee": {  # Changed from 'payer' to 'payee' - this is the recipient
            "partyIdType": "MSISDN",
            "partyId": recipient_msisdn
        },
        "payerMessage": "Disbursement payment",  # Message to the payer (you/your system)
        "payeeNote": "You have received a payment"  # Note to the payee (recipient)
    }

    logger.info("----- Disbursement Request -----")
    logger.info(f"URL: {DISBURSEMENT_TRANSFER_URL}")
    logger.info(f"Headers (partial): Authorization: Bearer {token[:10]}..., X-Reference-Id: {transaction_reference_id}")
    logger.info(f"Payload: {json.dumps(payload, indent=2)}")

    try:
        response = await session.post(DISBURSEMENT_TRANSFER_URL, headers=headers, json=payload)

        logger.info("----- Disbursement Response -----")
        logger.info(f"Status Code: {response.status_code}")
        logger.info(f"Response Headers: {response.headers}")
        logger.info(f"Response Text: {response.text}") # MoMo often returns empty 202 response for transfer

        if response.status_code == 202:
            logger.info(f"Disbursement request submitted successfully! Transaction ID: {transaction_reference_id}")
            logger.info("Please note: For disbursement, a 202 status means the request was accepted for processing.")
            logger.info("You will need to check the status of the transaction separately if you haven't implemented callbacks.")
            return transaction_reference_id
        else:
            logger.error(f"Failed to submit disbursement request. Status Code: {response.status_code}, Response: {response.text}")
            return None

    except httpx.HTTPStatusError as e:
        logger.error(f"HTTP error during disbursement: {e.response.status_code} - {e.response.text}")
        logger.error(f"Request URL: {e.request.url}")
        logger.error(f"Request Headers: {e.request.headers}")
    except httpx.RequestError as e:
        logger.error(f"Network error during disbursement request: {e}")
    except Exception as e:
        logger.error(f"An unexpected error occurred during disbursement: {e}")
    return None

async def check_disbursement_status(session: httpx.AsyncClient, transaction_id: str):
    """Check the status of a disbursement transaction"""
    token = await get_disbursement_access_token(session)
    if not token:
        logger.error("Cannot check disbursement status without an access token.")
        return None

    status_url = DISBURSEMENT_REQUEST_TO_PAY_STATUS_URL_TEMPLATE.format(transaction_id=transaction_id)
    
    headers = {
        "Authorization": f"Bearer {token}",
        "X-Target-Environment": "sandbox",
        "Ocp-Apim-Subscription-Key": DISBURSEMENT_PRIMARY_KEY,
    }

    logger.info("----- Checking Disbursement Status -----")
    logger.info(f"URL: {status_url}")
    logger.info(f"Transaction ID: {transaction_id}")

    try:
        response = await session.get(status_url, headers=headers)
        
        logger.info(f"Status Check Response Code: {response.status_code}")
        logger.info(f"Status Check Response: {response.text}")
        
        if response.status_code == 200:
            status_data = response.json()
            transaction_status = status_data.get("status")
            logger.info(f"Transaction Status: {transaction_status}")
            return status_data
        else:
            logger.error(f"Failed to check disbursement status. Status Code: {response.status_code}")
            return None
            
    except Exception as e:
        logger.error(f"Error checking disbursement status: {e}")
        return None

async def main():
    async with httpx.AsyncClient() as session:
        currency = os.getenv('MOMO_SANDBOX_CURRENCY')  # Changed default to direct from env
        logger.info(f"Attempting to disburse {TEST_AMOUNT} {currency} to {TEST_RECIPIENT_MSISDN}")
        transaction_id = await perform_disbursement(session, TEST_RECIPIENT_MSISDN, TEST_AMOUNT, currency)

        if transaction_id:
            logger.info(f"Disbursement initiated with Transaction ID: {transaction_id}")
            
            # Wait a bit and then check status
            logger.info("Waiting 5 seconds before checking status...")
            await asyncio.sleep(5)
            
            status = await check_disbursement_status(session, transaction_id)
            if status:
                logger.info("Disbursement status check completed.")
            else:
                logger.info("Could not retrieve disbursement status.")

if __name__ == "__main__":
    asyncio.run(main())
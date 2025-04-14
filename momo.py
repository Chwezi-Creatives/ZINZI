import os
import requests
import base64
import logging
import time
import uuid  # For generating UUIDs
from typing import Dict, Any

# Load MoMo environment variables
X_REFERENCE_ID = os.getenv("X_REFERENCE_ID")  # Unique UUID for reference
API_KEY = os.getenv("MOMO_API_KEY")            # API Key from MoMo
SUBSCRIPTION_KEY = os.getenv("MOMO_SUBSCRIPTION_KEY")  # Subscription Key
momo_base_url = os.getenv("MOMO")              # Base URL for MoMo API
momo_headers = {}
access_token = ""
token_expires_at = 0

# Configure logging
logging.basicConfig(level=logging.INFO)

def get_access_token(x_reference_id: str, api_key: str) -> str:
    """Request a new access token from the MoMo API."""
    url = f"{momo_base_url}/collection/token/"
    auth_header = base64.b64encode(f"{x_reference_id}:{api_key}".encode()).decode()  # Basic Auth

    headers = {
        "Authorization": f"Basic {auth_header}",
        "Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY,
    }

    logging.info("----- Access Token Request -----")
    logging.info(f"URL: {url}")
    logging.info(f"Headers: {headers}")

    response = requests.post(url, headers=headers)

    logging.info("----- Access Token Response -----")
    logging.info(f"Status Code: {response.status_code}")
    logging.info(f"Response Text: {response.text}")

    if response.status_code == 200:
        token_info = response.json()
        logging.info("Access token retrieved successfully!")
        return token_info["access_token"], time.time() + token_info["expires_in"]
    else:
        logging.error("Failed to retrieve access token.")
        response.raise_for_status()

def refresh_access_token() -> None:
    """Refresh the access token if it has expired."""
    global access_token, token_expires_at

    if time.time() >= token_expires_at:
        access_token, token_expires_at = get_access_token(X_REFERENCE_ID, API_KEY)
        momo_headers["Authorization"] = f"Bearer {access_token}"

def configure_momo() -> Dict[str, Any]:
    """Configure MoMo API headers."""
    global momo_headers, access_token, token_expires_at
    access_token, token_expires_at = get_access_token(X_REFERENCE_ID, API_KEY)

    momo_headers = {
        "Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY,
        "Authorization": f"Bearer {access_token}",
    }

    logging.info("MoMo API configured successfully.")
    return {"status": "success", "message": "MoMo API configured successfully."}

def request_momo_payment(amount: float, currency: str, external_id: str, 
                          payer_number: str, payer_message: str, 
                          payee_note: str) -> Dict[str, Any]:
    """Request a payment from a user."""
    try:
        refresh_access_token()  # Ensure we have a valid access token
        
        # Generate a unique reference ID for this transaction
        transaction_ref = str(uuid.uuid4())
        
        # Format the phone number correctly - ensure it has correct country code format
        # MTN MoMo typically requires phone numbers with country code but no + symbol
        # Strip any + sign if present and ensure it's just digits
        formatted_number = payer_number.replace('+', '')
        if not formatted_number.startswith('256') and formatted_number.startswith('46'):
            # If using a Ugandan number for testing, convert from Swedish format
            formatted_number = '256' + formatted_number[2:]

        # Prepare payload
        payload = {
            "amount": str(amount),  # Convert to string without formatting
            "currency": currency,
            "externalId": external_id,
            "payer": {
                "partyIdType": "MSISDN",  # Indicates phone number type
                "partyId": formatted_number,
            },
            "payerMessage": payer_message,
            "payeeNote": payee_note,
        }

        # Log the full payload for the request
        logging.info(f"Payload for payment request: {payload}")

        # Preparing headers for the request - include X-Reference-ID
        headers = {
            **momo_headers,
            "X-Target-Environment": "sandbox",
            "X-Reference-ID": transaction_ref,
            "Content-Type": "application/json"
        }

        # Log headers being sent with the request
        logging.info(f"Headers for payment request: {headers}")

        # Use the correct URL structure for the request-to-pay endpoint
        url = f"{momo_base_url}/collection/v1_0/requesttopay"
        logging.info(f"Request URL: {url}")

        response = requests.post(
            url,
            json=payload,
            headers=headers,
        )

        # Log the response status and headers for debugging
        logging.info(f"Payment request response received: {response.status_code}")
        logging.info(f"Response Headers: {response.headers}")
        logging.info(f"Response Content: {response.text}")

        if response.status_code == 202:  # Accepted
            logging.info(f"Payment request successful. Transaction Reference: {transaction_ref}")
            return {"status": "success", "transaction_ref": transaction_ref}
        else:
            # Enhanced error logging
            error_response = response.json() if response.content else "No content"
            logging.error(f"Payment request failed with status code {response.status_code}: {error_response}")
            return {"status": "failure", "error": error_response, "status_code": response.status_code}
    except Exception as e:
        logging.error(f"Unexpected error during request_momo_payment: {e}")
        return {"status": "failure", "error": f"An unexpected error occurred: {str(e)}"}

def check_momo_payment_status(transaction_ref: str) -> Dict[str, Any]:
    """Check the status of a payment request."""
    try:
        refresh_access_token()  # Ensure the access token is valid
        headers = {
            **momo_headers, 
            "X-Target-Environment": "sandbox",
            "Content-Type": "application/json"
        }

        url = f"{momo_base_url}/collection/v1_0/requesttopay/{transaction_ref}"
        logging.info(f"Status check URL: {url}")
        logging.info(f"Status check headers: {headers}")

        response = requests.get(url, headers=headers)

        logging.info(f"Status check response: {response.status_code}")
        logging.info(f"Status check response content: {response.text}")

        if response.status_code == 200:
            payment_status = response.json()
            logging.info(f"Payment status retrieved successfully: {payment_status}")
            return {"status": "success", "payment_status": payment_status}
        else:
            error_response = response.json() if response.content else "No content"
            logging.error(f"Failed to retrieve payment status: {error_response}")
            return {"status": "failure", "error": error_response, "status_code": response.status_code}
    except Exception as e:
        logging.error(f"Unexpected error during check_momo_payment_status: {e}")
        return {"status": "failure", "error": f"An unexpected error occurred: {str(e)}"}

# Initialize MoMo configuration
configure_momo()

# Test scenario: Request a payment
if __name__ == "__main__":
    logging.info("Starting MoMo payment request test scenario...")

    # Test payment details
    amount = 100.00  # Amount to request
    currency = "EUR"  # Currency code
    external_id = str(uuid.uuid4())  # Generate a unique UUID for externalId
    
    # Use properly formatted phone number according to MTN MoMo requirements
    # For Uganda testing, should be a number starting with 256 (Uganda's country code)
    # Check MTN MoMo documentation for specific testing phone numbers
    payer_number = "256774123456"  # Example Uganda MSISDN (testing number)
    payer_message = "Test payment"
    payee_note = "Payment for services"

    # Request a payment
    payment_response = request_momo_payment(
        amount, currency, external_id, payer_number, payer_message, payee_note
    )

    if payment_response["status"] == "success":
        transaction_ref = payment_response["transaction_ref"]
        logging.info(f"Transaction initiated. Reference ID: {transaction_ref}")

        # Wait a few seconds (simulate delay in processing) before checking payment status
        time.sleep(5)

        # Check payment status
        status_response = check_momo_payment_status(transaction_ref)
        logging.info(f"Payment status response: {status_response}")
    else:
        logging.error(f"Payment request failed: {payment_response}")
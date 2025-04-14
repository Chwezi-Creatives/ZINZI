import os
import requests
import json
import logging
import time
import uuid
import base64
from typing import Dict, Any
from datetime import datetime
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('airtel_money')

# Airtel Money Uganda API Configuration
AIRTEL_CLIENT_ID = os.getenv("AIR_CLIENT_ID")
AIRTEL_CLIENT_SECRET = os.getenv("AIR_CLIENT_SECRET")
AIRTEL_PIN = os.getenv("AIRTEL_PIN")  # PIN for transactions
AIRTEL_COUNTRY = "UG"  # Country code for Uganda
AIRTEL_CURRENCY = "UGX"  # Currency code for Ugandan Shilling

# Base URLs
AIRTEL_BASE_URL = os.getenv("AIR_API_BASE_URL")  # Use UAT for testing
if not AIRTEL_BASE_URL:
    raise ValueError("AIRTEL_BASE_URL environment variable is not set")
AIRTEL_ENVIRONMENT = os.getenv("AIRTEL_ENVIRONMENT")  # sandbox or production

# Storage for access token
access_token = None
token_expiry = 0

def get_access_token() -> str:
    """
    Get an OAuth access token from Airtel Money API
    """
    global access_token, token_expiry
    
    # Check if we have a valid token
    if access_token and token_expiry > time.time():
        logger.info("Using existing access token")
        return access_token
    
    logger.info("Requesting new access token")

    url = f"{AIRTEL_BASE_URL}/auth/oauth2/token"
    
    # Create basic auth from client ID and secret
    auth_string = f"{AIRTEL_CLIENT_ID}:{AIRTEL_CLIENT_SECRET}"
    auth_header = base64.b64encode(auth_string.encode()).decode()
    
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Basic {auth_header}"
    }
    
    payload = {
        "grant_type": "client_credentials"
    }
    
    logger.info(f"Token request URL: {url}")
    logger.info(f"Token request headers: {headers}")
    
    try:
        response = requests.post(url, headers=headers, json=payload)
        response.raise_for_status()
        
        token_data = response.json()
        logger.info("Access token retrieved successfully")
        
        # Store the token and calculate expiry time (subtract 60 seconds for safety)
        access_token = token_data["access_token"]
        token_expiry = time.time() + token_data["expires_in"] - 60
        
        return access_token
    except requests.exceptions.RequestException as e:
        logger.error(f"Error getting access token: {str(e)}")
        if hasattr(e, 'response') and e.response:
            logger.error(f"Response: {e.response.text}")
        raise

def generate_transaction_id() -> str:
    """
    Generate a unique transaction ID
    """
    return str(uuid.uuid4())

def create_payment_request(
    phone_number: str, 
    amount: float, 
    reference: str = None,
    transaction_note: str = "Payment for services"
) -> Dict[str, Any]:
    """
    Create a payment request to collect money from a customer
    
    Args:
        phone_number: Customer's phone number (must include country code)
        amount: Amount to collect
        reference: Optional reference for the transaction
        transaction_note: Note for the transaction
        
    Returns:
        Dict containing the response from the API
    """
    try:
        # Get access token
        token = get_access_token()
        
        # Format phone number (ensure it has country code)
        formatted_phone = phone_number
        if not formatted_phone.startswith('+'):
            formatted_phone = f"+{formatted_phone}"
        
        # If reference is not provided, generate one
        if not reference:
            reference = f"txn-{datetime.now().strftime('%Y%m%d%H%M%S')}"
        
        # Create transaction ID
        transaction_id = generate_transaction_id()
        
        # Prepare request
        url = f"{AIRTEL_BASE_URL}/merchant/v1/payments/"
        
        headers = {
            "Content-Type": "application/json",
            "Accept": "*/*",
            "X-Country": AIRTEL_COUNTRY,
            "X-Currency": AIRTEL_CURRENCY,
            "Authorization": f"Bearer {token}"
        }
        
        payload = {
            "reference": reference,
            "subscriber": {
                "country": AIRTEL_COUNTRY,
                "currency": AIRTEL_CURRENCY,
                "msisdn": formatted_phone
            },
            "transaction": {
                "amount": str(amount),
                "country": AIRTEL_COUNTRY,
                "currency": AIRTEL_CURRENCY,
                "id": transaction_id
            }
        }
        
        logger.info(f"Payment request URL: {url}")
        logger.info(f"Payment request headers: {headers}")
        logger.info(f"Payment request payload: {payload}")
        
        response = requests.post(url, headers=headers, json=payload)
        
        logger.info(f"Payment request response status: {response.status_code}")
        logger.info(f"Payment request response: {response.text}")
        
        if response.status_code in [200, 201, 202]:
            response_data = response.json()
            return {
                "status": "success",
                "transaction_id": transaction_id,
                "airtel_data": response_data
            }
        else:
            error_data = response.json() if response.text else {"error": "No response data"}
            logger.error(f"Payment request failed: {error_data}")
            return {
                "status": "error",
                "error": error_data,
                "status_code": response.status_code
            }
    
    except Exception as e:
        logger.error(f"Error creating payment request: {str(e)}")
        return {
            "status": "error",
            "error": str(e)
        }

def check_payment_status(transaction_id: str) -> Dict[str, Any]:
    """
    Check the status of a payment
    
    Args:
        transaction_id: The transaction ID to check
        
    Returns:
        Dict containing the status of the payment
    """
    try:
        # Get access token
        token = get_access_token()
        
        url = f"{AIRTEL_BASE_URL}/standard/v1/payments/{transaction_id}"
        
        headers = {
            "Content-Type": "application/json",
            "Accept": "*/*",
            "X-Country": AIRTEL_COUNTRY,
            "X-Currency": AIRTEL_CURRENCY,
            "Authorization": f"Bearer {token}"
        }
        
        logger.info(f"Payment status check URL: {url}")
        logger.info(f"Payment status check headers: {headers}")
        
        response = requests.get(url, headers=headers)
        
        logger.info(f"Payment status check response status: {response.status_code}")
        logger.info(f"Payment status check response: {response.text}")
        
        if response.status_code == 200:
            response_data = response.json()
            return {
                "status": "success",
                "transaction_status": response_data.get("status", "UNKNOWN"),
                "airtel_data": response_data
            }
        else:
            error_data = response.json() if response.text else {"error": "No response data"}
            logger.error(f"Payment status check failed: {error_data}")
            return {
                "status": "error",
                "error": error_data,
                "status_code": response.status_code
            }
    
    except Exception as e:
        logger.error(f"Error checking payment status: {str(e)}")
        return {
            "status": "error",
            "error": str(e)
        }

def disburse_funds(
    phone_number: str, 
    amount: float, 
    reference: str = None,
    transaction_note: str = "Payment disbursement"
) -> Dict[str, Any]:
    """
    Disburse funds to a customer (send money)
    
    Args:
        phone_number: Customer's phone number (must include country code)
        amount: Amount to disburse
        reference: Optional reference for the transaction
        transaction_note: Note for the transaction
        
    Returns:
        Dict containing the response from the API
    """
    try:
        # Get access token
        token = get_access_token()
        
        # Format phone number (ensure it has country code)
        formatted_phone = phone_number
        if not formatted_phone.startswith('+'):
            formatted_phone = f"+{formatted_phone}"
        
        # If reference is not provided, generate one
        if not reference:
            reference = f"dis-{datetime.now().strftime('%Y%m%d%H%M%S')}"
        
        # Create transaction ID
        transaction_id = generate_transaction_id()
        
        # Prepare request
        url = f"{AIRTEL_BASE_URL}/standard/v1/disbursements/"
        
        headers = {
            "Content-Type": "application/json",
            "Accept": "*/*",
            "X-Country": AIRTEL_COUNTRY,
            "X-Currency": AIRTEL_CURRENCY,
            "Authorization": f"Bearer {token}"
        }
        
        payload = {
            "payee": {
                "msisdn": formatted_phone
            },
            "reference": reference,
            "pin": AIRTEL_PIN,  # PIN required for disbursements
            "transaction": {
                "amount": str(amount),
                "id": transaction_id,
                "notes": transaction_note
            }
        }
        
        logger.info(f"Disbursement request URL: {url}")
        logger.info(f"Disbursement request headers: {headers}")
        logger.info(f"Disbursement request payload: {payload}")
        
        response = requests.post(url, headers=headers, json=payload)
        
        logger.info(f"Disbursement request response status: {response.status_code}")
        logger.info(f"Disbursement request response: {response.text}")
        
        if response.status_code in [200, 201, 202]:
            response_data = response.json()
            return {
                "status": "success",
                "transaction_id": transaction_id,
                "airtel_data": response_data
            }
        else:
            error_data = response.json() if response.text else {"error": "No response data"}
            logger.error(f"Disbursement request failed: {error_data}")
            return {
                "status": "error",
                "error": error_data,
                "status_code": response.status_code
            }
    
    except Exception as e:
        logger.error(f"Error creating disbursement request: {str(e)}")
        return {
            "status": "error",
            "error": str(e)
        }

def check_account_balance() -> Dict[str, Any]:
    """
    Check the account balance
    
    Returns:
        Dict containing the account balance
    """
    try:
        # Get access token
        token = get_access_token()
        
        url = f"{AIRTEL_BASE_URL}/standard/v1/users/balance"
        
        headers = {
            "Content-Type": "application/json",
            "Accept": "*/*",
            "X-Country": AIRTEL_COUNTRY,
            "X-Currency": AIRTEL_CURRENCY,
            "Authorization": f"Bearer {token}"
        }
        
        logger.info(f"Balance check URL: {url}")
        logger.info(f"Balance check headers: {headers}")
        
        response = requests.get(url, headers=headers)
        
        logger.info(f"Balance check response status: {response.status_code}")
        logger.info(f"Balance check response: {response.text}")
        
        if response.status_code == 200:
            response_data = response.json()
            return {
                "status": "success",
                "balance": response_data.get("data", {}).get("balance", "0"),
                "currency": response_data.get("data", {}).get("currency", AIRTEL_CURRENCY),
                "airtel_data": response_data
            }
        else:
            error_data = response.json() if response.text else {"error": "No response data"}
            logger.error(f"Balance check failed: {error_data}")
            return {
                "status": "error",
                "error": error_data,
                "status_code": response.status_code
            }
    
    except Exception as e:
        logger.error(f"Error checking account balance: {str(e)}")
        return {
            "status": "error",
            "error": str(e)
        }

# Test the implementation
if __name__ == "__main__":
    # Test payment collection
    logger.info("Testing Airtel Money Uganda payment collection")
    
    # Test phone number (use a valid test number for Airtel Uganda)
    test_phone = "256770123456"  # Replace with a valid test number
    test_amount = 1000  # 1000 UGX
    
    # Create payment request
    payment_result = create_payment_request(
        phone_number=test_phone,
        amount=test_amount,
        transaction_note="Test payment"
    )
    
    logger.info(f"Payment request result: {payment_result}")
    
    # If payment request was successful, check status
    if payment_result["status"] == "success":
        transaction_id = payment_result["transaction_id"]
        
        # Wait a few seconds before checking status
        time.sleep(5)
        
        # Check payment status
        status_result = check_payment_status(transaction_id)
        logger.info(f"Payment status result: {status_result}")
        
        # Check account balance
        balance_result = check_account_balance()
        logger.info(f"Account balance: {balance_result}")
    
    # Test disbursement
    logger.info("Testing Airtel Money Uganda disbursement")
    
    # Create disbursement request
    disbursement_result = disburse_funds(
        phone_number=test_phone,
        amount=500,  # 500 UGX
        transaction_note="Test disbursement"
    )
    
    logger.info(f"Disbursement result: {disbursement_result}")
import os
import aiohttp
import asyncio
import base64
import logging
import time
import uuid
from typing import Dict, Any
from dotenv import load_dotenv
load_dotenv()

# Collections API Configuration
COLLECTIONS_USER_ID = os.getenv("MOMO_COLLECTIONS_USER_ID")  # X-Reference-Id for collections
COLLECTIONS_API_KEY = os.getenv("MOMO_COLLECTIONS_API_KEY")  # API Key for collections
COLLECTIONS_SUBSCRIPTION_KEY = os.getenv("MOMO_COLLECTIONS_SUBSCRIPTION_KEY")  # Subscription key for collections
MOMO_SANDBOX_URL = os.getenv("MOMO_SANDBOX_URL", "https://sandbox.momodeveloper.mtn.com")

# Initialize global variables
momo_headers = {}
access_token = ""
token_expires_at = 0

# Configure logging
logging.basicConfig(level=logging.INFO)

async def get_access_token(session: aiohttp.ClientSession, x_reference_id: str, api_key: str) -> tuple[str, float]:
    """Request a new access token from the MoMo API."""
    url = f"{MOMO_SANDBOX_URL}/collection/token/"
    auth_header = base64.b64encode(f"{x_reference_id}:{api_key}".encode()).decode()  # Basic Auth

    headers = {
        "Authorization": f"Basic {auth_header}",
        "Ocp-Apim-Subscription-Key": COLLECTIONS_SUBSCRIPTION_KEY,
    }

    logging.info("----- Access Token Request -----")
    logging.info(f"URL: {url}")
    logging.info(f"Headers: {headers}")

    async with session.post(url, headers=headers) as response:
        response_text = await response.text()
        
        logging.info("----- Access Token Response -----")
        logging.info(f"Status Code: {response.status}")
        logging.info(f"Response Text: {response_text}")

        if response.status == 200:
            token_info = await response.json()
            logging.info("Access token retrieved successfully!")
            return token_info["access_token"], time.time() + token_info["expires_in"]
        else:
            logging.error("Failed to retrieve access token.")
            response.raise_for_status()

async def refresh_access_token(session: aiohttp.ClientSession) -> None:
    """Refresh the access token if it has expired."""
    global access_token, token_expires_at

    if time.time() >= token_expires_at:
        access_token, token_expires_at = await get_access_token(session, COLLECTIONS_USER_ID, COLLECTIONS_API_KEY)
        momo_headers["Authorization"] = f"Bearer {access_token}"

async def configure_momo(session: aiohttp.ClientSession) -> Dict[str, Any]:
    """Configure MoMo API headers."""
    global momo_headers, access_token, token_expires_at
    access_token, token_expires_at = await get_access_token(session, COLLECTIONS_USER_ID, COLLECTIONS_API_KEY)

    momo_headers = {
        "Ocp-Apim-Subscription-Key": COLLECTIONS_SUBSCRIPTION_KEY,
        "Authorization": f"Bearer {access_token}",
    }

    logging.info("MoMo API configured successfully.")
    return {"status": "success", "message": "MoMo API configured successfully."}

async def request_momo_payment(session: aiohttp.ClientSession, amount: float, currency: str, 
                              external_id: str, payer_number: str, payer_message: str, 
                              payee_note: str) -> Dict[str, Any]:
    """Request a payment from a user."""
    try:
        await refresh_access_token(session)  # Ensure we have a valid access token
        
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
        url = f"{MOMO_SANDBOX_URL}/collection/v1_0/requesttopay"
        logging.info(f"Request URL: {url}")

        async with session.post(url, json=payload, headers=headers) as response:
            response_text = await response.text()
            
            # Log the response status and headers for debugging
            logging.info(f"Payment request response received: {response.status}")
            logging.info(f"Response Headers: {dict(response.headers)}")
            logging.info(f"Response Content: {response_text}")

            if response.status == 202:  # Accepted
                logging.info(f"Payment request successful. Transaction Reference: {transaction_ref}")
                return {"status": "success", "transaction_ref": transaction_ref}
            else:
                # Enhanced error logging
                try:
                    error_response = await response.json() if response_text else "No content"
                except:
                    error_response = response_text
                logging.error(f"Payment request failed with status code {response.status}: {error_response}")
                return {"status": "failure", "error": error_response, "status_code": response.status}
    except Exception as e:
        logging.error(f"Unexpected error during request_momo_payment: {e}")
        return {"status": "failure", "error": f"An unexpected error occurred: {str(e)}"}

async def check_momo_payment_status(session: aiohttp.ClientSession, transaction_ref: str) -> Dict[str, Any]:
    """Check the status of a payment request."""
    try:
        await refresh_access_token(session)  # Ensure the access token is valid
        headers = {
            **momo_headers, 
            "X-Target-Environment": "sandbox",
            "Content-Type": "application/json"
        }

        url = f"{MOMO_SANDBOX_URL}/collection/v1_0/requesttopay/{transaction_ref}"
        logging.info(f"Status check URL: {url}")
        logging.info(f"Status check headers: {headers}")

        async with session.get(url, headers=headers) as response:
            response_text = await response.text()
            
            logging.info(f"Status check response: {response.status}")
            logging.info(f"Status check response content: {response_text}")

            if response.status == 200:
                payment_status = await response.json()
                logging.info(f"Payment status retrieved successfully: {payment_status}")
                return {"status": "success", "payment_status": payment_status}
            else:
                try:
                    error_response = await response.json() if response_text else "No content"
                except:
                    error_response = response_text
                logging.error(f"Failed to retrieve payment status: {error_response}")
                return {"status": "failure", "error": error_response, "status_code": response.status}
    except Exception as e:
        logging.error(f"Unexpected error during check_momo_payment_status: {e}")
        return {"status": "failure", "error": f"An unexpected error occurred: {str(e)}"}

async def main():
    """Main function to run the MoMo payment test scenario."""
    logging.info("Starting MoMo payment request test scenario...")
    
    # Create an aiohttp session with proper timeout configuration
    timeout = aiohttp.ClientTimeout(total=30)
    
    async with aiohttp.ClientSession(timeout=timeout) as session:
        # Initialize MoMo configuration
        await configure_momo(session)

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
        payment_response = await request_momo_payment(
            session, amount, currency, external_id, payer_number, payer_message, payee_note
        )

        if payment_response["status"] == "success":
            transaction_ref = payment_response["transaction_ref"]
            logging.info(f"Transaction initiated. Reference ID: {transaction_ref}")

            # Wait a few seconds (simulate delay in processing) before checking payment status
            await asyncio.sleep(5)

            # Check payment status
            status_response = await check_momo_payment_status(session, transaction_ref)
            logging.info(f"Payment status response: {status_response}")
        else:
            logging.error(f"Payment request failed: {payment_response}")

# Example of how to handle multiple concurrent payments
async def process_multiple_payments(payment_requests: list) -> list:
    """Process multiple payment requests concurrently."""
    timeout = aiohttp.ClientTimeout(total=30)
    
    async with aiohttp.ClientSession(timeout=timeout) as session:
        # Configure MoMo once for all requests
        await configure_momo(session)
        
        # Create tasks for all payment requests
        tasks = []
        for req in payment_requests:
            task = request_momo_payment(
                session,
                req["amount"],
                req["currency"],  
                req["external_id"],
                req["payer_number"],
                req["payer_message"],
                req["payee_note"]
            )
            tasks.append(task)
        
        # Execute all payment requests concurrently
        results = await asyncio.gather(*tasks, return_exceptions=True)
        return results

# Example usage for multiple payments
async def example_multiple_payments():
    """Example of processing multiple payments concurrently."""
    payment_requests = [
        {
            "amount": 100.0,
            "currency": "EUR",
            "external_id": str(uuid.uuid4()),
            "payer_number": "256774123456",
            "payer_message": "Payment 1",
            "payee_note": "Service 1"
        },
        {
            "amount": 200.0,
            "currency": "EUR", 
            "external_id": str(uuid.uuid4()),
            "payer_number": "256774123457",
            "payer_message": "Payment 2",
            "payee_note": "Service 2"
        }
    ]
    
    results = await process_multiple_payments(payment_requests)
    for i, result in enumerate(results):
        logging.info(f"Payment {i+1} result: {result}")

# Run the main function
if __name__ == "__main__":
    # Run the single payment test
    #asyncio.run(main())
    
    # Uncomment to test multiple concurrent payments
    asyncio.run(example_multiple_payments())
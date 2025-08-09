import aiohttp
import asyncio
import os
import base64
import logging
import time
import uuid
from typing import Dict, Any

# Load MoMo environment variables
X_REFERENCE_ID = os.getenv("X_REFERENCE_ID")  # Unique UUID for reference
API_KEY = os.getenv("MOMO_API_KEY")            # API Key from MoMo
SUBSCRIPTION_KEY = os.getenv("MOMO_SUBSCRIPTION_KEY")  # Subscription Key
momo_base_url = os.getenv("MOMO")              # Base URL for MoMo API

# Token management for different API types
collection_headers = {}
disbursement_headers = {}
collection_token = ""
disbursement_token = ""
collection_expires_at = 0
disbursement_expires_at = 0

# Configure logging
logging.basicConfig(level=logging.INFO)

async def get_access_token(session: aiohttp.ClientSession, x_reference_id: str, api_key: str, api_type: str = "collection") -> tuple[str, float]:
    """Request a new access token from the MoMo API."""
    url = f"{momo_base_url}/{api_type}/token/"
    auth_header = base64.b64encode(f"{x_reference_id}:{api_key}".encode()).decode()  # Basic Auth

    headers = {
        "Authorization": f"Basic {auth_header}",
        "Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY,
    }

    logging.info(f"----- Access Token Request ({api_type}) -----")
    logging.info(f"URL: {url}")
    logging.info(f"Headers: {headers}")

    async with session.post(url, headers=headers) as response:
        response_text = await response.text()
        
        logging.info(f"----- Access Token Response ({api_type}) -----")
        logging.info(f"Status Code: {response.status}")
        logging.info(f"Response Text: {response_text}")

        if response.status == 200:
            token_info = await response.json()
            logging.info(f"Access token retrieved successfully for {api_type}!")
            return token_info["access_token"], time.time() + token_info["expires_in"]
        else:
            logging.error(f"Failed to retrieve access token for {api_type}.")
            response.raise_for_status()

async def refresh_access_token(session: aiohttp.ClientSession, api_type: str = "collection") -> None:
    """Refresh the access token if it has expired."""
    global collection_token, disbursement_token, collection_expires_at, disbursement_expires_at
    global collection_headers, disbursement_headers

    if api_type == "collection":
        if time.time() >= collection_expires_at:
            collection_token, collection_expires_at = await get_access_token(session, X_REFERENCE_ID, API_KEY, "collection")
            collection_headers["Authorization"] = f"Bearer {collection_token}"
    elif api_type == "disbursement":
        if time.time() >= disbursement_expires_at:
            disbursement_token, disbursement_expires_at = await get_access_token(session, X_REFERENCE_ID, API_KEY, "disbursement")
            disbursement_headers["Authorization"] = f"Bearer {disbursement_token}"

async def configure_momo(session: aiohttp.ClientSession, api_types: list = ["collection"]) -> Dict[str, Any]:
    """Configure MoMo API headers for specified API types."""
    global collection_headers, disbursement_headers
    global collection_token, disbursement_token, collection_expires_at, disbursement_expires_at
    
    configured_apis = []
    
    if "collection" in api_types:
        collection_token, collection_expires_at = await get_access_token(session, X_REFERENCE_ID, API_KEY, "collection")
        collection_headers = {
            "Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY,
            "Authorization": f"Bearer {collection_token}",
        }
        configured_apis.append("collection")
    
    if "disbursement" in api_types:
        disbursement_token, disbursement_expires_at = await get_access_token(session, X_REFERENCE_ID, API_KEY, "disbursement")
        disbursement_headers = {
            "Ocp-Apim-Subscription-Key": SUBSCRIPTION_KEY,
            "Authorization": f"Bearer {disbursement_token}",
        }
        configured_apis.append("disbursement")

    logging.info(f"MoMo API configured successfully for: {', '.join(configured_apis)}.")
    return {"status": "success", "message": f"MoMo API configured successfully for: {', '.join(configured_apis)}."}

async def request_momo_payment(session: aiohttp.ClientSession, amount: float, currency: str, 
                              external_id: str, payer_number: str, payer_message: str, 
                              payee_note: str) -> Dict[str, Any]:
    """Request a payment from a user (Collections API)."""
    try:
        await refresh_access_token(session, "collection")  # Ensure we have a valid access token
        
        # Generate a unique reference ID for this transaction
        transaction_ref = str(uuid.uuid4())
        
        # Format the phone number correctly
        formatted_number = payer_number.replace('+', '')
        if not formatted_number.startswith('256') and formatted_number.startswith('46'):
            formatted_number = '256' + formatted_number[2:]

        # Prepare payload
        payload = {
            "amount": str(amount),
            "currency": currency,
            "externalId": external_id,
            "payer": {
                "partyIdType": "MSISDN",
                "partyId": formatted_number,
            },
            "payerMessage": payer_message,
            "payeeNote": payee_note,
        }

        logging.info(f"Payload for payment request: {payload}")

        # Preparing headers for the request
        headers = {
            **collection_headers,
            "X-Target-Environment": "sandbox",
            "X-Reference-ID": transaction_ref,
            "Content-Type": "application/json"
        }

        logging.info(f"Headers for payment request: {headers}")

        url = f"{momo_base_url}/collection/v1_0/requesttopay"
        logging.info(f"Request URL: {url}")

        async with session.post(url, json=payload, headers=headers) as response:
            response_text = await response.text()
            
            logging.info(f"Payment request response received: {response.status}")
            logging.info(f"Response Headers: {dict(response.headers)}")
            logging.info(f"Response Content: {response_text}")

            if response.status == 202:  # Accepted
                logging.info(f"Payment request successful. Transaction Reference: {transaction_ref}")
                return {"status": "success", "transaction_ref": transaction_ref}
            else:
                try:
                    error_response = await response.json() if response_text else "No content"
                except:
                    error_response = response_text
                logging.error(f"Payment request failed with status code {response.status}: {error_response}")
                return {"status": "failure", "error": error_response, "status_code": response.status}
    except Exception as e:
        logging.error(f"Unexpected error during request_momo_payment: {e}")
        return {"status": "failure", "error": f"An unexpected error occurred: {str(e)}"}

async def send_momo_disbursement(session: aiohttp.ClientSession, amount: float, currency: str,
                                external_id: str, payee_number: str, payer_message: str,
                                payee_note: str) -> Dict[str, Any]:
    """Send money to a user (Disbursements API)."""
    try:
        await refresh_access_token(session, "disbursement")  # Ensure we have a valid access token
        
        # Generate a unique reference ID for this transaction
        transaction_ref = str(uuid.uuid4())
        
        # Format the phone number correctly
        formatted_number = payee_number.replace('+', '')
        if not formatted_number.startswith('256') and formatted_number.startswith('46'):
            formatted_number = '256' + formatted_number[2:]

        # Prepare payload for disbursement
        payload = {
            "amount": str(amount),
            "currency": currency,
            "externalId": external_id,
            "payee": {
                "partyIdType": "MSISDN",
                "partyId": formatted_number,
            },
            "payerMessage": payer_message,
            "payeeNote": payee_note,
        }

        logging.info(f"Payload for disbursement request: {payload}")

        # Preparing headers for the request
        headers = {
            **disbursement_headers,
            "X-Target-Environment": "sandbox",
            "X-Reference-ID": transaction_ref,
            "Content-Type": "application/json"
        }

        logging.info(f"Headers for disbursement request: {headers}")

        url = f"{momo_base_url}/disbursement/v1_0/transfer"
        logging.info(f"Disbursement URL: {url}")

        async with session.post(url, json=payload, headers=headers) as response:
            response_text = await response.text()
            
            logging.info(f"Disbursement request response received: {response.status}")
            logging.info(f"Response Headers: {dict(response.headers)}")
            logging.info(f"Response Content: {response_text}")

            if response.status == 202:  # Accepted
                logging.info(f"Disbursement request successful. Transaction Reference: {transaction_ref}")
                return {"status": "success", "transaction_ref": transaction_ref}
            else:
                try:
                    error_response = await response.json() if response_text else "No content"
                except:
                    error_response = response_text
                logging.error(f"Disbursement request failed with status code {response.status}: {error_response}")
                return {"status": "failure", "error": error_response, "status_code": response.status}
    except Exception as e:
        logging.error(f"Unexpected error during send_momo_disbursement: {e}")
        return {"status": "failure", "error": f"An unexpected error occurred: {str(e)}"}

async def check_momo_payment_status(session: aiohttp.ClientSession, transaction_ref: str, api_type: str = "collection") -> Dict[str, Any]:
    """Check the status of a payment request or disbursement."""
    try:
        await refresh_access_token(session, api_type)  # Ensure the access token is valid
        
        if api_type == "collection":
            headers = {**collection_headers, "X-Target-Environment": "sandbox", "Content-Type": "application/json"}
            url = f"{momo_base_url}/collection/v1_0/requesttopay/{transaction_ref}"
        elif api_type == "disbursement":
            headers = {**disbursement_headers, "X-Target-Environment": "sandbox", "Content-Type": "application/json"}
            url = f"{momo_base_url}/disbursement/v1_0/transfer/{transaction_ref}"
        else:
            return {"status": "failure", "error": "Invalid API type. Use 'collection' or 'disbursement'."}

        logging.info(f"Status check URL: {url}")
        logging.info(f"Status check headers: {headers}")

        async with session.get(url, headers=headers) as response:
            response_text = await response.text()
            
            logging.info(f"Status check response: {response.status}")
            logging.info(f"Status check response content: {response_text}")

            if response.status == 200:
                payment_status = await response.json()
                logging.info(f"{api_type.title()} status retrieved successfully: {payment_status}")
                return {"status": "success", "payment_status": payment_status}
            else:
                try:
                    error_response = await response.json() if response_text else "No content"
                except:
                    error_response = response_text
                logging.error(f"Failed to retrieve {api_type} status: {error_response}")
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
        # Initialize MoMo configuration for both collection and disbursement
        await configure_momo(session, ["collection", "disbursement"])

        # Test payment details
        amount = 100.00  # Amount to request
        currency = "EUR"  # Currency code
        external_id = str(uuid.uuid4())  # Generate a unique UUID for externalId
        
        # Use properly formatted phone number according to MTN MoMo requirements
        payer_number = "256774123456"  # Example Uganda MSISDN (testing number)
        payer_message = "Test payment"
        payee_note = "Payment for services"

        # Test 1: Request a payment (Collection)
        logging.info("=== Testing Collection (Request Payment) ===")
        payment_response = await request_momo_payment(
            session, amount, currency, external_id, payer_number, payer_message, payee_note
        )

        if payment_response["status"] == "success":
            transaction_ref = payment_response["transaction_ref"]
            logging.info(f"Collection initiated. Reference ID: {transaction_ref}")

            # Wait a few seconds before checking payment status
            await asyncio.sleep(5)

            # Check payment status
            status_response = await check_momo_payment_status(session, transaction_ref, "collection")
            logging.info(f"Collection status response: {status_response}")
        else:
            logging.error(f"Collection request failed: {payment_response}")

        # Test 2: Send money (Disbursement)
        logging.info("\n=== Testing Disbursement (Send Money) ===")
        disbursement_external_id = str(uuid.uuid4())
        disbursement_response = await send_momo_disbursement(
            session, amount, currency, disbursement_external_id, payer_number, 
            "Money transfer", "Disbursement to user"
        )

        if disbursement_response["status"] == "success":
            disbursement_ref = disbursement_response["transaction_ref"]
            logging.info(f"Disbursement initiated. Reference ID: {disbursement_ref}")

            # Wait a few seconds before checking disbursement status
            await asyncio.sleep(5)

            # Check disbursement status
            disbursement_status = await check_momo_payment_status(session, disbursement_ref, "disbursement")
            logging.info(f"Disbursement status response: {disbursement_status}")
        else:
            logging.error(f"Disbursement request failed: {disbursement_response}")

# Example of how to handle multiple concurrent payments and disbursements
async def process_multiple_operations(operations: list) -> list:
    """Process multiple operations (payments/disbursements) concurrently."""
    timeout = aiohttp.ClientTimeout(total=30)
    
    async with aiohttp.ClientSession(timeout=timeout) as session:
        # Configure MoMo for both APIs
        await configure_momo(session, ["collection", "disbursement"])
        
        # Create tasks for all operations
        tasks = []
        for op in operations:
            if op["type"] == "collection":
                task = request_momo_payment(
                    session, op["amount"], op["currency"], op["external_id"],
                    op["payer_number"], op["payer_message"], op["payee_note"]
                )
            elif op["type"] == "disbursement":
                task = send_momo_disbursement(
                    session, op["amount"], op["currency"], op["external_id"],
                    op["payee_number"], op["payer_message"], op["payee_note"]
                )
            tasks.append(task)
        
        # Execute all operations concurrently
        results = await asyncio.gather(*tasks, return_exceptions=True)
        return results

# Example usage for mixed operations
async def example_mixed_operations():
    """Example of processing both collections and disbursements concurrently."""
    operations = [
        {
            "type": "collection",
            "amount": 100.0,
            "currency": "EUR",
            "external_id": str(uuid.uuid4()),
            "payer_number": "256774123456",
            "payer_message": "Payment request 1",
            "payee_note": "Service 1"
        },
        {
            "type": "disbursement",
            "amount": 50.0,
            "currency": "EUR", 
            "external_id": str(uuid.uuid4()),
            "payee_number": "256774123457", 
            "payer_message": "Money transfer 1",
            "payee_note": "Disbursement 1"
        },
        {
            "type": "collection",
            "amount": 200.0,
            "currency": "EUR",
            "external_id": str(uuid.uuid4()),
            "payer_number": "256774123458",
            "payer_message": "Payment request 2", 
            "payee_note": "Service 2"
        }
    ]
    
    results = await process_multiple_operations(operations)
    for i, result in enumerate(results):
        op_type = operations[i]["type"]
        logging.info(f"{op_type.title()} {i+1} result: {result}")

# Run the main function
if __name__ == "__main__":
    # Run the single payment test
    asyncio.run(main())
    
    # Uncomment to test multiple concurrent payments
    # asyncio.run(example_multiple_payments())
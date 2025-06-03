import os
import logging
import base64
from typing import Dict, Any, Optional
import aiohttp
import asyncio
from datetime import datetime
import uuid # For generating UUIDs for X-Reference-Id
from dotenv import load_dotenv

# Configure logging (call basicConfig once, ideally at app startup)
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')

class MomoService:
    """
    Service class for handling MoMo payment and disbursement operations.
    This class provides an interface to interact with the MoMo API for both
    collections (payments) and disbursements (payouts).
    """

    def __init__(self):
        load_dotenv()
        self.logger = logging.getLogger(__name__)

        # Common configuration
        self.momo_base_url = os.getenv("MOMO_SANDBOX_URL", "https://sandbox.momodeveloper.mtn.com")
        self.default_currency = os.getenv("MOMO_SANDBOX_CURRENCY", "EUR")
        self.callback_url = os.getenv("MOMO_COLLECTIONS_CALLBACK_URL")
        # Default to sandbox if target environment is not explicitly set
        self.target_environment = os.getenv("MOMO_TARGET_ENVIRONMENT", "sandbox")
        
        if not self.callback_url:
            self.logger.warning("MOMO_COLLECTIONS_CALLBACK_URL not set in environment variables. Callbacks will not work.")

        # Collections (Payments) configuration using new env var names
        self.collection_user_id = os.getenv("MOMO_COLLECTIONS_USER_ID")
        self.collection_api_key = os.getenv("MOMO_COLLECTIONS_API_KEY")
        self.collection_subscription_key = os.getenv("MOMO_COLLECTIONS_SUBSCRIPTION_KEY")

        # Disbursements configuration using new env var names
        self.disbursement_user_id = os.getenv("MOMO_DISBURSEMENTS_USER_ID")
        self.disbursement_api_key = os.getenv("MOMO_DISBURSEMENTS_API_KEY")
        self.disbursement_subscription_key = os.getenv("MOMO_DISBURSEMENTS_SUBSCRIPTION_KEY")

        # Initialize token caches
        self.collection_access_token: Optional[str] = None
        self.collection_token_expires_at: float = 0
        self.disbursement_access_token: Optional[str] = None
        self.disbursement_token_expires_at: float = 0
        
        self.logger.info("MomoService initialized.")
        self.logger.debug(f"MOMO Base URL: {self.momo_base_url}")
        self.logger.debug(f"Default Currency: {self.default_currency}")
        self.logger.debug(f"Target Environment: {self.target_environment}")
        self.logger.debug(f"Collection User ID Loaded: {'Yes' if self.collection_user_id else 'NO - MISSING!'}")
        self.logger.debug(f"Collection API Key Loaded: {'Yes' if self.collection_api_key else 'NO - MISSING!'}")
        self.logger.debug(f"Collection Sub Key Loaded: {'Yes' if self.collection_subscription_key else 'NO - MISSING!'}")
        self.logger.debug(f"Disbursement User ID Loaded: {'Yes' if self.disbursement_user_id else 'NO - MISSING!'}")
        self.logger.debug(f"Disbursement API Key Loaded: {'Yes' if self.disbursement_api_key else 'NO - MISSING!'}")
        self.logger.debug(f"Disbursement Sub Key Loaded: {'Yes' if self.disbursement_subscription_key else 'NO - MISSING!'}")


    async def _get_collection_token(self, session: aiohttp.ClientSession) -> str:
        """Get access token for collections API."""
        if self.collection_access_token and datetime.now().timestamp() < self.collection_token_expires_at - 60:
            self.logger.info("Using cached collection access token.")
            return self.collection_access_token

        if not all([self.collection_user_id, self.collection_api_key, self.collection_subscription_key]):
            self.logger.error("Collection credentials (MOMO_COLLECTIONS_USER_ID, MOMO_COLLECTIONS_API_KEY, or MOMO_COLLECTIONS_SUBSCRIPTION_KEY) are not configured in .env.")
            raise ValueError("Collection credentials not configured.")

        url = f"{self.momo_base_url}/collection/token/"
        # For collection token, the API User ID (X_REFERENCE_ID) and API Key (MOMO_API_KEY) are used for Basic Auth.
        auth_string = f"{self.collection_user_id}:{self.collection_api_key}"
        auth_header_val = f"Basic {base64.b64encode(auth_string.encode()).decode()}"

        headers = {
            "Authorization": auth_header_val,
            "Ocp-Apim-Subscription-Key": self.collection_subscription_key,
        }
        
        self.logger.info(f"Requesting collection token from {url}")
        try:
            async with session.post(url, headers=headers) as response:
                if 'application/json' in response.headers.get('Content-Type', ''):
                    response_data = await response.json()
                else:
                    response_text = await response.text()
                    self.logger.error(f"Error getting MoMo collection token: Non-JSON response. Status: {response.status}, Body: {response_text}")
                    raise Exception(f"Failed to get collection token: Server returned non-JSON response. Status: {response.status}")

                if response.status == 200:
                    self.collection_access_token = response_data["access_token"]
                    self.collection_token_expires_at = datetime.now().timestamp() + response_data["expires_in"]
                    self.logger.info("Successfully obtained new collection access token.")
                    return self.collection_access_token
                else:
                    self.logger.error(f"Error getting MoMo collection token: {response.status} - {response_data}")
                    raise Exception(f"Failed to get collection token: {response_data.get('message', str(response_data))}")
        except aiohttp.ClientError as e:
            self.logger.error(f"HTTP Error getting MoMo collection token: {str(e)}", exc_info=True)
            raise
        except Exception as e:
            self.logger.error(f"Unexpected error getting MoMo collection token: {str(e)}", exc_info=True)
            raise

    async def _get_disbursement_token(self, session: aiohttp.ClientSession) -> str:
        """Get access token for disbursements API."""
        if self.disbursement_access_token and datetime.now().timestamp() < self.disbursement_token_expires_at - 60:
            self.logger.info("Using cached disbursement access token.")
            return self.disbursement_access_token

        if not all([self.disbursement_user_id, self.disbursement_api_key, self.disbursement_subscription_key]):
            self.logger.error("Disbursement credentials (DISBURSEMENT_USER_ID, DISBURSEMENT_API_KEY, or DISBURSEMENT_PRIMARY_KEY) are not configured in .env.")
            raise ValueError("Disbursement credentials not configured.")

        url = f"{self.momo_base_url}/disbursement/token/"
        # For disbursement token, the API User ID (DISBURSEMENT_USER_ID) and API Key (DISBURSEMENT_API_KEY) are used for Basic Auth.
        auth_string = f"{self.disbursement_user_id}:{self.disbursement_api_key}"
        auth_header_val = f"Basic {base64.b64encode(auth_string.encode()).decode()}"

        headers = {
            "Authorization": auth_header_val,
            "Ocp-Apim-Subscription-Key": self.disbursement_subscription_key, # This is DISBURSEMENT_PRIMARY_KEY from .env
        }

        self.logger.info(f"Requesting disbursement token from {url}")
        try:
            async with session.post(url, headers=headers) as response:
                if 'application/json' in response.headers.get('Content-Type', ''):
                    response_data = await response.json()
                else:
                    response_text = await response.text()
                    self.logger.error(f"Error getting MoMo disbursement token: Non-JSON response. Status: {response.status}, Body: {response_text}")
                    raise Exception(f"Failed to get disbursement token: Server returned non-JSON response. Status: {response.status}")

                if response.status == 200:
                    self.disbursement_access_token = response_data["access_token"]
                    self.disbursement_token_expires_at = datetime.now().timestamp() + response_data["expires_in"]
                    self.logger.info("Successfully obtained new disbursement access token.")
                    return self.disbursement_access_token
                else:
                    self.logger.error(f"Error getting MoMo disbursement token: {response.status} - {response_data}")
                    raise Exception(f"Failed to get disbursement token: {response_data.get('message', str(response_data))}")
        except aiohttp.ClientError as e:
            self.logger.error(f"HTTP Error getting MoMo disbursement token: {str(e)}", exc_info=True)
            raise
        except Exception as e:
            self.logger.error(f"Unexpected error getting MoMo disbursement token: {str(e)}", exc_info=True)
            raise

    def _format_msisdn(self, phone_number: str, country_code: str = "256") -> str:
        """Helper to format MSISDNs to the required international format without '+'."""
        if not phone_number:
            return ""
        
        cleaned_number = phone_number.strip()
        if cleaned_number.startswith('+'):
            cleaned_number = cleaned_number[1:]
        
        cleaned_number = ''.join(filter(str.isdigit, cleaned_number))

        if cleaned_number.startswith(country_code) and len(cleaned_number) == (len(country_code) + 9):
            return cleaned_number
        elif cleaned_number.startswith('0') and len(cleaned_number) == 10:
             return country_code + cleaned_number[1:]
        elif len(cleaned_number) == 9 and not cleaned_number.startswith(country_code):
             return country_code + cleaned_number
        
        self.logger.warning(f"Phone number {phone_number} (cleaned: {cleaned_number}) might not be in standard {country_code} format. Using as is if it starts with country code, otherwise attempting prefix.")
        if cleaned_number.startswith(country_code):
            return cleaned_number
        if not cleaned_number.startswith(country_code) and len(cleaned_number) > 0:
             self.logger.warning(f"Attempting to prefix {country_code} to {cleaned_number}")
             return country_code + cleaned_number
        return cleaned_number

    async def request_payment(self, amount: float, payer_number: str,
                              currency: Optional[str] = None, external_id: Optional[str] = None,
                              payer_message: Optional[str] = None, payee_note: Optional[str] = None) -> Dict[str, Any]:
        if not payer_number:
            raise ValueError("Payer phone number (payer_number) is required.")

        request_currency = currency if currency is not None else self.default_currency
        client_external_id = external_id if external_id is not None else f"ZINZI_PAY_{int(datetime.now().timestamp())}"
        # IMPORTANT: For MoMo API, X-Reference-Id for requesttopay must be a UUID v4.
        # The X_REFERENCE_ID from .env is the API User ID, not the per-transaction reference.
        transaction_uuid = str(uuid.uuid4())

        formatted_payer_number = self._format_msisdn(payer_number)
        if not formatted_payer_number or not formatted_payer_number.startswith("256"):
             raise ValueError(f"Invalid or improperly formatted payer phone number for UG: {payer_number} -> {formatted_payer_number}")

        default_payer_message = f"Payment of {amount} {request_currency} to ZINZI"
        request_payer_message = (payer_message if payer_message is not None else default_payer_message)[:160]
        
        default_payee_note = "Thank you for your payment"
        request_payee_note = (payee_note if payee_note is not None else default_payee_note)[:160]

        payload = {
            "amount": str(float(amount)),
            "currency": request_currency,
            "externalId": client_external_id,
            "payer": {
                "partyIdType": "MSISDN",
                "partyId": formatted_payer_number
            },
            "payerMessage": request_payer_message,
            "payeeNote": request_payee_note
        }
        
        # Add callback URL if configured
        if self.callback_url:
            payload["callbackUrl"] = self.callback_url
            self.logger.info(f"Using callback URL: {self.callback_url}")
        else:
            self.logger.warning("No callback URL configured. Payment status updates won't be received automatically.")

        url = f"{self.momo_base_url}/collection/v1_0/requesttopay"
        timeout = aiohttp.ClientTimeout(total=60)

        async with aiohttp.ClientSession(timeout=timeout) as session:
            try:
                access_token = await self._get_collection_token(session)
                headers = {
                    "Authorization": f"Bearer {access_token}",
                    "X-Reference-Id": transaction_uuid, # Per-transaction UUID
                    "X-Target-Environment": self.target_environment,
                    "Content-Type": "application/json",
                    "Ocp-Apim-Subscription-Key": self.collection_subscription_key # From MOMO_SUBSCRIPTION_KEY
                }

                self.logger.info(f"Requesting payment to {url} with X-Reference-Id: {transaction_uuid}")
                self.logger.debug(f"Payment Request Payload: {payload}")
                self.logger.debug(f"Payment Request Headers: {headers}")

                async with session.post(url, json=payload, headers=headers) as response:
                    response_text = await response.text()
                    self.logger.info(f"Payment request response status: {response.status}")
                    self.logger.debug(f"Payment request response headers: {dict(response.headers)}")
                    self.logger.debug(f"Payment request response content: {response_text}")

                    if response.status == 202:
                        self.logger.info(f"Payment request successful. API Transaction ID: {transaction_uuid}, Client External ID: {client_external_id}")
                        return {
                            "status": "pending",
                            "message": "Payment request initiated successfully. Await payer authorization.",
                            "transaction_id": transaction_uuid,
                            "external_id": client_external_id,
                            "status_check_url": f"/api/v1/momo/payment-status/{transaction_uuid}" 
                        }
                    else:
                        error_msg = f"HTTP {response.status}"
                        try:
                            if 'application/json' in response.headers.get('Content-Type', ''):
                                error_data = await response.json()
                                error_msg = error_data.get('message', str(error_data))
                            else:
                                error_msg = f"HTTP {response.status}: {response_text}"
                        except Exception as parse_exc:
                            self.logger.error(f"Could not parse error response as JSON: {parse_exc}")
                            error_msg = f"HTTP {response.status}: {response_text}"
                        self.logger.error(f"Payment request failed: {error_msg}")
                        raise Exception(f"Payment request failed: {error_msg}")
            except aiohttp.ClientError as e:
                self.logger.error(f"HTTP error during payment request: {str(e)}", exc_info=True)
                raise Exception(f"Payment request failed due to network/HTTP error: {str(e)}")
            except Exception as e:
                self.logger.error(f"Error in MoMo payment request: {str(e)}", exc_info=True)
                raise Exception(f"An unexpected error occurred during payment request: {str(e)}")

    async def disburse_funds(self, amount: float, payee_id: str,
                             currency: Optional[str] = None, external_id: Optional[str] = None,
                             payee_id_type: str = "MSISDN", 
                             payer_message: Optional[str] = None, payee_note: Optional[str] = None) -> Dict[str, Any]:
        if not payee_id:
            raise ValueError("Payee ID (payee_id) is required.")

        request_currency = currency if currency is not None else self.default_currency
        client_external_id = external_id if external_id is not None else f"ZINZI_DISB_{int(datetime.now().timestamp())}"
        # IMPORTANT: For MoMo API, X-Reference-Id for transfer must be a UUID v4.
        # The DISBURSEMENT_USER_ID from .env is the API User ID, not the per-transaction reference.
        transaction_uuid = str(uuid.uuid4())

        formatted_payee_id = payee_id
        if payee_id_type == "MSISDN":
            formatted_payee_id = self._format_msisdn(payee_id)
            if not formatted_payee_id or not formatted_payee_id.startswith("256"):
                raise ValueError(f"Invalid or improperly formatted payee phone number for UG: {payee_id} -> {formatted_payee_id}")
        
        default_payer_message = f"Payment from ZINZI"
        request_payer_message = (payer_message if payer_message is not None else default_payer_message)[:160]

        default_payee_note = f"You have received {amount} {request_currency}"
        request_payee_note = (payee_note if payee_note is not None else default_payee_note)[:160]

        payload = {
            "amount": str(float(amount)),
            "currency": request_currency,
            "externalId": client_external_id,
            "payee": {
                "partyIdType": payee_id_type,
                "partyId": formatted_payee_id
            },
            "payerMessage": request_payer_message,
            "payeeNote": request_payee_note
        }
        
        # Add callback URL if configured
        if self.callback_url:
            payload["callbackUrl"] = self.callback_url
            self.logger.info(f"Using callback URL: {self.callback_url}")
        else:
            self.logger.warning("No callback URL configured. Disbursement status updates won't be received automatically.")

        url = f"{self.momo_base_url}/disbursement/v1_0/transfer"
        timeout = aiohttp.ClientTimeout(total=60)

        async with aiohttp.ClientSession(timeout=timeout) as session:
            try:
                access_token = await self._get_disbursement_token(session)
                headers = {
                    "Authorization": f"Bearer {access_token}",
                    "X-Reference-Id": transaction_uuid, # Per-transaction UUID
                    "X-Target-Environment": self.target_environment,
                    "Content-Type": "application/json",
                    "Ocp-Apim-Subscription-Key": self.disbursement_subscription_key # From DISBURSEMENT_PRIMARY_KEY
                }

                self.logger.info(f"Requesting disbursement to {url} with X-Reference-Id: {transaction_uuid}")
                self.logger.debug(f"Disbursement Request Payload: {payload}")
                self.logger.debug(f"Disbursement Request Headers: {headers}")
                
                async with session.post(url, json=payload, headers=headers) as response:
                    response_text = await response.text()
                    self.logger.info(f"Disbursement request response status: {response.status}")
                    self.logger.debug(f"Disbursement request response headers: {dict(response.headers)}")
                    self.logger.debug(f"Disbursement request response content: {response_text}")

                    if response.status == 202:
                        self.logger.info(f"Disbursement request successful. API Transaction ID: {transaction_uuid}, Client External ID: {client_external_id}")
                        return {
                            "status": "pending",
                            "message": "Disbursement request initiated successfully.",
                            "transaction_id": transaction_uuid,
                            "external_id": client_external_id,
                            "status_check_url": f"/api/v1/momo/disbursement-status/{transaction_uuid}"
                        }
                    else:
                        error_msg = f"HTTP {response.status}"
                        try:
                            if 'application/json' in response.headers.get('Content-Type', ''):
                                error_data = await response.json()
                                error_msg = error_data.get('message', str(error_data))
                            else:
                                error_msg = f"HTTP {response.status}: {response_text}"
                        except Exception as parse_exc:
                            self.logger.error(f"Could not parse error response as JSON: {parse_exc}")
                            error_msg = f"HTTP {response.status}: {response_text}"
                        self.logger.error(f"Disbursement request failed: {error_msg}")
                        raise Exception(f"Disbursement request failed: {error_msg}")
            except aiohttp.ClientError as e:
                self.logger.error(f"HTTP error during disbursement request: {str(e)}", exc_info=True)
                raise Exception(f"Disbursement request failed due to network/HTTP error: {str(e)}")
            except Exception as e:
                self.logger.error(f"Error in MoMo disbursement request: {str(e)}", exc_info=True)
                raise Exception(f"An unexpected error occurred during disbursement request: {str(e)}")

    async def check_payment_status(self, transaction_uuid: str) -> Dict[str, Any]:
        if not transaction_uuid:
            raise ValueError("MoMo API Transaction ID (UUID) is required to check payment status.")

        url = f"{self.momo_base_url}/collection/v1_0/requesttopay/{transaction_uuid}"
        timeout = aiohttp.ClientTimeout(total=30)

        async with aiohttp.ClientSession(timeout=timeout) as session:
            try:
                access_token = await self._get_collection_token(session)
                headers = {
                    "Authorization": f"Bearer {access_token}",
                    "X-Target-Environment": self.target_environment,
                    "Ocp-Apim-Subscription-Key": self.collection_subscription_key, # From MOMO_SUBSCRIPTION_KEY
                }
                
                self.logger.info(f"Checking payment status for {transaction_uuid} at {url}")
                self.logger.debug(f"Check Payment Status Headers: {headers}")

                async with session.get(url, headers=headers) as response:
                    response_text = await response.text()
                    self.logger.info(f"Check payment status response: {response.status}")
                    self.logger.debug(f"Check payment status response content: {response_text}")

                    if response.status == 200:
                        if 'application/json' in response.headers.get('Content-Type', ''):
                            status_data = await response.json()
                            self.logger.info(f"Payment status for {transaction_uuid}: {status_data.get('status')}")
                            return status_data
                        else:
                            self.logger.error(f"Payment status check for {transaction_uuid} returned non-JSON. Body: {response_text}")
                            raise Exception(f"Payment status check returned non-JSON response. Status: {response.status}")
                    else:
                        error_msg = f"HTTP {response.status}"
                        try:
                            if 'application/json' in response.headers.get('Content-Type', ''):
                                error_data = await response.json()
                                error_msg = error_data.get('message', str(error_data))
                            else:
                                 error_msg = f"HTTP {response.status}: {response_text}"
                        except Exception as parse_exc:
                            self.logger.error(f"Could not parse error response as JSON: {parse_exc}")
                            error_msg = f"HTTP {response.status}: {response_text}"
                        self.logger.error(f"Failed to get payment status for {transaction_uuid}: {error_msg}")
                        raise Exception(f"Failed to get payment status: {error_msg}")
            except aiohttp.ClientError as e:
                self.logger.error(f"HTTP error checking payment status: {str(e)}", exc_info=True)
                raise Exception(f"Network/HTTP error checking payment status: {str(e)}")
            except Exception as e:
                self.logger.error(f"Error checking payment status: {str(e)}", exc_info=True)
                raise Exception(f"An unexpected error occurred while checking payment status: {str(e)}")

    async def check_disbursement_status(self, transaction_uuid: str) -> Dict[str, Any]:
        if not transaction_uuid:
            raise ValueError("MoMo API Transaction ID (UUID) is required to check disbursement status.")

        url = f"{self.momo_base_url}/disbursement/v1_0/transfer/{transaction_uuid}"
        timeout = aiohttp.ClientTimeout(total=30)

        async with aiohttp.ClientSession(timeout=timeout) as session:
            try:
                access_token = await self._get_disbursement_token(session)
                headers = {
                    "Authorization": f"Bearer {access_token}",
                    "X-Target-Environment": self.target_environment,
                    "Ocp-Apim-Subscription-Key": self.disbursement_subscription_key, # From DISBURSEMENT_PRIMARY_KEY
                }

                self.logger.info(f"Checking disbursement status for {transaction_uuid} at {url}")
                self.logger.debug(f"Check Disbursement Status Headers: {headers}")

                async with session.get(url, headers=headers) as response:
                    response_text = await response.text()
                    self.logger.info(f"Check disbursement status response: {response.status}")
                    self.logger.debug(f"Check disbursement status response content: {response_text}")

                    if response.status == 200:
                        if 'application/json' in response.headers.get('Content-Type', ''):
                            status_data = await response.json()
                            self.logger.info(f"Disbursement status for {transaction_uuid}: {status_data.get('status')}")
                            return status_data
                        else:
                            self.logger.error(f"Disbursement status check for {transaction_uuid} returned non-JSON. Body: {response_text}")
                            raise Exception(f"Disbursement status check returned non-JSON response. Status: {response.status}")
                    else:
                        error_msg = f"HTTP {response.status}"
                        try:
                            if 'application/json' in response.headers.get('Content-Type', ''):
                                error_data = await response.json()
                                error_msg = error_data.get('message', str(error_data))
                            else:
                                error_msg = f"HTTP {response.status}: {response_text}"
                        except Exception as parse_exc:
                            self.logger.error(f"Could not parse error response as JSON: {parse_exc}")
                            error_msg = f"HTTP {response.status}: {response_text}"
                        self.logger.error(f"Failed to get disbursement status for {transaction_uuid}: {error_msg}")
                        raise Exception(f"Failed to get disbursement status: {error_msg}")
            except aiohttp.ClientError as e:
                self.logger.error(f"HTTP error checking disbursement status: {str(e)}", exc_info=True)
                raise Exception(f"Network/HTTP error checking disbursement status: {str(e)}")
            except Exception as e:
                self.logger.error(f"Error checking disbursement status: {str(e)}", exc_info=True)
                raise Exception(f"An unexpected error occurred while checking disbursement status: {str(e)}")

# --- Example Usage for Direct Testing ---
async def main_test():
    print("--- MoMo Service Direct Test ---")
    # --- IMPORTANT ---
    # Create a .env file in the same directory as this script (or your project root)
    # with the following variables (matching your original script's names)
    # correctly set from your MoMo Developer Portal:
    #
    # MOMO=<your_momo_base_url_e.g._https://sandbox.momodeveloper.mtn.com>
    # MOMO_CURRENCY=EUR  (Or your specific currency)
    # MOMO_TARGET_ENVIRONMENT=sandbox (Optional, defaults to sandbox if not set)
    #
    # # Collection Product Credentials
    # X_REFERENCE_ID=<your_collection_api_user_id_uuid>
    # MOMO_API_KEY=<your_collection_api_key>
    # MOMO_SUBSCRIPTION_KEY=<your_collection_primary_subscription_key>
    #
    # # Disbursement Product Credentials
    # DISBURSEMENT_USER_ID=<your_disbursement_api_user_id_uuid>
    # DISBURSEMENT_API_KEY=<your_disbursement_api_key>
    # DISBURSEMENT_PRIMARY_KEY=<your_disbursement_subscription_key>
    # --- END IMPORTANT ---

    service = MomoService()
    
    print("\n--- Testing Request Payment (Collection) ---")
    test_payer_msisdn = "256772123456" # <--- !!! REPLACE WITH YOUR SANDBOX TEST PAYER MSISDN !!!
    test_amount_collection = 50.0

    if not service.collection_user_id:
        print("'X_REFERENCE_ID' for collections is missing in .env. Skipping Collection test.")
    else:
        try:
            payment_res = await service.request_payment(
                amount=test_amount_collection,
                payer_number=test_payer_msisdn,
                external_id=f"testcol_{int(datetime.now().timestamp())}",
                payer_message=f"Test Collect {test_amount_collection} {service.default_currency}",
                payee_note="Zinzi Test Collection"
            )
            print(f"Payment Request Response: {payment_res}")

            if payment_res and payment_res.get("status") == "pending":
                payment_tx_id = payment_res.get("transaction_id")
                print(f"\n>>> Payer ({test_payer_msisdn}) needs to APPROVE payment via USSD.")
                print(f"--- Waiting 30s then Checking Payment Status for Transaction ID: {payment_tx_id} ---")
                await asyncio.sleep(30)
                status_res = await service.check_payment_status(payment_tx_id)
                print(f"Payment Status Response: {status_res}")
        except Exception as e:
            print(f"Error during Collection test: {e}")

    print("\n--- Testing Disburse Funds (Disbursement) ---")
    test_payee_msisdn = "256772123456" # <--- !!! REPLACE WITH YOUR SANDBOX TEST PAYEE MSISDN !!!
    test_amount_disbursement = 20.0

    if not service.disbursement_user_id:
        print("'DISBURSEMENT_USER_ID' is missing in .env. Skipping Disbursement test.")
    else:
        try:
            disburse_res = await service.disburse_funds(
                amount=test_amount_disbursement,
                payee_id=test_payee_msisdn,
                external_id=f"testdisb_{int(datetime.now().timestamp())}",
                payer_message=f"Zinzi Test Disbursement Payer Msg",
                payee_note=f"You received {test_amount_disbursement} {service.default_currency}"
            )
            print(f"Disbursement Request Response: {disburse_res}")

            if disburse_res and disburse_res.get("status") == "pending":
                disburse_tx_id = disburse_res.get("transaction_id")
                print(f"\n--- Waiting 15s then Checking Disbursement Status for Transaction ID: {disburse_tx_id} ---")
                await asyncio.sleep(15) 
                dis_status_res = await service.check_disbursement_status(disburse_tx_id)
                print(f"Disbursement Status Response: {dis_status_res}")
        except Exception as e:
            print(f"Error during Disbursement test: {e}")

if __name__ == "__main__":
    # asyncio.run(main_test())
    pass
import requests
import json
import uuid
import time
import os
from datetime import datetime, timedelta

# --- Configuration (Load from environment variables or secure config) ---
# **NEVER HARDCODE IN PRODUCTION**
AIRTEL_API_BASE_URL_SANDBOX = os.environ.get("AIR_API_BASE_URL", "")# Example Sandbox URL - CHECK OFFICIAL DOCS
AIRTEL_API_BASE_URL_PRODUCTION = os.environ.get("AIR_API_BASE_URL", "") # Example Production URL - CHECK OFFICIAL DOCS

# Use Sandbox or Production?
IS_PRODUCTION = False # Set to True for production
API_BASE_URL = AIRTEL_API_BASE_URL_PRODUCTION if IS_PRODUCTION else AIRTEL_API_BASE_URL_SANDBOX

# --- Get Credentials Securely (Replace with your method) ---
CLIENT_ID = os.environ.get("AIR_CLIENT_ID", "YOUR_CLIENT_ID_HERE") #donot change key name 
CLIENT_SECRET = os.environ.get("AIR_CLIENT_SECRET", "YOUR_CLIENT_SECRET_HERE") #donot change key name 
# --- For Disbursements (PIN needs encryption based on Airtel Docs) ---
# ENCRYPTED_PIN = os.environ.get("AIRTEL_ENCRYPTED_PIN", "YOUR_ENCRYPTED_PIN_HERE") # Placeholder

# --- Constants ---
COUNTRY = "UG" # Uganda Country Code
CURRENCY = "UGX" # Uganda Shillings Currency Code

# --- Global variable to cache token (simple cache) ---
# In a real app, use a more robust cache (Redis, Memcached) or manage state better
access_token_cache = {
    "token": None,
    "expires_at": datetime.now()
}

# === 1. Authentication: Get Access Token ===
def get_access_token():
    """
    Fetches a new access token from Airtel API using Client Credentials Grant.
    Includes simple caching.
    """
    global access_token_cache

    # Check if cached token is still valid (with a small buffer)
    if access_token_cache["token"] and access_token_cache["expires_at"] > datetime.now() + timedelta(seconds=60):
        print("Using cached access token.")
        return access_token_cache["token"]

    print("Fetching new access token...")
    auth_url = f"{API_BASE_URL}/auth/oauth2/token"
    headers = {
        "Content-Type": "application/json",
        "Accept": "*/*"
    }
    payload = {
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "grant_type": "client_credentials"
    }

    try:
        response = requests.post(auth_url, headers=headers, json=payload, timeout=30)
        response.raise_for_status()  # Raise HTTPError for bad responses (4xx or 5xx)

        token_data = response.json()
        access_token = token_data.get("access_token")
        expires_in = token_data.get("expires_in") # Usually in seconds

        if not access_token or not expires_in:
            print(f"Error: Could not retrieve access token. Response: {token_data}")
            return None

        # Cache the token and calculate expiry time
        access_token_cache["token"] = access_token
        access_token_cache["expires_at"] = datetime.now() + timedelta(seconds=int(expires_in))
        print("Successfully obtained new access token.")
        return access_token

    except requests.exceptions.RequestException as e:
        print(f"Error getting access token: {e}")
        if hasattr(e, 'response') and e.response is not None:
             try:
                print(f"Response status: {e.response.status_code}")
                print(f"Response body: {e.response.text}")
             except Exception:
                 print("Could not parse error response body.")
        return None
    except json.JSONDecodeError:
        print(f"Error decoding JSON response from token endpoint. Response text: {response.text}")
        return None


# === 2. Initiate Collection (Customer Pays You) ===
def initiate_collection(customer_msisdn, amount, your_internal_transaction_id):
    """
    Initiates a payment request from a customer's Airtel Money account.
    """
    print(f"\nInitiating collection from {customer_msisdn} for UGX {amount}...")
    token = get_access_token()
    if not token:
        print("Collection failed: Could not get access token.")
        return None, "Failed - No Token"

    collection_url = f"{API_BASE_URL}/collection/v2/payments" # Check V2 endpoint in docs
    external_transaction_id = str(uuid.uuid4()) # Unique ID for this specific API call

    headers = {
        "Content-Type": "application/json",
        "Accept": "*/*",
        "X-Country": COUNTRY,
        "X-Currency": CURRENCY,
        "X-CorrelationID": external_transaction_id, # Unique ID for logging/tracing
        "Authorization": f"Bearer {token}"
    }

    payload = {
        "subscriber": {
            "country": COUNTRY,
            "currency": CURRENCY,
            "msisdn": int(customer_msisdn) # Ensure MSISDN is integer if required by API
        },
        "transaction": {
            "amount": int(amount), # Ensure amount is integer if required
            "country": COUNTRY,
            "currency": CURRENCY,
            "id": your_internal_transaction_id # Your reference for this payment
        }
    }

    try:
        print(f"Sending collection request to: {collection_url}")
        print(f"Payload: {json.dumps(payload, indent=2)}")
        print(f"Headers: {headers}")

        response = requests.post(collection_url, headers=headers, json=payload, timeout=60) # Longer timeout for transaction

        print(f"Collection Response Status Code: {response.status_code}")
        print(f"Collection Response Body: {response.text}")

        # 202 Accepted usually means the request was received, not completed.
        if response.status_code == 202:
            response_data = response.json()
            status = response_data.get("status")
            message = response_data.get("message")
            airtel_ref_id = response_data.get("data", {}).get("transaction", {}).get("airtel_money_id", "N/A") # Path might vary
            print(f"Collection request accepted. Status: {status}, Message: {message}, Airtel Ref: {airtel_ref_id}")
            print("IMPORTANT: Check transaction status later to confirm completion.")
            # Return your internal ID to track it
            return your_internal_transaction_id, "Accepted"
        else:
            # Handle other potential success codes or specific errors if documented
            print(f"Collection request failed or received unexpected status.")
            try:
                 error_data = response.json()
                 print(f"Error details: {error_data}")
                 return your_internal_transaction_id, f"Failed - Status {response.status_code}"
            except json.JSONDecodeError:
                 print("Could not parse error response body.")
                 return your_internal_transaction_id, f"Failed - Status {response.status_code}"


    except requests.exceptions.Timeout:
        print("Collection request timed out.")
        # Consider transaction status unknown, needs checking
        return your_internal_transaction_id, "Timeout"
    except requests.exceptions.RequestException as e:
        print(f"Error initiating collection: {e}")
        if hasattr(e, 'response') and e.response is not None:
             try:
                print(f"Response status: {e.response.status_code}")
                print(f"Response body: {e.response.text}")
             except Exception:
                 print("Could not parse error response body.")
        return your_internal_transaction_id, "Failed - Request Exception"
    except json.JSONDecodeError:
        print(f"Error decoding JSON response from collection endpoint. Response text: {response.text}")
        return your_internal_transaction_id, "Failed - JSON Decode Error"


# === 3. Initiate Disbursement (Pay Agent/Producer/Chef) ===
def initiate_disbursement(agent_msisdn, amount, your_internal_transaction_id):
    """
    Sends money to an agent's Airtel Money account.
    NOTE: Requires PIN encryption - implementation details depend on Airtel docs.
    """
    print(f"\nInitiating disbursement to {agent_msisdn} for UGX {amount}...")
    token = get_access_token()
    if not token:
        print("Disbursement failed: Could not get access token.")
        return None, "Failed - No Token"

    # --- PIN Encryption Placeholder ---
    # You MUST implement PIN encryption here based on Airtel's V2 documentation
    # This usually involves getting Airtel's public key and using RSA encryption.
    encrypted_pin = "PLACEHOLDER_ENCRYPTED_PIN" # Replace with actual encrypted PIN
    if encrypted_pin == "PLACEHOLDER_ENCRYPTED_PIN":
         print("WARNING: PIN encryption is not implemented. Disbursement will likely fail.")
         # return None, "Failed - PIN Encryption Missing" # Uncomment to prevent running without PIN

    # --- End PIN Encryption Placeholder ---


    disbursement_url = f"{API_BASE_URL}/standard/v2/disbursements" # Check V2 endpoint in docs
    external_transaction_id = str(uuid.uuid4())

    headers = {
        "Content-Type": "application/json",
        "Accept": "*/*",
        "X-Country": COUNTRY,
        "X-Currency": CURRENCY,
        "X-CorrelationID": external_transaction_id,
        "Authorization": f"Bearer {token}"
    }

    payload = {
        "payee": {
            "partyIdType": "MSISDN", # Assuming MSISDN, check docs for alternatives
            "partyId": int(agent_msisdn)
        },
        "transaction": {
            "amount": int(amount),
            "id": your_internal_transaction_id # Your reference
        },
        # PIN is often part of the payload or sometimes a header. CHECK DOCS CAREFULLY.
        # This structure is an assumption.
        "pin": encrypted_pin # Add the *encrypted* PIN here
    }

    try:
        print(f"Sending disbursement request to: {disbursement_url}")
        print(f"Payload: {json.dumps(payload, indent=2)}") # Be cautious logging payloads with PINs, even encrypted
        print(f"Headers: {headers}")

        response = requests.post(disbursement_url, headers=headers, json=payload, timeout=60)

        print(f"Disbursement Response Status Code: {response.status_code}")
        print(f"Disbursement Response Body: {response.text}")

        # 202 Accepted usually means the request was received
        if response.status_code == 202:
            response_data = response.json()
            status = response_data.get("status")
            message = response_data.get("message")
            airtel_ref_id = response_data.get("data", {}).get("transaction", {}).get("airtel_money_id", "N/A") # Path might vary
            print(f"Disbursement request accepted. Status: {status}, Message: {message}, Airtel Ref: {airtel_ref_id}")
            print("IMPORTANT: Check transaction status later to confirm completion.")
            return your_internal_transaction_id, "Accepted"
        else:
            print(f"Disbursement request failed or received unexpected status.")
            try:
                 error_data = response.json()
                 print(f"Error details: {error_data}")
                 return your_internal_transaction_id, f"Failed - Status {response.status_code}"
            except json.JSONDecodeError:
                 print("Could not parse error response body.")
                 return your_internal_transaction_id, f"Failed - Status {response.status_code}"


    except requests.exceptions.Timeout:
        print("Disbursement request timed out.")
        return your_internal_transaction_id, "Timeout"
    except requests.exceptions.RequestException as e:
        print(f"Error initiating disbursement: {e}")
        if hasattr(e, 'response') and e.response is not None:
             try:
                print(f"Response status: {e.response.status_code}")
                print(f"Response body: {e.response.text}")
             except Exception:
                 print("Could not parse error response body.")
        return your_internal_transaction_id, "Failed - Request Exception"
    except json.JSONDecodeError:
        print(f"Error decoding JSON response from disbursement endpoint. Response text: {response.text}")
        return your_internal_transaction_id, "Failed - JSON Decode Error"


# === 4. Check Transaction Status ===
def check_transaction_status(your_internal_transaction_id, transaction_type="collection"):
    """
    Checks the status of a previously initiated collection or disbursement.
    'transaction_type' should be 'collection' or 'disbursement'.
    """
    print(f"\nChecking status for {transaction_type} transaction ID: {your_internal_transaction_id}...")
    token = get_access_token()
    if not token:
        print("Status check failed: Could not get access token.")
        return None

    if transaction_type == "collection":
         # Endpoint for checking collection status - CHECK DOCS
        status_url = f"{API_BASE_URL}/standard/v2/collections/{your_internal_transaction_id}" # Example - Verify Correct Endpoint!
    elif transaction_type == "disbursement":
        # Endpoint for checking disbursement status - CHECK DOCS
        status_url = f"{API_BASE_URL}/standard/v2/disbursements/{your_internal_transaction_id}" # Example - Verify Correct Endpoint!
    else:
        print(f"Invalid transaction_type: {transaction_type}. Use 'collection' or 'disbursement'.")
        return None

    external_transaction_id = str(uuid.uuid4()) # Unique ID for this specific API call

    headers = {
        "Accept": "*/*",
        "X-Country": COUNTRY,
        "X-Currency": CURRENCY,
        "X-CorrelationID": external_transaction_id,
        "Authorization": f"Bearer {token}"
    }

    try:
        print(f"Sending status check request to: {status_url}")
        print(f"Headers: {headers}")

        response = requests.get(status_url, headers=headers, timeout=30)
        response.raise_for_status() # Raise HTTPError for bad responses (4xx or 5xx)

        status_data = response.json()
        print(f"Status check successful. Response Code: {response.status_code}")
        print(f"Status Data: {json.dumps(status_data, indent=2)}")

        # Interpret the status based on Airtel documentation
        # Example interpretation (adjust based on actual API response):
        transaction_status = status_data.get("data", {}).get("transaction", {}).get("status", "Unknown")
        print(f"Interpreted Transaction Status: {transaction_status}")
        return status_data # Return the full data for further processing

    except requests.exceptions.HTTPError as e:
        print(f"HTTP error checking status: {e}")
        if e.response.status_code == 404:
            print("Transaction not found (404). It might not exist or hasn't processed yet.")
        elif hasattr(e, 'response') and e.response is not None:
             try:
                print(f"Response status: {e.response.status_code}")
                print(f"Response body: {e.response.text}")
             except Exception:
                 print("Could not parse error response body.")
        return None
    except requests.exceptions.RequestException as e:
        print(f"Error checking transaction status: {e}")
        return None
    except json.JSONDecodeError:
        print(f"Error decoding JSON response from status endpoint. Response text: {response.text}")
        return None


# === Main Execution Example ===
if __name__ == "__main__":

    # --- Ensure Credentials are set ---
    if "YOUR_CLIENT_ID" in CLIENT_ID or "YOUR_CLIENT_SECRET" in CLIENT_SECRET:
        print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
        print("!!! ERROR: Please set your API Client ID and Secret    !!!")
        print("!!!        (Preferably via environment variables)      !!!")
        print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
        exit()


    # --- Example Workflow ---

    # 1. Collect Payment from Customer
    customer_phone = "2567xxxxxxxx"  # Replace with a valid TEST customer number for Sandbox
    service_amount = 5000           # Example amount in UGX
    collection_tx_id = f"COLL_{uuid.uuid4()}" # Generate and STORE this ID in your system

    # Store this ID associated with the customer's order/service
    print(f"Generated Collection Transaction ID: {collection_tx_id}")

    # Initiate the collection
    # The customer will receive a USSD prompt on their phone to enter PIN
    init_coll_id, init_coll_status = initiate_collection(customer_phone, service_amount, collection_tx_id)

    # --------------------------------------------
    # PAUSE - In a real app, you wait here. Either:
    #   a) Poll the status check endpoint after a delay.
    #   b) Wait for a callback notification from Airtel (preferred).
    # --------------------------------------------
    if init_coll_id and init_coll_status == "Accepted":
        print("\nCollection request sent. Waiting 30 seconds before checking status (for demo)...")
        time.sleep(30) # Demo delay - NOT suitable for production!

        # 2. Check Collection Status
        collection_status_data = check_transaction_status(init_coll_id, transaction_type="collection")

        if collection_status_data:
            # Check the actual status from the response data based on Airtel docs
            # Example: look for status like "TS" (Success), "TF" (Failed), "TIP" (Pending)
            final_status = collection_status_data.get("data", {}).get("transaction", {}).get("status", "Unknown")

            if final_status == "TS": # Assuming 'TS' means Transaction Successful
                print(f"\nSUCCESS: Collection {init_coll_id} confirmed successfully!")

                # 3. Pay Agent (Disbursement) - Only if collection was successful
                agent_phone = "2567yyyyyyyy" # Replace with a valid TEST agent number for Sandbox
                agent_payout = 1000        # Example payout amount
                disbursement_tx_id = f"DISB_{uuid.uuid4()}" # Generate and STORE this ID

                print(f"Generated Disbursement Transaction ID: {disbursement_tx_id}")

                # Initiate the disbursement
                init_disb_id, init_disb_status = initiate_disbursement(agent_phone, agent_payout, disbursement_tx_id)

                if init_disb_id and init_disb_status == "Accepted":
                     print("\nDisbursement request sent. Waiting 15 seconds before checking status (for demo)...")
                     time.sleep(15) # Demo delay

                     # 4. Check Disbursement Status
                     disbursement_status_data = check_transaction_status(init_disb_id, transaction_type="disbursement")
                     if disbursement_status_data:
                          final_disb_status = disbursement_status_data.get("data", {}).get("transaction", {}).get("status", "Unknown")
                          print(f"\nDisbursement {init_disb_id} final status check result: {final_disb_status}")
                          # Further logic based on disbursement status...
                     else:
                          print(f"\nCould not get final status for disbursement {init_disb_id}.")

                else:
                    print(f"\nDisbursement initiation for {init_disb_id} failed or was not accepted. Status: {init_disb_status}")

            elif final_status == "TF": # Assuming 'TF' means Transaction Failed
                 print(f"\nFAILED: Collection {init_coll_id} failed. Reason might be in status data.")
            elif final_status == "TIP": # Assuming 'TIP' means Transaction In Progress/Pending
                 print(f"\nPENDING: Collection {init_coll_id} is still pending. Check status again later.")
            else:
                 print(f"\nUNKNOWN: Collection {init_coll_id} status is unclear ({final_status}). Check status again later.")

        else:
            print(f"\nCould not get status for collection {init_coll_id}. Need manual check or retry.")

    else:
         print(f"\nCollection initiation for {collection_tx_id} failed or was not accepted. Status: {init_coll_status}")

    print("\n\n--- Script Execution Finished ---")
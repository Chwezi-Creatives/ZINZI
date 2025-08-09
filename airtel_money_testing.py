import requests
import json
import base64
import hashlib
import hmac
import os
from dotenv import load_dotenv
from Crypto.PublicKey import RSA
from Crypto.Cipher import PKCS1_OAEP, AES
from Crypto.Random import get_random_bytes
from Crypto.Util.Padding import pad, unpad

# Load environment variables
load_dotenv()

# Fetch credentials from .env
CLIENT_ID = os.getenv('AIR_CLIENT_ID')
CLIENT_SECRET = os.getenv('AIR_CLIENT_SECRET')
PRIVATE_KEY = os.getenv('AIR_PRIVATE_KEY')
PUBLIC_KEY = os.getenv('AIR_PUBLIC_KEY')
API_BASE_URL = os.getenv('AIR_API_BASE_URL')

# Fetch Access Token
def get_access_token():
    headers = {'Content-Type': 'application/json', 'Accept': '*/*'}
    body = {
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "grant_type": "client_credentials"
    }
    response = requests.post(f'{API_BASE_URL}/auth/oauth2/token', json=body, headers=headers)
    response_data = response.json()
    if response.status_code == 200:
        return response_data.get("access_token")
    else:
        print(f"Error fetching token: {response_data}")
        return None

# Encrypt payload using AES-GCM
def encrypt_payload(msg):
    aes_key = get_random_bytes(32)  # Secure 256-bit AES key
    iv = get_random_bytes(12)  # 96-bit IV for GCM
    cipher = AES.new(aes_key, AES.MODE_GCM, nonce=iv)
    encrypted_payload, tag = cipher.encrypt_and_digest(msg.encode())

    # RSA encrypt AES key and IV
    public_key = RSA.import_key(base64.b64decode(PUBLIC_KEY))
    rsa_cipher = PKCS1_OAEP.new(public_key)
    encrypted_aes_key = rsa_cipher.encrypt(aes_key + iv)

    return base64.b64encode(encrypted_payload).decode(), base64.b64encode(encrypted_aes_key).decode()

# Generate HMAC signature
def generate_signature(encrypted_payload):
    return base64.b64encode(hmac.new(
        bytes(PRIVATE_KEY, 'utf-8'), 
        msg=encrypted_payload.encode(), 
        digestmod=hashlib.sha256
    ).digest()).decode()

# Create Payment Request
def create_payment(reference, msisdn, amount, auth_token):
    payload = {
        "reference": reference,
        "subscriber": {
            "country": "UG",
            "currency": "UGX",
            "msisdn": msisdn
        },
        "transaction": {
            "amount": amount,
            "country": "UG",
            "currency": "UGX",
            "id": reference
        }
    }

    json_payload = json.dumps(payload)
    encrypted_payload, encrypted_aes_key = encrypt_payload(json_payload)
    signature = generate_signature(encrypted_payload)

    headers = {
        'Accept': '*/*',
        'Content-Type': 'application/json',
        'X-Country': 'UG',
        'X-Currency': 'UGX',
        'Authorization': f'Bearer {auth_token}',
        'x-signature': signature,
        'x-key': encrypted_aes_key
    }

    response = requests.post(f'{API_BASE_URL}/merchant/v2/payments/', headers=headers, json={"data": encrypted_payload})
    return response.json()

# Check Transaction Status
def check_transaction_status(airtel_money_id, auth_token):
    headers = {
        'Authorization': f'Bearer {auth_token}'
    }
    response = requests.get(f'{API_BASE_URL}/merchant/v2/payments/{airtel_money_id}', headers=headers)
    return response.json()

# Create a Refund Request
def create_refund(airtel_money_id, auth_token):
    payload = {
        "transaction": {
            "airtel_money_id": airtel_money_id
        }
    }
    
    json_payload = json.dumps(payload)
    encrypted_payload, encrypted_aes_key = encrypt_payload(json_payload)
    signature = generate_signature(encrypted_payload)

    headers = {
        'Accept': '*/*',
        'Content-Type': 'application/json',
        'Authorization': f'Bearer {auth_token}',
        'x-signature': signature,
        'x-key': encrypted_aes_key
    }

    response = requests.post(f'{API_BASE_URL}/standard/v2/payments/refund', headers=headers, json={"data": encrypted_payload})
    return response.json()

if __name__ == "__main__":
    token = get_access_token()

    if token:
        # Example to create a payment
        payment_response = create_payment("test-payment-001", "757372265", 1000, token)
        print("Payment Response:", payment_response)

        # Example to check transaction status (replace with actual airtel_money_id)
        status_response = check_transaction_status("CI************18", token)
        print("Transaction Status:", status_response)

        # Example to create a refund (replace with actual airtel_money_id)
        refund_response = create_refund("CI************18", token)
        print("Refund Response:", refund_response)
    else:
        print("Failed to fetch access token.")

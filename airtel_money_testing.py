import requests
import json
import base64
import hashlib
import hmac
from Crypto.PublicKey import RSA
from Crypto.Cipher import PKCS1_OAEP
from Crypto.Hash import SHA256

# Your staging credentials and settings
CLIENT_ID = "aaf70342-8c2d-4806-bca7-5a5fcd791b013"
CLIENT_SECRET = "aaf70342-8c2d-4806-bca7-5a5f1cd79b013"
PRIVATE_KEY = "<your_private_key>"  # Used for HMAC
PUBLIC_KEY = "<public_key_from_api>"  # Get from encryption keys

# Fetch Access Token
def get_access_token():
    headers = {'Content-Type': 'application/json', 'Accept': '*/*'}
    body = {
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "grant_type": "client_credentials"
    }
    response = requests.post('https://openapiuat.airtel.africa/auth/oauth2/token', json=body, headers=headers)
    return response.json().get("access_token")

# Encrypt payload using RSA
def encrypt_payload(msg):
    public_key = RSA.import_key(base64.b64decode(PUBLIC_KEY))
    cipher = PKCS1_OAEP.new(public_key, hashAlgo=SHA256)
    cipher_text = cipher.encrypt(msg.encode())
    return base64.b64encode(cipher_text).decode()

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
            "id": reference  # Transaction ID
        }
    }
    # Convert payload to JSON and encode
    json_payload = json.dumps(payload)
    
    # Generate AES key and IV (for example purposes, let’s just use a static key.)
    aes_key = base64.urlsafe_b64encode(b'sixteen byte key'.ljust(32))  # should be a random AES key
    iv = base64.urlsafe_b64encode(b'sixteen byte iv '.ljust(16))  # should be a random IV
    
    # Encrypt the payload using AES, then base64 encode
    
    # -- AES encryption logic goes here --
    encrypted_payload = json_payload  # Placeholder
    encrypted_aes_key = encrypt_payload(f"{aes_key.decode()}:{iv.decode()}")  # RSA encrypt key:iv

    # Generate HMAC signature
    signature = base64.b64encode(hmac.new(bytes(PRIVATE_KEY, 'utf-8'), msg=encrypted_payload.encode(), digestmod=hashlib.sha256).digest()).decode()

    headers = {
        'Accept': '*/*',
        'Content-Type': 'application/json',
        'X-Country': 'UG',
        'X-Currency': 'UGX',
        'Authorization': f'Bearer {auth_token}',
        'x-signature': signature,
        'x-key': encrypted_aes_key
    }

    response = requests.post('https://openapiuat.airtel.africa/merchant/v2/payments/', headers=headers, json=payload)
    return response.json()

# Create a Refund Request
def create_refund(airtel_money_id, auth_token):
    payload = {
        "transaction": {
            "airtel_money_id": airtel_money_id
        }
    }
    
    # Similar encryption and headers as in create_payment here...
    # Use previously defined encrypt_payload and other functions
    
    json_payload = json.dumps(payload)
    encrypted_payload = json_payload  # Placeholder
    encrypted_aes_key = encrypt_payload(f"{aes_key.decode()}:{iv.decode()}")  # RSA encrypt key:iv

    # Generate HMAC signature
    signature = base64.b64encode(hmac.new(bytes(PRIVATE_KEY, 'utf-8'), msg=encrypted_payload.encode(), digestmod=hashlib.sha256).digest()).decode()

    headers = {
        'Accept': '*/*',
        'Content-Type': 'application/json',
        'X-Country': 'UG',
        'X-Currency': 'UGX',
        'Authorization': f'Bearer {auth_token}',
        'x-signature': signature,
        'x-key': encrypted_aes_key
    }

    response = requests.post('https://openapi.uat.airtel.africa/standard/v2/payments/refund', headers=headers, json=payload)
    return response.json()

if __name__ == "__main__":
    token = get_access_token()
    
    # Example to create a payment
    payment_response = create_payment("test-payment-001", "752604392", 1000, token)
    print("Payment Response:", payment_response)

    # Example to create a refund (replace with actual airtel_money_id from a successful payment)
    refund_response = create_refund("CI************18", token)
    print("Refund Response:", refund_response)
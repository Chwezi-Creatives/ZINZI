#cSpell:disable
from flask import Flask, request, jsonify
import hashlib
import pyodbc
import random
import string
import zinzi
import logging
from flask_cors import CORS
from zinzi import Authentication, Updatelists, MealRecommendation
from zinzi import configure_paypal, create_payment, execute_payment, handle_payment_cancellation
from zinzi import configure_stripe, create_stripe_payment, execute_stripe_payment, handle_stripe_payment_cancellation

app = Flask(__name__)
CORS(app)

# Create instances of the classes from the backend
auth = Authentication()
updater = Updatelists()
meal_rec = MealRecommendation(1)  # Example user_id is 1 for testing


@app.route('/rr')
def welcome():
    return 'Welcome to Bonobo API.'

# 1. Signup User (Using the signup_user method from the Authentication class)
@app.route('/rr/signup_user', methods=['POST'])
def signup_user():
    data = request.get_json()
    name = data.get('name')
    email = data.get('email')
    password = data.get('password')

    if not name or not email or not password:
        return jsonify({'error': 'Missing required fields'}), 400

    # Call the signup_user method
    user_id = auth.signup_user(name, email, password)
    
    if user_id is None:
        return jsonify({'error': 'Failed to register user'}), 500

    # Return a response with user_id as an integer
    return jsonify({'message': 'User registered successfully', 'user_id': user_id}), 201

@app.route('/rr/verify_user', methods=['POST'])
def verify_user():
    try:
        # Parse JSON payload from request
        data = request.json
        print(f"Received verification request: {data}")
        if not data or 'user_id' not in data or 'verification_code' not in data:
            return jsonify({'message': 'Invalid request payload'}), 400

        user_id = data['user_id']
        verification_code = data['verification_code']

        # Call the verification method
        response, status_code = auth.verify_user_email(user_id, verification_code)
        return jsonify(response), status_code
    except Exception as e:
        print(f"Error: {e}")
        return jsonify({'message': 'Internal server error'}), 500


@app.route('/rr/login_user', methods=['POST'])
def login_user():
    data = request.get_json()
    identifier = data.get('identifier')  # Can be name or email
    password = data.get('password')

    if not identifier or not password:
        return jsonify({'error': 'Missing required fields'}), 400

    # Call the login_user method from the Authentication class
    result, status_code = auth.login_user(identifier, password)

    if status_code == 200:
        # Include the user_id in the response if login is successful
        return jsonify({'message': result['message'], 'user_id': result['user_id']}), 200
    else:
        # Return the error message from the login_user method
        return jsonify({'error': result['message']}), status_code


# 3. Add or Update User Metrics (Using the add_user_metrics method from the Updatelists class)
@app.route('/rr/add_user_metrics', methods=['POST'])
def add_user_metrics():
    try:
        data = request.get_json()
        print(f"Received data: {data}")  # Debugging the received data

        # Extract the data from the request
        user_id = data.get('user_id')
        age_range = data.get('age_range')
        weight = data.get('weight')
        height = data.get('height')
        cholesterol_level = data.get('cholesterol_level')
        sys_bp = data.get('sys_bp')
        dia_bp = data.get('dia_bp')
        pulse = data.get('pulse')
        sex = data.get('sex')  # Added 'sex' to the extracted data
        activity_level = data.get('activity_level')  # Added 'activity_level' to the extracted data

        # Validate the incoming data
        required_fields = ['user_id', 'age_range', 'weight', 'height', 'cholesterol_level', 'sys_bp', 'dia_bp', 'pulse', 'sex', 'activity_level']
        if not all(data.get(field) for field in required_fields):
            return jsonify({'error': 'Missing required fields'}), 400

        # Convert the values to floats where applicable
        weight = float(weight)
        cholesterol_level = float(cholesterol_level)
        sys_bp = float(sys_bp)
        dia_bp = float(dia_bp)
        pulse = float(pulse)
        height = float(height)

        # Call the function with all parameters
        updater.add_user_metrics(user_id, age_range, weight, height, cholesterol_level, sys_bp, dia_bp, pulse, sex, activity_level)
        
        return jsonify({'message': 'Metrics updated successfully.'}), 200
    except Exception as e:
        print(f"Error: {e}")
        return jsonify({'message': 'Error updating metrics.', 'error': str(e)}), 500


    
@app.route('/rr/get_user_metrics', methods=['GET'])
def get_user_metrics():
    user_id = request.args.get('user_id')
    if not user_id:
        return jsonify({'error': 'User ID is required'}), 400

    try:
        updatelists = Updatelists()
        user_metrics = updatelists.get_user_metrics(user_id)
        print (user_metrics)
        

        if user_metrics:
            return jsonify(user_metrics), 200
        
        else:
            return jsonify({'error': 'User metrics not found'}), 404
    except Exception as e:
        return jsonify({'error': f'Error fetching metrics: {str(e)}'}), 500


# 4. Add or Update User Preferences (Using the add_user_preferences method from the Updatelists class)
@app.route('/rr/add_user_preferences', methods=['POST'])
def add_user_preferences():
    data = request.get_json()
    user_id = data.get('user_id')
    goals = data.get('goals')
    diet_type = data.get('diet_type')
    food_restrictions = data.get('food_restrictions')
    print(data)  # Printing the incoming data

    # List to hold missing fields
    missing_fields = []

    # Check for missing fields
    if not user_id:
        missing_fields.append('user_id')
    if not goals:
        missing_fields.append('goals')
    if not diet_type:
        missing_fields.append('diet_type')
    if missing_fields:
        error_message = f'Missing required fields: {", ".join(missing_fields)}'
        error_response = jsonify({'error': error_message})
        print(f"Response: {error_response.get_data(as_text=True)}")  # Print the error response
        return error_response, 400

    try:
        updater.add_user_preferences(user_id, goals, diet_type, food_restrictions)
        success_response = jsonify({'message': 'User preferences updated successfully'})
        print(f"Response: {success_response.get_data(as_text=True)}")  # Print the success response
        return success_response, 200
    except Exception as e:
        error_response = jsonify({'error': f'Error updating preferences: {str(e)}'})
        print(f"Response: {error_response.get_data(as_text=True)}")  # Print the error response
        return error_response, 500


@app.route('/rr/fetch_user_preferences', methods=['GET'])
def get_user_preferences():
    user_id = request.args.get('user_id')
    
    if not user_id:
        return jsonify({"error": "user_id is required"}), 400
    
    try:
        user_id = int(user_id)  # Ensure user_id is an integer
        user_preferences = updater.fetch_user_preferences(user_id)
        print(user_preferences)
        
        if user_preferences:
            return jsonify(user_preferences), 200
        else:
            return jsonify({"error": f"No preferences found for user with ID {user_id}."}), 404
    except ValueError:
        return jsonify({"error": "user_id must be an integer"}), 400
    except Exception as e:
        return jsonify({"error": f"Error fetching preferences: {str(e)}"}), 500
    

# New Route: Log User Metrics
@app.route('/rr/log_user_metrics', methods=['POST'])
def log_user_metrics():
    try:
        data = request.get_json()
        user_id = data.get('user_id')
        weight = data.get('weight')

        # Validate the incoming data
        if not user_id or not weight:
            return jsonify({'error': 'Missing required fields'}), 400

        # Call the method in zinzy.py to log user metrics
        response = updater.log_user_metrics(user_id, weight)

        if response:
            return jsonify({'message': 'Metrics logged successfully'}), 200
        else:
            return jsonify({'error': 'Failed to log metrics'}), 500
    except Exception as e:
        print(f"Error: {e}")
        return jsonify({'error': f'Error logging metrics: {str(e)}'}), 500

# New Route: Fetch User Metrics History
@app.route('/rr/get_metrics_history', methods=['GET'])
def get_metrics_history():
    user_id = request.args.get('user_id')

    if not user_id:
        return jsonify({'error': 'User ID is required'}), 400

    try:
        # Call the method in zinzy.py to fetch metrics history
        metrics_history = updater.get_metrics_history(user_id)
        print(metrics_history)

        if metrics_history:
            return jsonify(metrics_history), 200
        else:
            return jsonify({'error': 'No metrics history found for the user'}), 404
    except Exception as e:
        print(f"Error: {e}")
        return jsonify({'error': f'Error fetching metrics history: {str(e)}'}), 500


# 5. Get Meal Recommendations (Using the recommend_meals method from the MealRecommendation class)
@app.route('/rr/get_meal_recommendations', methods=['GET'])
def get_meal_recommendations():
    user_id = request.args.get('user_id')

    if not user_id:
        return jsonify({'error': 'Missing user_id'}), 400

    try:
        recommended_meals = meal_rec.recommend_meals()
        return jsonify({'recommended_meals': recommended_meals}), 200
    except Exception as e:
        return jsonify({'error': f'Error fetching meal recommendations: {str(e)}'}), 500
    


# Endpoint to initiate payment
# Configure PayPal SDK (replace with your credentials)
configure_paypal('sandbox', 'AcKJRTT6sFMyTvRfqzMXP0b2pXbBv12hDXHP1lA16lwdMYpT942sIFxyEttBKcaX3B_Y640CiJSLIziX', 'EPZFANf3DedgssBp64xEwR2H0BnoIQy9HTq04Wi4Fohf_c2rYLU3q7iv0QhKnXTNmaQT4rHxHAb_7p-K')

@app.route('/rr/pay', methods=['POST'])
def create_payment_route():
    data = request.json
    amount = data.get('amount')
    description = "Payment for ZINZI health service"  # Update with your description

    if amount is None:
        return jsonify({"error": "Amount is required"}), 400

    response = create_payment(amount, description)
    return jsonify(response)

@app.route('/rr/execute', methods=['GET'])
def execute_payment_route():
  payment_id = request.args.get('paymentId')
  payer_id = request.args.get('PayerID')

  response = execute_payment(payment_id, payer_id)
  return jsonify(response)

@app.route('/rr/cancel', methods=['GET'])
def handle_payment_cancellation_route():
  return jsonify(handle_payment_cancellation())

# Configure Stripe with your secret key
STRIPE_SECRET_KEY = "sk_test_51QdZkrP0TRsYJeZcUMkyQMSDojKYuRaWVZmmTP7VkdXui3sEeu5jsaXimH8qQGd0q9foYSkGdZt5yQ7Gs8Vfi0HT00odFWIpA3"
configure_stripe(STRIPE_SECRET_KEY)


@app.route('/rr/create_stripe_payment', methods=['POST'])
def create_payment():
    """
    Endpoint to create a Stripe payment intent.
    Expects JSON with 'amount'.
    """
    try:
        data = request.json
        amount = data.get('amount')

        if not amount:
            return jsonify({"status": "failure", "error": "Missing amount"}), 400

        # Call backend function to create payment
        response = create_stripe_payment(amount)
        return jsonify(response)
    except Exception as e:
        logging.error(f"Unexpected error: {e}")
        return jsonify({"status": "failure", "error": "Something went wrong"}), 500

@app.route('/rr/confirm_stripe_payment', methods=['POST'])
def confirm_payment():
    """
    Endpoint to confirm a Stripe payment.
    Expects JSON with 'paymentIntentId' and optionally 'paymentMethodId'.
    """
    try:
        data = request.json
        payment_intent_id = data.get('paymentIntentId')
        payment_method_id = data.get('paymentMethodId')

        if not payment_intent_id:
            return jsonify({"error": "Missing paymentIntentId"}), 400

        # Call backend function to confirm payment
        response = execute_stripe_payment(payment_intent_id, payment_method_id)
        return jsonify(response)
    except Exception as e:
        logging.error(f"Unexpected error: {e}")
        return jsonify({"error": "Something went wrong"}), 500


@app.route('/rr/cancel_stripe_payment', methods=['POST'])
def cancel_payment():
    """
    Endpoint to handle payment cancellation.
    """
    try:
        # Call backend function to handle cancellation
        response = handle_stripe_payment_cancellation()
        return jsonify(response)
    except Exception as e:
        logging.error(f"Unexpected error: {e}")
        return jsonify({"error": "Something went wrong"}), 500




if __name__ == '__main__':
  app.run(debug=True, host='0.0.0.0')
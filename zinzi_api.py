from flask import Flask, request, jsonify
import uuid
import logging
import json
from flask_cors import CORS
from datetime import datetime
from zinzi import (
    Authentication,
    Updatelists, GetAllMeals,
    MealRecommendation2,
    configure_paypal,
    create_payment_paypal,
    execute_payment,
    handle_payment_cancellation,
    configure_stripe,
    create_stripe_payment,
    execute_stripe_payment,
    handle_stripe_payment_cancellation,
)
from momo import (
    request_momo_payment,
    check_momo_payment_status,
    configure_momo,
)
from crud import Database, Users, Chefs, Herbals, Meals, Produce, Producers, Gadgets, Spices, Stakeholders, MetricsHistory, Orders

app = Flask(__name__)
CORS(app)

# Configure Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Create instances of the classes from the backend
auth = Authentication()
updater = Updatelists()
meal_fetcher = GetAllMeals()

# Initialize database and CRUD classes
db = Database()
users = Users(db)
chefs = Chefs(db)
herbals = Herbals(db)
meals = Meals(db)
produce = Produce(db)
producers = Producers(db)
gadgets = Gadgets(db)
spices = Spices(db)
stakeholders = Stakeholders(db)
metrics_history = MetricsHistory(db)
orders = Orders(db)

@app.route('/rr')
def welcome():
    return 'Welcome to Bonobo API.'

# Meal fetching and recommendations
@app.route('/rr/meals', methods=['GET'])
def get_meals():
    """ Fetch all meals """
    try:
        meals_list = meal_fetcher.Fetch_All_Meals()
        if meals_list:
            return jsonify(meals_list), 200
        else:
            return jsonify({'error': 'No meals found.'}), 404
    except Exception as e:
        logger.error(f"Error fetching meals: {e}")
        return jsonify({'error': f'Error fetching meals: {str(e)}'}), 500

@app.route('/rr/recommend_meals', methods=['GET'])
def recommend_meals_f():
    user_id = request.args.get('user_id')
    if not user_id:
        logger.error('User ID is required.')
        return jsonify({'error': 'User ID is required'}), 400
    try:
        meal_recommender = MealRecommendation2(user_id=int(user_id))
        recommended_meals = meal_recommender.recommend_meals()
        if recommended_meals:
            return jsonify({
                'message': 'Recommended meals retrieved successfully.',
                'data': recommended_meals
            }), 200
        else:
            return jsonify({'error': 'No recommended meals found for user ID: {}'.format(user_id)}), 404
    except Exception as e:
        logger.error(f'Error fetching recommended meals for user ID {user_id}: {e}')
        return jsonify({'error': f'Error fetching recommended meals: {str(e)}'}), 500

# User Authentication
@app.route('/rr/signup_user', methods=['POST'])
def signup_user():
    data = request.get_json()
    name = data.get('name')
    email = data.get('email')
    password = data.get('password')
    if not name or not email or not password:
        logger.error('Missing required fields during signup.')
        return jsonify({'error': 'Missing required fields'}), 400
    try:
        user_id = users.create_user({'Name': name, 'Email': email, 'Password': password})['UserId']
        return jsonify({
            'message': 'User registered successfully',
            'data': {'user_id': user_id}
        }), 201
    except ValueError as ve:
        logger.error(f"Validation error during user signup: {ve}")
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        logger.error(f"Exception occurred during user signup: {e}")
        return jsonify({'error': str(e)}), 500  

@app.route('/rr/verify_user', methods=['POST'])
def verify_user():
    try:
        data = request.json
        if not data or 'user_id' not in data or 'verification_code' not in data:
            logger.error('Invalid request payload for user verification: {}'.format(data))
            return jsonify({'error': 'Invalid request payload'}), 400
        user_id = data['user_id']
        verification_code = data['verification_code']
        response, status_code = auth.verify_user_email(user_id, verification_code)
        return jsonify(response), status_code
    except Exception as e:
        logger.error(f'Internal server error during verification: {e}')
        return jsonify({'message': 'Internal server error', 'error': str(e)}), 500

@app.route('/rr/login_user', methods=['POST'])
def login_user():
    data = request.get_json()
    identifier = data.get('identifier')
    password = data.get('password')
    if not identifier or not password:
        logger.error('Missing required fields during login.')
        return jsonify({'error': 'Missing required fields'}), 400
    try:
        result, status_code = auth.login_user(identifier, password)
        if status_code == 200:
            return jsonify({
                'message': result['message'],
                'data': {
                    'user_id': result['user_id'],
                    'user_type': result['user_type']
                }
            }), 200
        else:
            logger.warning(f'Login error for {identifier}: {result["message"]}')
            return jsonify({'error': result['message']}), status_code
    except Exception as e:
        logger.error(f"Exception occurred during user login: {e}")
        return jsonify({'error': str(e)}), 500  

# Login endpoints for each user type
@app.route('/rr/login/chefs', methods=['POST'])
def login_chef():
    data = request.get_json()
    identifier = data.get('identifier')
    password = data.get('password')
    if not identifier or not password:
        logger.error('Missing required fields during chef login.')
        return jsonify({'error': 'Missing required fields'}), 400
    try:
        result, status_code = chefs.login_user(identifier, password)
        if status_code == 200:
            return jsonify({
                'message': result['message'],
                'data': {
                    'chef_id': result['chef_id'],
                    'user_type': result['user_type']
                }
            }), 200
        else:
            logger.warning(f'Chef login error for {identifier}: {result["message"]}')
            return jsonify({'error': result['message']}), status_code
    except Exception as e:
        logger.error(f"Exception occurred during chef login: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/rr/rchefs', methods=['GET'])
def list_chefs_endpoint():
    """ Fetch all chefs or a specific chef by chef_id """
    chef_id = request.args.get('chef_id')  # Optional parameter
    try:
        chefs_list = chefs.list_chefs(chef_id)
        logger.info('Fetched chefs list successfully.')
        return jsonify({
            'message': 'Chefs retrieved successfully.',
            'data': chefs_list
        }), 200
    except Exception as e:
        logger.error(f'Error fetching chefs: {e}')
        return jsonify({'error': f'Error fetching chefs: {str(e)}'}), 500

@app.route('/rr/login/producers', methods=['POST'])
def login_producer():
    data = request.get_json()
    identifier = data.get('identifier')
    password = data.get('password')
    if not identifier or not password:
        logger.error('Missing required fields during producer login.')
        return jsonify({'error': 'Missing required fields'}), 400
    try:
        result, status_code = producers.login_user(identifier, password)
        if status_code == 200:
            return jsonify({
                'message': result['message'],
                'data': {
                    'producer_id': result['producer_id'],
                    'user_type': result['user_type']
                }
            }), 200
        else:
            logger.warning(f'Producer login error for {identifier}: {result["message"]}')
            return jsonify({'error': result['message']}), status_code
    except Exception as e:
        logger.error(f"Exception occurred during producer login: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/rr/login/stakeholders', methods=['POST'])
def login_stakeholder():
    data = request.get_json()
    identifier = data.get('identifier')
    password = data.get('password')
    if not identifier or not password:
        logger.error('Missing required fields during stakeholder login.')
        return jsonify({'error': 'Missing required fields'}), 400
    try:
        result, status_code = stakeholders.login_user(identifier, password)
        if status_code == 200:
            return jsonify({
                'message': result['message'],
                'data': {
                    'stakeholder_id': result['stakeholder_id'],
                    'user_type': result['user_type']
                }
            }), 200
        else:
            logger.warning(f'Stakeholder login error for {identifier}: {result["message"]}')
            return jsonify({'error': result['message']}), status_code
    except Exception as e:
        logger.error(f"Exception occurred during stakeholder login: {e}")
        return jsonify({'error': str(e)}), 500

# User Management
@app.route('/rr/rusers', methods=['GET'])
def get_users_endpoint():
    """ Fetch all users or a specific user based on user_id """
    user_id = request.args.get('user_id')  # Optional parameter
    try:
        users_list = users.list_users(user_id=user_id)
        logger.info('Fetched users list successfully.')
        return jsonify({
            'message': 'Users retrieved successfully.',
            'data': users_list
        }), 200
    except Exception as e:
        logger.error(f'Error fetching users: {e}')
        return jsonify({'error': f'Error fetching users: {str(e)}'}), 500

# CRUD for Metrics
@app.route('/rr/metrics', methods=['POST'], endpoint='create_metric_endpoint_1')
def create_metric_endpoint():
    data = request.json
    try:
        created_metric = users.create_metric(data)
        logger.info('Metric data added successfully.')
        return jsonify(created_metric), 201
    except ValueError as ve:
        logger.error(f'Validation error while adding metric: {ve}')
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        logger.error(f'Error adding metric: {e}')
        return jsonify({'error': f'Error adding metric: {str(e)}'}), 500

@app.route('/rr/metrics', methods=['GET'])
def list_metrics_endpoint():
    metric_id = request.args.get('metric_id')  # Optional parameter
    try:
        metrics = users.list_metrics(metric_id=metric_id)
        logger.info('Fetched metrics list successfully.')
        return jsonify({
            'message': 'Metrics retrieved successfully.',
            'data': metrics
        }), 200
    except Exception as e:
        logger.error(f'Error fetching metrics: {e}')
        return jsonify({'error': f'Error fetching metrics: {str(e)}'}), 500

@app.route('/rr/metrics/<int:metric_id>', methods=['PUT'])
def update_metric_endpoint(metric_id):
    updates = request.json
    try:
        users.update_metric(metric_id, updates)
        return jsonify({"message": "Metric updated successfully"}), 200
    except ValueError as ve:
        logger.error(f'Validation error while updating metric: {ve}')
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        logger.error(f'Error updating metric: {e}')
        return jsonify({'error': f'Error updating metric: {str(e)}'}), 500

# Metrics History Management
@app.route('/rr/metrics_history', methods=['POST'], endpoint='create_metric_history_endpoint')
def create_metric_history_endpoint():
    data = request.json
    try:
        created_history = users.create_metric_history(data)
        logger.info('Metric history data added successfully.')
        return jsonify(created_history), 201
    except ValueError as ve:
        logger.error(f'Validation error while adding metric history: {ve}')
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        logger.error(f'Error adding metric history: {e}')
        return jsonify({'error': f'Error adding metric history: {str(e)}'}), 500

@app.route('/rr/metrics_history', methods=['GET'])
def list_metric_history_endpoint():
    log_id = request.args.get('log_id')  # Optional parameter
    try:
        history_list = users.list_metric_history(log_id=log_id)
        logger.info('Fetched metric history list successfully.')
        return jsonify({
            'message': 'Metric history retrieved successfully.',
            'data': history_list
        }), 200
    except Exception as e:
        logger.error(f'Error fetching metric history: {e}')
        return jsonify({'error': f'Error fetching metric history: {str(e)}'}), 500

@app.route('/rr/metrics_history/<int:log_id>', methods=['PUT'])
def update_metric_history_endpoint(log_id):
    updates = request.json
    try:
        users.update_metric_history(log_id, updates)
        return jsonify({"message": "Metric history updated successfully"}), 200
    except ValueError as ve:
        logger.error(f'Validation error while updating metric history: {ve}')
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        logger.error(f'Error updating metric history: {e}')
        return jsonify({'error': f'Error updating metric history: {str(e)}'}), 500

# User Preferences Management
@app.route('/rr/fetch_user_preferences', methods=['GET'])
def fetch_user_preferences_endpoint():
    user_id = request.args.get('user_id')  # Optional parameter
    try:
        if not user_id:
            logger.error('User ID is required to fetch preferences.')
            return jsonify({'error': 'User ID is required'}), 400
        preferences = users.list_preferences(user_id=user_id)
        logger.info('Fetched user preferences successfully.')
        return jsonify({
            'message': 'User preferences retrieved successfully.',
            'data': preferences
        }), 200
    except Exception as e:
        logger.error(f'Error fetching user preferences: {e}')
        return jsonify({'error': f'Error fetching user preferences: {str(e)}'}), 500

@app.route('/rr/update_user_preferences', methods=['PUT'])
def update_user_preferences_endpoint():
    user_id = request.args.get('user_id')
    preferences = request.json
    try:
        if not user_id or not preferences:
            logger.error('User ID and preferences are required to update preferences.')
            return jsonify({'error': 'User ID and preferences are required'}), 400
        users.update_user_preferences(user_id=user_id, preferences=preferences)
        logger.info('User preferences updated successfully.')
        return jsonify({'message': 'User preferences updated successfully.'}), 200
    except ValueError as ve:
        logger.error(f'Validation error while updating user preferences: {ve}')
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        logger.error(f'Error updating user preferences: {e}')
        return jsonify({'error': f'Error updating user preferences: {str(e)}'}), 500

# CRUD for Herbals
@app.route('/rr/aherbals', methods=['POST'])
def add_herbal_endpoint():
    data = request.json
    try:
        created_herbal = herbals.create_herbal(data)
        logger.info('Herbal data added successfully.')
        return jsonify(created_herbal), 201
    except ValueError as ve:
        logger.error(f'Validation error while adding herbal: {ve}')
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        logger.error(f'Error adding herbal: {e}')
        return jsonify({'error': f'Error adding herbal: {str(e)}'}), 500

@app.route('/rr/rherbals', methods=['GET'])
def get_herbals_endpoint():
    herbal_id = request.args.get('herbal_id')  # Optional parameter
    try:
        herbals_list = herbals.list_herbals(herbal_id)
        logger.info('Fetched herbal list successfully.')
        return jsonify({
            'message': 'Herbals retrieved successfully.',
            'data': herbals_list
        }), 200
    except Exception as e:
        logger.error(f'Error fetching herbals: {e}')
        return jsonify({'error': f'Error fetching herbals: {str(e)}'}), 500

# CRUD for Meals
@app.route('/rr/meals', methods=['POST'])
def add_meal_endpoint():
    data = request.json
    try:
        created_meal = meals.create_meal(data)
        logger.info('Meal data added successfully.')
        return jsonify(created_meal), 201
    except ValueError as ve:
        logger.error(f'Validation error while adding meal: {ve}')
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        logger.error(f'Error adding meal: {e}')
        return jsonify({'error': f'Error adding meal: {str(e)}'}), 500

@app.route('/rr/rmeals', methods=['GET'])
def get_meals_endpoint():
    meal_id = request.args.get('meal_id')  # Optional parameter
    try:
        meals_list = meals.list_meals(meal_id)
        logger.info('Fetched meals list successfully.')
        return jsonify({
            'message': 'Meals retrieved successfully.',
            'data': meals_list
        }), 200
    except Exception as e:
        logger.error(f'Error fetching meals: {e}')
        return jsonify({'error': f'Error fetching meals: {str(e)}'}), 500

# CRUD for Produce
@app.route('/rr/produce', methods=['POST'])
def add_produce_endpoint():
    data = request.json
    try:
        created_produce = produce.create_produce(data)
        logger.info('Produce data added successfully.')
        return jsonify(created_produce), 201
    except ValueError as ve:
        logger.error(f'Validation error while adding produce: {ve}')
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        logger.error(f'Error adding produce: {e}')
        return jsonify({'error': f'Error adding produce: {str(e)}'}), 500

@app.route('/rr/produce', methods=['GET'])
def get_produce_endpoint():
    produce_id = request.args.get('produce_id')  # Optional parameter
    try:
        produce_list = produce.list_produce(produce_id)
        logger.info('Fetched produce list successfully.')
        return jsonify({
            'message': 'Produce retrieved successfully.',
            'data': produce_list
        }), 200
    except Exception as e:
        logger.error(f'Error fetching produce: {e}')
        return jsonify({'error': f'Error fetching produce: {str(e)}'}), 500

# CRUD for Producers
@app.route('/rr/create_producers', methods=['POST'])
def add_producer_endpoint():
    data = request.json
    try:
        created_producer = producers.create_producer(data)
        logger.info('Producer data added successfully.')
        return jsonify(created_producer), 201
    except ValueError as ve:
        logger.error(f'Validation error while adding producer: {ve}')
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        logger.error(f'Error adding producer: {e}')
        return jsonify({'error': f'Error adding producer: {str(e)}'}), 500

@app.route('/rr/rproducers', methods=['GET'])
def get_producers_endpoint():
    producer_id = request.args.get('producer_id')  # Optional parameter
    try:
        producers_list = producers.list_producers(producer_id=producer_id)
        logger.info('Fetched producers list successfully.')
        return jsonify({
            'message': 'Producers retrieved successfully.',
            'data': producers_list
        }), 200
    except Exception as e:
        logger.error(f'Error fetching producers: {e}')
        return jsonify({'error': f'Error fetching producers: {str(e)}'}), 500

# CRUD for Gadgets
@app.route('/rr/gadgets', methods=['POST'])
def add_gadget_endpoint():
    data = request.json
    try:
        created_gadget = gadgets.create_gadget(data)
        logger.info('Gadget data added successfully.')
        return jsonify(created_gadget), 201
    except ValueError as ve:
        logger.error(f'Validation error while adding gadget: {ve}')
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        logger.error(f'Error adding gadget: {e}')
        return jsonify({'error': f'Error adding gadget: {str(e)}'}), 500

@app.route('/rr/gadgets', methods=['GET'])
def get_gadgets_endpoint():
    gadget_id = request.args.get('gadget_id')  # Optional parameter
    try:
        gadgets_list = gadgets.list_gadgets(gadget_id)
        logger.info('Fetched gadgets list successfully.')
        return jsonify({
            'message': 'Gadgets retrieved successfully.',
            'data': gadgets_list
        }), 200
    except Exception as e:
        logger.error(f'Error fetching gadgets: {e}')
        return jsonify({'error': f'Error fetching gadgets: {str(e)}'}), 500

# CRUD for Spices
@app.route('/rr/spices', methods=['POST'])
def add_spice_endpoint():
    data = request.json
    try:
        created_spice = spices.create_spice(data)
        logger.info('Spice data added successfully.')
        return jsonify(created_spice), 201
    except ValueError as ve:
        logger.error(f'Validation error while adding spice: {ve}')
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        logger.error(f'Error adding spice: {e}')
        return jsonify({'error': f'Error adding spice: {str(e)}'}), 500

@app.route('/rr/rspices', methods=['GET'])
def get_spices_endpoint():
    spice_id = request.args.get('spice_id')  # Optional parameter
    try:
        spices_list = spices.list_spices(spice_id)
        logger.info('Fetched spices list successfully.')
        return jsonify({
            'message': 'Spices retrieved successfully.',
            'data': spices_list
        }), 200
    except Exception as e:
        logger.error(f'Error fetching spices: {e}')
        return jsonify({'error': f'Error fetching spices: {str(e)}'}), 500

# CRUD for Stakeholders
@app.route('/rr/create_stakeholders', methods=['POST'])
def add_stakeholder_endpoint():
    data = request.json
    try:
        created_stakeholder = stakeholders.create_stakeholder(data)
        logger.info('Stakeholder data added successfully.')
        return jsonify(created_stakeholder), 201
    except ValueError as ve:
        logger.error(f'Validation error while adding stakeholder: {ve}')
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        logger.error(f'Error adding stakeholder: {e}')
        return jsonify({'error': f'Error adding stakeholder: {str(e)}'}), 500

@app.route('/rr/rstakeholders', methods=['GET'])
def get_stakeholders_endpoint():
    stakeholder_id = request.args.get('stakeholder_id')  # Optional parameter
    try:
        stakeholders_list = stakeholders.list_stakeholders(stakeholder_id)
        logger.info('Fetched stakeholders list successfully.')
        return jsonify({
            'message': 'Stakeholders retrieved successfully.',
            'data': stakeholders_list
        }), 200
    except Exception as e:
        logger.error(f'Error fetching stakeholders: {e}')
        return jsonify({'error': f'Error fetching stakeholders: {str(e)}'}), 500

# Orders Management
@app.route('/rr/orders', methods=['GET'])
def get_orders_endpoint():
    chef_id = request.args.get('chef_id')
    producer_id = request.args.get('producer_id')
    user_id = request.args.get('user_id')
    order_id = request.args.get('order_id')  # Optional parameter
    try:
        orders_list = orders.read_orders(chef_id=chef_id, producer_id=producer_id, user_id=user_id, order_id=order_id)
        logger.info('Fetched orders list successfully.')
        return jsonify({
            'message': 'Orders retrieved successfully.',
            'data': orders_list
        }), 200
    except Exception as e:
        logger.error(f'Error fetching orders: {e}')
        return jsonify({'error': f'Error fetching orders: {str(e)}'}), 500

@app.route('/rr/order', methods=['POST'])
def add_order():
    data = request.json
    print(data)  # Debugging: Print the incoming payload
    try:
        user_id = data.get('user_id')
        order_type = data.get('order_type')
        delivery_address = data.get('delivery_address')
        total_price = data.get('total_price')
        notes = data.get('notes', "")
        payment_mode = data.get('payment_mode')
        payment_status = data.get('payment_status', 'Pending')
        items = data.get('items', [])
        if not user_id or not order_type:
            return jsonify({'error': 'Missing required fields: user_id or order_type'}), 400
        created_orders = []
        for item in items:
            product_id = item.get('product_id')
            chef_id = item.get('chef_id')
            producer_id = item.get('producer_id')
            quantity = item.get('quantity', 1)
            price = item.get('price', 0)
            result = orders.create_order(
                user_id=user_id,
                order_type=order_type,
                product_id=product_id,
                chef_id=chef_id,
                producer_id=producer_id,
                delivery_address=delivery_address,
                total_price=price * quantity,
                notes=notes,
                payment_mode=payment_mode,
                payment_status=payment_status,
                amount_paid=0,
                transaction_id=None,
                quantity=quantity
            )
            if not result['success']:
                return jsonify({'error': result['error']}), 500
            created_orders.append(result)
        logger.info('Order(s) added successfully.')
        return jsonify({'success': True, 'message': 'Order(s) created successfully', 'orders': created_orders}), 201
    except ValueError as ve:
        logger.error(f'Validation error while adding order: {ve}')
        return jsonify({'error': str(ve)}), 400
    except Exception as e:
        logger.error(f'Error adding order: {e}')
        return jsonify({'error': f'Error adding order: {str(e)}'}), 500

@app.route('/rr/orders/<int:order_id>', methods=['GET'])
def get_order_by_id(order_id):
    try:
        order = orders.read_order(order_id)  # Fetch a specific order by ID
        if order:
            logger.info(f'Fetched order successfully for Order ID: {order_id}')
            return jsonify({
                'message': 'Order retrieved successfully.',
                'data': order
            }), 200
        else:
            logger.warning(f'No order found for Order ID: {order_id}')
            return jsonify({'error': 'No order found for the specified Order ID.'}), 404
    except Exception as e:
        logger.error(f'Error fetching order with ID {order_id}: {e}')
        return jsonify({'error': f'Error fetching order: {str(e)}'}), 500

# Payment Management
configure_paypal('sandbox', 'YOUR_CLIENT_ID', 'YOUR_SECRET')

@app.route('/rr/pay', methods=['POST'])
def create_payment_route():
    data = request.json
    amount = data.get('amount')
    description = "Payment for ZINZI health service"
    if amount is None:
        logger.error('Amount is required for payment.')
        return jsonify({"error": "Amount is required"}), 400
    response = create_payment_paypal(amount, description)
    logger.info(f'Payment created: {response}')
    return jsonify({
        'message': 'Payment created successfully.',
        'data': response
    })

@app.route('/rr/execute', methods=['GET'])
def execute_payment_route():
    payment_id = request.args.get('paymentId')
    payer_id = request.args.get('PayerID')
    if not payment_id or not payer_id:
        logger.error('Both paymentId and PayerID are required to execute a payment.')
        return jsonify({"error": "Both paymentId and PayerID are required"}), 400
    response = execute_payment(payment_id, payer_id)
    logger.info(f'Executed payment: {response}')
    return jsonify({
        'message': 'Payment executed successfully.',
        'data': response
    })

@app.route('/rr/cancel', methods=['GET'])
def handle_payment_cancellation_route():
    response = handle_payment_cancellation()
    logger.info(f'Payment cancelled: {response}')
    return jsonify({
        'message': 'Payment cancelled successfully.',
        'data': response
    })

# Stripe Management
STRIPE_SECRET_KEY = "YOUR_SECRET_KEY"
configure_stripe(STRIPE_SECRET_KEY)

@app.route('/rr/create_stripe_payment', methods=['POST'])
def create_stripe_payment_route():
    data = request.json
    try:
        amount = data.get('amount')
        if not amount:
            logger.error("Missing amount for Stripe payment.")
            return jsonify({"error": "Missing amount"}), 400
        response = create_stripe_payment(amount)
        logger.info(f'Stripe payment created: {response}')
        return jsonify({
            'message': 'Stripe payment created successfully.',
            'data': response
        })
    except Exception as e:
        logger.error(f"Unexpected error while creating Stripe payment: {e}")
        return jsonify({"error": "Something went wrong"}), 500

@app.route('/rr/confirm_stripe_payment', methods=['POST'])
def confirm_stripe_payment():
    data = request.json
    try:
        payment_intent_id = data.get('paymentIntentId')
        payment_method_id = data.get('paymentMethodId')
        if not payment_intent_id:
            logger.error("Missing paymentIntentId for Stripe payment confirmation.")
            return jsonify({"error": "Missing paymentIntentId"}), 400
        response = execute_stripe_payment(payment_intent_id, payment_method_id)
        logger.info(f'Stripe payment confirmed: {response}')
        return jsonify({
            'message': 'Stripe payment confirmed successfully.',
            'data': response
        })
    except Exception as e:
        logger.error(f"Unexpected error while confirming Stripe payment: {e}")
        return jsonify({"error": "Something went wrong"}), 500

@app.route('/rr/cancel_stripe_payment', methods=['POST'])
def cancel_stripe_payment():
    try:
        response = handle_stripe_payment_cancellation()
        logger.info(f'Stripe payment cancelled: {response}')
        return jsonify({
            'message': 'Stripe payment cancelled successfully.',
            'data': response
        })
    except Exception as e:
        logger.error(f"Unexpected error while cancelling Stripe payment: {e}")
        return jsonify({"error": "Something went wrong"}), 500

# MTN MoMo Configuration and Payment
@app.route('/rr/configure_momo', methods=['POST'])
def configure_momo_route():
    try:
        data = request.json
        api_user = data.get('api_user')
        api_key = data.get('api_key')
        subscription_key = data.get('subscription_key')
        result = configure_momo(api_user, api_key, subscription_key)
        logger.info(f"MoMo API configured: {json.dumps(result)}")
        return jsonify({
            'message': 'MoMo configured successfully.',
            'data': result
        })
    except Exception as e:
        logger.error(f"Error in configure_momo_route: {e}")
        return jsonify({"error": "An error occurred while configuring MoMo"}), 500

@app.route('/rr/request_momo_payment', methods=['POST'])
def request_momo_payment_route():
    try:
        data = request.json
        amount = data.get('amount', '1')
        currency = data.get('currency', 'EUR')
        external_id = str(uuid.uuid4())
        payer_number = data.get('payer_number', '+256787372100')
        payer_message = data.get('payer_message', 'Payment for ZINZI')
        payee_note = data.get('payee_note', 'You have a payment request from ZINZI')
        result = request_momo_payment(amount, currency, external_id, payer_number, payer_message, payee_note)
        logger.info(f"MoMo payment request result: {json.dumps(result)}")
        return jsonify({
            'message': 'MoMo payment requested successfully.',
            'data': result
        })
    except Exception as e:
        logger.error(f"Error in request_momo_payment_route: {e}")
        return jsonify({"error": "An error occurred while processing the payment request"}), 500

@app.route('/rr/check_momo_payment_status', methods=['GET'])
def check_momo_payment_status_route():
    try:
        transaction_ref = request.args.get('transaction_ref')
        if not transaction_ref:
            logger.error("Transaction reference is required to check payment status.")
            return jsonify({"error": "Transaction reference is required."}), 400
        result = check_momo_payment_status(transaction_ref)
        return jsonify({
            'message': 'MoMo payment status checked successfully.',
            'data': result
        })
    except Exception as e:
        logger.error(f"Error in check_momo_payment_status_route: {e}")
        return jsonify({"error": "An error occurred while checking the payment status"}), 500

@app.route('/rr/momo_callback', methods=['POST', 'PUT'])
def momo_callback():
    try:
        notification_data = request.get_json()
        if 'transactionStatus' not in notification_data or 'transactionReference' not in notification_data:
            logger.error("Invalid notification data received in callback: {}".format(notification_data))
            return jsonify({"error": "Invalid notification data"}), 400
        transaction_status = notification_data['transactionStatus']
        transaction_ref = notification_data['transactionReference']
        if transaction_status == 'SUCCESSFUL':
            logger.info(f"Payment {transaction_ref} was successful.")
        else:
            logger.error(f"Payment {transaction_ref} failed with status: {transaction_status}.")
        return jsonify({"message": "Callback received successfully."}), 200
    except Exception as e:
        logger.error(f"Error processing callback: {e}")
        return jsonify({"error": "An unexpected error occurred"}), 500

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0')
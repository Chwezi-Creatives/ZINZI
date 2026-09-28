
# API Changes Documentation

This document tracks all API changes to help with frontend updates.

## 2024-09-24: Subscription Endpoint Updates

### Updated Endpoints

#### `POST /api/subscriptions/cancel`
- **Changes**:
  - Enhanced OpenAPI documentation with detailed response codes
  - Added comprehensive parameter descriptions
  - Improved error handling and logging
  - Added deprecation notice for old endpoint
  - Enhanced response structure with more details

- **Request Body**:
  ```json
  {
    "user_id": 123
  }
  ```

- **Success Response**:
  ```json
  {
    "success": true,
    "message": "Subscription cancelled successfully",
    "details": "Access will continue until the end of the current billing period"
  }
  ```

- **Error Responses**:
  - `400 Bad Request`: Invalid request parameters
  - `403 Forbidden`: Not authorized to cancel this subscription
  - `404 Not Found`: No active subscription found to cancel
  - `500 Internal Server Error`: Failed to process cancellation

#### `GET /api/subscriptions/status`
- **Changes**:
  - Enhanced with detailed OpenAPI documentation
  - Improved error handling
  - Better response structure
  - Deprecated singular `/api/subscription/status` endpoint

### Frontend Updates Required
1. Update any references to the old `/api/subscription/cancel` endpoint to use `/api/subscriptions/cancel`
2. Update error handling to account for the new response structure
3. Update any TypeScript interfaces/types to match the updated response format
4. Consider implementing UI feedback for the subscription cancellation flow based on the new response details

### Backend Updates
- Added proper transaction handling for subscription cancellation
- Improved error logging for better debugging
- Ensured consistent error response formats across all subscription endpoints

## 2024-09-24: API Cleanup and Consolidation

### Removed Endpoints

#### Prebuilt Meal Plan Endpoints (Consolidated into Plan endpoints)
- `GET /api/prebuilt-meal-plans/search` - Use `GET /api/plans?is_prebuilt=true&meal_ids=1,2,3`
- `POST /api/prebuilt-meal-plans` - Use `POST /api/plans` with `is_prebuilt=true`
- `GET /api/prebuilt-meal-plans/{plan_id}` - Use `GET /api/plans/{plan_id}`
- `PUT /api/prebuilt-meal-plans/{plan_id}` - Use `PUT /api/plans/{plan_id}`
- `DELETE /api/prebuilt-meal-plans/{plan_id}` - Use `DELETE /api/plans/{plan_id}`

#### Deprecated Endpoints (Marked for removal in future)
- `POST /api/subscription/subscribe` - Use `POST /api/subscriptions`
- `GET /api/subscription/status` - Use `GET /api/subscriptions/status`
- `POST /api/subscription/cancel` - Use `POST /api/subscriptions/cancel`
- `GET /api/plans/featured` - Use `GET /api/plans?is_featured=true`

### Modified Endpoints

#### Plan Endpoints
- `GET /api/plans` - Enhanced with filtering
  - Added query params: `is_prebuilt`, `chef_id`, `is_featured`
  - Example: `GET /api/plans?is_prebuilt=true&chef_id=123`

- `POST /api/plans` - Now handles both normal and prebuilt plans
  - Use `is_prebuilt` boolean to indicate prebuilt plan
  - For prebuilt plans, include `chef_id` and `meal_ids`

#### Subscription Endpoints
- `GET /api/subscriptions/status` - Now the canonical endpoint for subscription status
  - Returns both subscription and associated plan details

### New Endpoints
- `GET /api/subscriptions/me` - Get current user's subscription
  - Replaces the need for `GET /api/users/{user_id}/subscriptions`

### Plan Endpoint Details

#### Create Plan (POST /api/plans)
- **Required Fields**:
  - `name`: string - Name of the plan
  - `price`: number - Price in USD
  - `billing_cycle`: string - 'monthly' or 'yearly'
  - `is_prebuilt`: boolean - Whether this is a prebuilt meal plan

- **Conditional Fields (when is_prebuilt=true)**:
  - `chef`: object - Chef details (required)
    - `chef_id`: number - ID of the chef
    - `name`: string - Chef's name
    - `avatar_url`: string - URL to chef's avatar
  - `meals`: object[] - Array of meal objects (required)
    - `meal_id`: number - Unique identifier for the meal
    - `name`: string - Name of the meal
    - `description`: string - Description of the meal
    - `image_url`: string - URL to meal image
    - `nutritional_info`: object - Nutritional information
  - `description`: string - Optional plan description
  - `is_featured`: boolean - Whether to feature this plan (default: false)

- **Example Request (Prebuilt Plan)**:
  ```json
  {
    "name": "Gourmet Weekly Plan",
    "price": 99.99,
    "billing_cycle": "monthly",
    "is_prebuilt": true,
    "chef": {
      "chef_id": 123,
      "name": "Chef Michael",
      "avatar_url": "https://example.com/chef.jpg"
    },
    "meals": [
      {
        "meal_id": 1,
        "name": "Pasta Carbonara",
        "description": "Classic Italian pasta",
        "image_url": "https://example.com/pasta.jpg",
        "nutritional_info": {
          "calories": 650,
          "protein": 25,
          "carbs": 75,
          "fat": 30
        }
      }
    ],
    "is_featured": true
  }
  ```

#### List Plans (GET /api/plans)
- **Pagination**:
  - `limit`: number (default: 20, max: 100)
  - `offset`: number (default: 0)
  - `sort_by`: string - Field to sort by (e.g., 'price', 'created_at')
  - `sort_order`: 'asc'|'desc' (default: 'desc')

### Frontend Updates Required
1. Update all references to `/prebuilt-meal-plans/*` to use `/plans` with appropriate filters
2. Update subscription endpoints to use the non-deprecated versions
3. Use the enhanced filtering on list endpoints instead of multiple specific endpoints
4. Update type definitions to reflect the unified plan model

### Database Impact
No schema changes required. All changes are at the API layer only.

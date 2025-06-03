import json
import logging
import asyncio
from typing import Dict, Any, Optional, List, Union
import asyncpg
from datetime import datetime
from contextlib import asynccontextmanager
from .momo_service import MomoService
from fastapi import HTTPException, status

logger = logging.getLogger(__name__)

class DisbursementService:
    """
    Service class for handling order disbursements to chefs, producers, and transporters.
    This service handles the business logic for processing disbursements when orders are completed.
    """
    
    def __init__(self):
        """Initialize the DisbursementService with a MoMoService instance."""
        self.momo_service = MomoService()
        self.disbursement_amount = 1000  # Fixed disbursement amount in UGX
    
    async def process_order_disbursements(self, conn: asyncpg.Connection, order_id: int) -> None:
        """
        Process disbursements for all parties associated with a completed order.
        
        This method coordinates the disbursement process for all parties (chef, producer, transporter)
        involved in an order. It runs each disbursement in its own transaction to ensure isolation.
        
        Args:
            conn: Database connection
            order_id: ID of the completed order
            
        Raises:
            Exception: If there's an error that should be handled by the caller
        """
        logger.info(f"[DISBURSEMENT][process_order_disbursements] Starting disbursement process for order {order_id}")
        
        # Use a transaction for the entire disbursement process
        async with conn.transaction():
            try:
                # Get order details with associated user phone numbers
                order_details = await self._get_order_details(conn, order_id)
                if not order_details:
                    error_msg = f"Order {order_id} not found or missing required details"
                    logger.error(f"[DISBURSEMENT][process_order_disbursements] {error_msg}")
                    raise ValueError(error_msg)
                
                # Process disbursements for each party
                tasks = []
                
                # Process chef disbursement if chef exists
                if order_details.get('chef_id') and order_details.get('chef_phone'):
                    tasks.append(
                        self._process_single_disbursement(
                            conn, order_id, 'chef',
                            order_details['chef_id'], order_details['chef_phone']
                        )
                    )
                
                # Process producer disbursement if producer exists
                if order_details.get('producer_id') and order_details.get('producer_phone'):
                    tasks.append(
                        self._process_single_disbursement(
                            conn, order_id, 'producer',
                            order_details['producer_id'], order_details['producer_phone']
                        )
                    )
                
                # Process transporter disbursement if transporter exists
                if order_details.get('transporter_id') and order_details.get('transporter_phone'):
                    tasks.append(
                        self._process_single_disbursement(
                            conn, order_id, 'transporter',
                            order_details['transporter_id'], order_details['transporter_phone']
                        )
                    )
                
                # Process disbursements sequentially to avoid database connection conflicts
                for i, task in enumerate(tasks):
                    try:
                        await task
                    except Exception as e:
                        user_type = ['chef', 'producer', 'transporter'][i] if i < 3 else 'unknown'
                        logger.error(
                            f"[DISBURSEMENT][process_order_disbursements] "
                            f"Error processing {user_type} disbursement for order {order_id}: {str(e)}",
                            exc_info=e
                        )
                
                logger.info(f"[DISBURSEMENT][process_order_disbursements] "
                            f"Successfully processed disbursements for order {order_id}")
                
            except Exception as e:
                logger.error(f"[DISBURSEMENT][process_order_disbursements] "
                            f"Error processing disbursements for order {order_id}: {str(e)}", 
                            exc_info=True)
                # Re-raise to trigger transaction rollback
                raise
    
    async def _get_order_details(self, conn: asyncpg.Connection, order_id: int) -> Optional[Dict[str, Any]]:
        """
        Retrieve order details along with associated user phone numbers.
        
        Args:
            conn: Database connection
            order_id: ID of the order
            
        Returns:
            Dictionary containing order details and user phone numbers, or None if not found
        """
        query = """
            SELECT 
                o.order_id, o.chef_id, o.producer_id, o.transporter_id,
                c.phone_number as chef_phone,
                p.phone_number as producer_phone,
                t.phone_number as transporter_phone
            FROM orders o
            LEFT JOIN chefs c ON o.chef_id = c.chefid  -- Note: chefs table uses 'chefid' not 'chef_id'
            LEFT JOIN producers p ON o.producer_id = p.producer_id
            LEFT JOIN transporters t ON o.transporter_id = t.transporter_id
            WHERE o.order_id = $1
        """
        
        try:
            row = await conn.fetchrow(query, order_id)
            if not row:
                return None
                
            # Convert to dict and clean up phone numbers
            details = dict(row)
            
            # Format phone numbers (remove any non-digit characters and ensure country code)
            for user_type in ['chef', 'producer', 'transporter']:
                phone_key = f"{user_type}_phone"
                if details.get(phone_key):
                    # Remove any non-digit characters
                    phone = ''.join(filter(str.isdigit, str(details[phone_key])))
                    # If phone starts with 0, replace with 256 (Uganda country code)
                    if phone.startswith('0'):
                        phone = '256' + phone[1:]
                    # Ensure it's at least 9 digits (256 + 9 = 12 digits)
                    if len(phone) >= 12:
                        details[phone_key] = phone
                    else:
                        logger.warning(f"Invalid phone number for {user_type}: {details[phone_key]}")
                        details[phone_key] = None
                else:
                    details[phone_key] = None
            
            return details
            
        except Exception as e:
            logger.error(f"Error fetching order details for order {order_id}: {str(e)}", exc_info=True)
            return None
    
    async def _process_single_disbursement(
        self, 
        conn: asyncpg.Connection, 
        order_id: int, 
        user_type: str, 
        user_id: int, 
        phone_number: str
    ) -> None:
        """
        Process a single disbursement for a user (chef, producer, or transporter).
        
        Args:
            conn: Database connection
            order_id: ID of the order
            user_type: Type of user ('chef', 'producer', 'transporter')
            user_id: ID of the user
            phone_number: Phone number in international format (e.g., 256XXXXXXXXX)
        """
        if not phone_number:
            logger.warning(f"Skipping {user_type} {user_id} for order {order_id}: No phone number")
            return
            
        # Generate IDs outside the transaction to ensure they're the same for success/failure cases
        external_id = f"ZINZI_{order_id}_{user_type.upper()}_{int(datetime.utcnow().timestamp())}"
        payer_message = f"ZINZI Order {order_id} payment"
        payee_note = f"Payment for completing order {order_id}"
        
        try:
            # Log the disbursement attempt
            logger.info(f"Processing {user_type} disbursement for order {order_id}: {user_type}_id={user_id}, phone={phone_number}")
            
            # Call MoMo API to disburse funds
            result = await self.momo_service.disburse_funds(
                amount=self.disbursement_amount,
                payee_id=phone_number,
                external_id=external_id,
                payer_message=payer_message,
                payee_note=payee_note
            )
            
            # Log the successful transaction
            await self._log_disbursement(
                conn=conn,
                order_id=order_id,
                user_type=user_type,
                user_id=user_id,
                amount=self.disbursement_amount,
                transaction_id=result.get('transaction_id', external_id),
                status=result.get('status', 'pending'),
                reference_id=external_id,
                phone_number=phone_number,
                response_data=result
            )
            
            logger.info(f"Successfully processed {user_type} disbursement for order {order_id}")
            
        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error processing {user_type} disbursement for order {order_id}: {error_msg}", exc_info=True)
            
            # Log the failed transaction in a new transaction to ensure it's recorded
            try:
                await self._log_disbursement(
                    conn=conn,
                    order_id=order_id,
                    user_type=user_type,
                    user_id=user_id,
                    amount=self.disbursement_amount,
                    transaction_id=f"FAILED_{int(datetime.utcnow().timestamp())}",
                    status="failed",
                    reference_id=f"FAILED_{external_id}",
                    phone_number=phone_number,
                    error_message=error_msg
                )
            except Exception as log_error:
                logger.error(f"Failed to log failed disbursement: {str(log_error)}", exc_info=True)
            
            # Re-raise the original exception to be handled by the caller
            raise
    
    async def _log_disbursement(
        self,
        conn: asyncpg.Connection,
        order_id: int,
        user_type: str,
        user_id: int,
        amount: int,
        transaction_id: str,
        status: str,
        reference_id: str,
        phone_number: str,
        response_data: Optional[Dict] = None,
        error_message: Optional[str] = None
    ) -> None:
        """
        Log a disbursement transaction in the database.
        
        This method handles logging to both the specific user-type table and the general
        disbursement_transactions table within a transaction.
        
        Args:
            conn: Database connection
            order_id: ID of the order
            user_type: Type of user ('chef', 'producer', 'transporter')
            user_id: ID of the user
            amount: Amount disbursed (in the default currency)
            transaction_id: Transaction ID from MoMo
            status: Transaction status ('pending', 'success', 'failed')
            reference_id: External reference ID
            phone_number: Recipient's phone number
            response_data: Raw response from MoMo API (optional)
            error_message: Error message if the transaction failed (optional)
        """
        try:
            # 1. Log to the specific user-type table (minimal fields)
            table_map = {
                'chef': ('chef_disbursements', 'chef_id'),
                'producer': ('producer_disbursements', 'producer_id'),
                'transporter': ('transporter_disbursements', 'transporter_id')
            }
            
            if user_type in table_map:
                table_name, id_column = table_map[user_type]
                
                # Simplified query with only essential fields
                query = f"""
                    INSERT INTO {table_name} (
                        {id_column}, order_id, amount, transaction_id, created_at
                    ) VALUES ($1, $2, $3, $4, NOW())
                """
                
                # Execute the query with only the essential parameters
                await conn.execute(
                    query,
                    user_id, 
                    order_id, 
                    amount, 
                    transaction_id
                )
                logger.info(f"Logged {user_type} disbursement for order {order_id} in {table_name}")
            
            # 2. Log to the disbursement_transactions table
            if response_data and 'transaction_id' in response_data:
                momo_response = response_data.get('momo_response', {}) if isinstance(response_data, dict) else {}
                
                disb_query = """
                    INSERT INTO disbursement_transactions (
                        transaction_id, external_id, amount, currency, 
                        status, recipient_id, recipient_type, 
                        details, created_at, updated_at
                    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW(), NOW())
                """
                
                metadata = {
                    'user_type': user_type,
                    'user_id': user_id,
                    'order_id': order_id,
                    'response_data': response_data
                }
                if error_message:
                    metadata['error'] = error_message
                
                # Execute the query without starting a new transaction
                await conn.execute(
                    disb_query,
                    response_data.get('transaction_id'),
                    reference_id,
                    amount,
                    'UGX',  # Default currency
                    status.lower(),
                    phone_number,
                    'MSISDN',
                    json.dumps(metadata)
                )
                logger.info(f"Logged disbursement transaction {transaction_id} in disbursement_transactions")
            
        except Exception as e:
            error_msg = f"Error logging disbursement to database: {str(e)}"
            logger.error(error_msg, exc_info=True)
            # Don't re-raise the exception to allow the calling method to handle it
            # This prevents masking the original error with a logging error

# Create a singleton instance of the service
disbursement_service = DisbursementService()

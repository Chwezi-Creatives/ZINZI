import os
import logging
from typing import Optional
from brevo import AsyncBrevo
from brevo.transactional_emails import (
    SendTransacEmailRequestSender,
    SendTransacEmailRequestToItem,
)
from brevo.core.api_error import ApiError

logger = logging.getLogger(__name__)


class BrevoEmailService:
    def __init__(self):
        self.api_key = os.getenv("BREVO_API_KEY")
        self.sender_email = os.getenv("BREVO_SENDER_EMAIL")
        self.sender_name = os.getenv("BREVO_SENDER_NAME", "ZINZI")
        
        if not self.api_key:
            logger.warning("BREVO_API_KEY not configured - email sending will fail")
        
        self.client = AsyncBrevo(
            api_key=self.api_key,
            timeout=30.0,
        ) if self.api_key else None

    async def send_email(
        self,
        to_email: str,
        subject: str,
        html_content: str,
        text_content: Optional[str] = None,
        to_name: Optional[str] = None,
    ) -> bool:
        """
        Send a transactional email via Brevo API.
        
        Args:
            to_email: Recipient email address
            subject: Email subject line
            html_content: HTML email body
            text_content: Optional plain text version
            to_name: Optional recipient name
            
        Returns:
            True if sent successfully, False otherwise
        """
        if not self.client:
            logger.error("Brevo client not initialized - missing API key")
            return False
            
        if not self.sender_email:
            logger.error("BREVO_SENDER_EMAIL not configured")
            return False

        try:
            sender = SendTransacEmailRequestSender(
                email=self.sender_email,
                name=self.sender_name,
            )
            
            to = [SendTransacEmailRequestToItem(
                email=to_email,
                name=to_name or to_email.split("@")[0],
            )]
            
            await self.client.transactional_emails.send_transac_email(
                sender=sender,
                to=to,
                subject=subject,
                html_content=html_content,
                text_content=text_content,
            )
            
            logger.info(f"Email sent successfully to {to_email} via Brevo")
            return True
            
        except ApiError as e:
            logger.error(f"Brevo API error sending to {to_email}: status={e.status_code}, body={e.body}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error sending email to {to_email}: {e}", exc_info=True)
            return False

    async def send_verification_email(
        self,
        to_email: str,
        verification_code: str,
        to_name: Optional[str] = None,
    ) -> bool:
        """
        Send a verification code email using a styled template.
        
        Args:
            to_email: Recipient email address
            verification_code: 6-digit verification code
            to_name: Optional recipient name
            
        Returns:
            True if sent successfully, False otherwise
        """
        subject = "🔐 Your ZINZI Verification Code"
        
        html_content = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                body {{
                    font-family: 'Arial', sans-serif;
                    line-height: 1.6;
                    color: #333333;
                    max-width: 600px;
                    margin: 0 auto;
                    padding: 20px;
                }}
                .container {{
                    border: 1px solid #e0e0e0;
                    border-radius: 8px;
                    overflow: hidden;
                }}
                .header {{
                    background-color: #4CAF50;
                    padding: 20px;
                    text-align: center;
                }}
                .content {{
                    padding: 30px;
                    background-color: #ffffff;
                }}
                .verification-code {{
                    background-color: #f8f9fa;
                    border: 2px dashed #4CAF50;
                    color: #4CAF50;
                    font-size: 28px;
                    font-weight: bold;
                    letter-spacing: 5px;
                    padding: 15px 25px;
                    margin: 25px 0;
                    text-align: center;
                    border-radius: 4px;
                    display: inline-block;
                }}
                .footer {{
                    text-align: center;
                    padding: 20px;
                    font-size: 12px;
                    color: #999999;
                    background-color: #f8f9fa;
                }}
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1 style="color: white; margin: 0;">ZINZI</h1>
                    <p style="color: white; margin: 5px 0 0 0;">Healthy Food, Happy Life</p>
                </div>
                
                <div class="content">
                    <h2>Welcome to ZINZI! 🌱</h2>
                    <p>Thank you for joining our community of health-conscious individuals. To complete your registration, please verify your email address using the code below:</p>
                    
                    <div class="verification-code">
                        {verification_code}
                    </div>
                    
                    <p>This code will expire in 10 minutes for security reasons.</p>
                    
                    <p>If you didn't request this, please ignore this email or contact our support team if you have any concerns.</p>
                    
                    <p>Best regards,<br>The ZINZI Team</p>
                </div>
                
                <div class="footer">
                    <p>© 2025 ZINZI. All rights reserved.</p>
                    <p>Kampala, Uganda | <a href="https://zinzi.ug" style="color: #4CAF50; text-decoration: none;">zinzi.ug</a></p>
                </div>
            </div>
        </body>
        </html>
        """
        
        text_content = f"""
Welcome to ZINZI! 🌱

Your verification code is: {verification_code}

This code will expire in 10 minutes for security reasons.

If you didn't request this, please ignore this email.

Best regards,
The ZINZI Team
        """.strip()
        
        return await self.send_email(
            to_email=to_email,
            subject=subject,
            html_content=html_content,
            text_content=text_content,
            to_name=to_name,
        )

    async def send_password_reset_email(
        self,
        to_email: str,
        reset_code: str,
        user_type: str = "user",
        to_name: Optional[str] = None,
    ) -> bool:
        """
        Send a password reset code email.
        
        Args:
            to_email: Recipient email address
            reset_code: Password reset code
            user_type: Type of user (user, chef, producer, etc.)
            to_name: Optional recipient name
            
        Returns:
            True if sent successfully, False otherwise
        """
        subject = "Your Password Reset Code"
        
        html_content = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                body {{
                    font-family: 'Arial', sans-serif;
                    line-height: 1.6;
                    color: #333333;
                    max-width: 600px;
                    margin: 0 auto;
                    padding: 20px;
                }}
                .container {{
                    border: 1px solid #e0e0e0;
                    border-radius: 8px;
                    overflow: hidden;
                }}
                .header {{
                    background-color: #4CAF50;
                    padding: 20px;
                    text-align: center;
                }}
                .content {{
                    padding: 30px;
                    background-color: #ffffff;
                }}
                .reset-code {{
                    background-color: #f8f9fa;
                    border: 2px dashed #4CAF50;
                    color: #4CAF50;
                    font-size: 28px;
                    font-weight: bold;
                    letter-spacing: 5px;
                    padding: 15px 25px;
                    margin: 25px 0;
                    text-align: center;
                    border-radius: 4px;
                    display: inline-block;
                }}
                .footer {{
                    text-align: center;
                    padding: 20px;
                    font-size: 12px;
                    color: #999999;
                    background-color: #f8f9fa;
                }}
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1 style="color: white; margin: 0;">ZINZI</h1>
                    <p style="color: white; margin: 5px 0 0 0;">Healthy Food, Happy Life</p>
                </div>
                
                <div class="content">
                    <h2>Password Reset Request</h2>
                    <p>Hello,</p>
                    <p>We received a request to reset the password for your {user_type.capitalize()} account.</p>
                    <p>Your password reset code is:</p>
                    
                    <div class="reset-code">
                        {reset_code}
                    </div>
                    
                    <p>Please enter this code in the app to reset your password. This code will expire in 10 minutes.</p>
                    <p>If you didn't request this password reset, you can safely ignore this email.</p>
                    
                    <p>Best regards,<br>The ZINZI Team</p>
                </div>
                
                <div class="footer">
                    <p>© 2025 ZINZI. All rights reserved.</p>
                    <p>Kampala, Uganda | <a href="https://zinzi.ug" style="color: #4CAF50; text-decoration: none;">zinzi.ug</a></p>
                </div>
            </div>
        </body>
        </html>
        """
        
        text_content = f"""
Password Reset Request

Hello,

We received a request to reset the password for your {user_type.capitalize()} account.

Your password reset code is: {reset_code}

Please enter this code in the app to reset your password. This code will expire in 10 minutes.

If you didn't request this password reset, you can safely ignore this email.

Best regards,
The ZINZI Team
        """.strip()
        
        return await self.send_email(
            to_email=to_email,
            subject=subject,
            html_content=html_content,
            text_content=text_content,
            to_name=to_name,
        )


_brevo_service: Optional[BrevoEmailService] = None


def get_brevo_email_service() -> BrevoEmailService:
    """Get or create the singleton BrevoEmailService instance."""
    global _brevo_service
    if _brevo_service is None:
        _brevo_service = BrevoEmailService()
    return _brevo_service
from typing import Callable, Awaitable
from fastapi import Request, HTTPException, status
from slowapi import Limiter
from slowapi.util import get_remote_address

# Initialize rate limiter
limiter = Limiter(
    key_func=get_remote_address,  # Rate limit by IP address
    default_limits=["1000 per day", "100 per hour"]
)

def get_remote_address_override(request: Request) -> str:
    """
    Get client IP address, with support for proxy headers.
    This is a more robust version that checks common proxy headers.
    """
    # Check for forwarded IP first (common with proxies)
    if "x-forwarded-for" in request.headers:
        # Get the first IP in the X-Forwarded-For header
        return request.headers["x-forwarded-for"].split(",")[0].strip()
    
    # Fall back to the default implementation
    return get_remote_address(request)

# Update the limiter to use our custom key function
limiter.key_func = get_remote_address_override

async def rate_limit_middleware(
    request: Request,
    call_next: Callable[[Request], Awaitable]
):
    """
    Middleware to handle rate limiting for all requests.
    """
    # Skip rate limiting for health checks and other non-API endpoints
    if request.url.path.startswith('/health') or request.url.path.startswith('/docs'):
        return await call_next(request)
        
    try:
        # Check rate limit for the current endpoint
        route = request.scope.get('route')
        if route:
            # Get rate limit for this specific endpoint if defined
            endpoint = f"{request.method}:{route.path}"
            await limiter.check(endpoint, request)
            
        return await call_next(request)
        
    except HTTPException as e:
        if e.status_code == status.HTTP_429_TOO_MANY_REQUESTS:
            # Add rate limit headers to the response
            retry_after = e.headers.get('Retry-After', 60)
            return JSONResponse(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                content={"detail": "Too many requests, please try again later.",
                        "retry_after": retry_after},
                headers={"Retry-After": str(retry_after)}
            )
        raise

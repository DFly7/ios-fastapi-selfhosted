"""Aggregate v1 routes.

Route handler convention — async def
--------------------------------------
All handlers that touch the database use ``async def`` and ``await`` every
database call. The project uses SQLAlchemy's AsyncSession, so the event loop
is never blocked by database I/O.

Pure utility handlers (``/ping``) that do no I/O keep plain ``def`` — there
is nothing to await and FastAPI handles both in the same event loop without
any thread-pool overhead for coroutine-free handlers.

Router organisation — inline routes vs feature sub-routers
-----------------------------------------------------------
Simple utility endpoints (``/ping``, ``/secure-test``, ``/me/profile``) live
here inline so the file doubles as a quick reference for common patterns.

For any non-trivial feature — multiple endpoints, its own service layer, or
its own tests — create a dedicated sub-router file (see ``notes.py``) and
mount it with ``api_router.include_router(...)``.  Prefer sub-routers for
feature #2 and beyond; inline routes are the exception, not the template.

To protect all v1 routes: APIRouter(dependencies=[Depends(verify_jwt)])
"""

import uuid as uuid_module

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1 import auth as auth_module
from app.api.v1.notes import router as notes_router
from app.api.v1.webhooks import router as webhooks_router
from app.core.auth import verify_jwt
from app.db.session import get_db
from app.repositories import profile_repo
from app.schemas.profile import ProfileOut, ProfileUpdate

api_router = APIRouter()

# Feature routers — add yours here as the app grows.
api_router.include_router(auth_module.router)
api_router.include_router(notes_router)
api_router.include_router(webhooks_router, prefix="/webhooks", tags=["webhooks"])


@api_router.get("/ping")
def ping() -> dict:
    return {"ok": True}


@api_router.get("/secure-test")
async def secure_test(auth_data: dict = Depends(verify_jwt)) -> dict:
    return {
        "message": "Token valid",
        "user_id": auth_data["payload"].get("sub"),
    }


@api_router.get("/me/profile", response_model=ProfileOut)
async def get_my_profile(
    auth: dict = Depends(verify_jwt),
    db: AsyncSession = Depends(get_db),
) -> ProfileOut:
    """Load the signed-in user's row from `public.profiles`.

    RLS is implicit via the user's database row.
    """
    user_id = uuid_module.UUID(auth["payload"]["sub"])
    profile = await profile_repo.get_profile(db, user_id)
    if not profile:
        raise HTTPException(
            status_code=404,
            detail=(
                "No profile row found. Run migrations and sign up again."
            ),
        )
    return ProfileOut.model_validate(profile)


@api_router.patch("/me/profile", response_model=ProfileOut)
async def update_my_profile(
    payload: ProfileUpdate,
    auth: dict = Depends(verify_jwt),
    db: AsyncSession = Depends(get_db),
) -> ProfileOut:
    """Partially update the signed-in user's profile (PATCH semantics).

    Only the fields included in the request body are changed. Omit a field to
    leave it unchanged. Returns the full updated profile row.
    """
    user_id = uuid_module.UUID(auth["payload"]["sub"])
    changes = payload.model_dump(exclude_none=True)
    if not changes:
        raise HTTPException(
            status_code=422,
            detail="Request body must include at least one field to update.",
        )
    updated = await profile_repo.update_profile(db, user_id, payload)
    if not updated:
        raise HTTPException(status_code=404, detail="Profile not found.")
    return ProfileOut.model_validate(updated)


# Example of including another feature router:
# from app.api.v1.invoices import router as invoices_router
# api_router.include_router(invoices_router, prefix="/invoices", tags=["invoices"])

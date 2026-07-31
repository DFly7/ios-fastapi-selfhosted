import threading
import uuid

from app.services.auth_service import (
    create_access_token,
    create_refresh_token_value,
    decode_access_token,
    hash_password,
    hash_password_async,
    hash_refresh_token,
    verify_password,
    verify_password_async,
)


def test_password_round_trip():
    hashed = hash_password("secret123")
    assert verify_password("secret123", hashed)
    assert not verify_password("wrong", hashed)


async def test_async_password_round_trip():
    hashed = await hash_password_async("secret123")
    assert await verify_password_async("secret123", hashed)
    assert not await verify_password_async("wrong", hashed)


async def test_hash_password_async_offloads_to_worker_thread(monkeypatch):
    """bcrypt is CPU-bound and blocking; it must not run on the event loop thread."""
    import bcrypt

    main_thread = threading.current_thread()
    seen_threads: list[threading.Thread] = []
    real_hashpw = bcrypt.hashpw

    def _spy_hashpw(*args, **kwargs):
        seen_threads.append(threading.current_thread())
        return real_hashpw(*args, **kwargs)

    monkeypatch.setattr(bcrypt, "hashpw", _spy_hashpw)

    await hash_password_async("secret123")

    assert len(seen_threads) == 1
    assert seen_threads[0] is not main_thread


async def test_verify_password_async_offloads_to_worker_thread(monkeypatch):
    import bcrypt

    hashed = hash_password("secret123")
    main_thread = threading.current_thread()
    seen_threads: list[threading.Thread] = []
    real_checkpw = bcrypt.checkpw

    def _spy_checkpw(*args, **kwargs):
        seen_threads.append(threading.current_thread())
        return real_checkpw(*args, **kwargs)

    monkeypatch.setattr(bcrypt, "checkpw", _spy_checkpw)

    assert await verify_password_async("secret123", hashed)

    assert len(seen_threads) == 1
    assert seen_threads[0] is not main_thread


def test_verify_password_accepts_legacy_passlib_compatible_bcrypt_hash():
    # Fixed hash produced under the old passlib bcrypt backend for "legacy-test".
    legacy_hash = "$2b$12$y/17PjtiClXORPvrlaGY1.y6xJ4hOeHxw6ClUbVqJyPE9PiRrIZY."
    assert verify_password("legacy-test", legacy_hash)
    assert not verify_password("wrong-password", legacy_hash)


def test_access_token_decode():
    uid = uuid.uuid4()
    token = create_access_token(uid)
    payload = decode_access_token(token)
    assert payload["sub"] == str(uid)
    assert payload["type"] == "access"


def test_refresh_token_hash_is_deterministic():
    raw = create_refresh_token_value()
    assert hash_refresh_token(raw) == hash_refresh_token(raw)


def test_refresh_token_hash_differs_from_raw():
    raw = create_refresh_token_value()
    assert hash_refresh_token(raw) != raw

import uuid

from app.services.auth_service import (
    create_access_token,
    create_refresh_token_value,
    decode_access_token,
    hash_password,
    hash_refresh_token,
    verify_password,
)


def test_password_round_trip():
    hashed = hash_password("secret123")
    assert verify_password("secret123", hashed)
    assert not verify_password("wrong", hashed)


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

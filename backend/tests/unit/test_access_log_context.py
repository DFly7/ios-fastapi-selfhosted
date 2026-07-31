"""Access-log contextvars must not bind user_email=None (misleading noise)."""

from app.middleware.access_log import request_context_bindings


def test_bindings_omit_user_email_when_absent():
    bindings = request_context_bindings(
        user_id="59bb2690-0a8c-4d42-b05c-6ac8cd5951ca",
        user_email=None,
        client_ip="82.132.216.145",
    )
    assert bindings == {
        "user_id": "59bb2690-0a8c-4d42-b05c-6ac8cd5951ca",
        "client_ip": "82.132.216.145",
    }
    assert "user_email" not in bindings


def test_bindings_include_user_email_when_present():
    bindings = request_context_bindings(
        user_id="59bb2690-0a8c-4d42-b05c-6ac8cd5951ca",
        user_email="user@example.com",
        client_ip="82.132.216.145",
    )
    assert bindings["user_email"] == "user@example.com"


def test_bindings_empty_without_user_id():
    assert request_context_bindings(user_id=None, user_email="x@y.z", client_ip="1.2.3.4") == {}

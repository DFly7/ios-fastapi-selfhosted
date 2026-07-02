"""Unit tests for database session lifecycle (commit-on-success, rollback-on-error)."""

from unittest.mock import AsyncMock, MagicMock

import pytest

from app.db import session as session_module


def _patch_session_local(monkeypatch: pytest.MonkeyPatch, mock_session: AsyncMock) -> None:
    mock_cm = MagicMock()

    async def _aenter(_self: object) -> AsyncMock:
        return mock_session

    async def _aexit(_self: object, *_args: object) -> None:
        return None

    mock_cm.__aenter__ = _aenter
    mock_cm.__aexit__ = _aexit
    monkeypatch.setattr(session_module, "AsyncSessionLocal", lambda: mock_cm)


@pytest.mark.asyncio
async def test_get_db_commits_on_success(monkeypatch: pytest.MonkeyPatch) -> None:
    mock_session = AsyncMock()
    _patch_session_local(monkeypatch, mock_session)

    gen = session_module.get_db()
    db = await gen.__anext__()
    assert db is mock_session

    with pytest.raises(StopAsyncIteration):
        await gen.__anext__()

    mock_session.commit.assert_awaited_once()
    mock_session.rollback.assert_not_awaited()


@pytest.mark.asyncio
async def test_get_db_rolls_back_on_error(monkeypatch: pytest.MonkeyPatch) -> None:
    mock_session = AsyncMock()
    _patch_session_local(monkeypatch, mock_session)

    gen = session_module.get_db()
    await gen.__anext__()

    with pytest.raises(RuntimeError, match="boom"):
        await gen.athrow(RuntimeError("boom"))

    mock_session.rollback.assert_awaited_once()
    mock_session.commit.assert_not_awaited()

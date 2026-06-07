"""Domain-specific exceptions. Register handlers in app/exception_handlers.py."""


class DomainError(Exception):
    """Base class for application errors (replace or extend per feature)."""

    pass


class NotesLimitExceeded(DomainError):
    """Raised when a user has reached the maximum allowed number of notes."""

    def __init__(self, limit: int) -> None:
        self.limit = limit
        super().__init__(f"Note limit of {limit} reached.")

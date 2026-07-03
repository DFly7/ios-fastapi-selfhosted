# SCAFFOLDING — not a real module. Safe to delete once you add your first service.
# It only marks where new service modules go; it defines nothing and is imported nowhere.
#
# Pattern: one file per use-case (e.g. invoice_service.py, notification_service.py).
# Services orchestrate one or more repositories and contain business logic.
# Inject dependencies (settings, clients) via function parameters rather than globals.
# Worked example: notes_service.py

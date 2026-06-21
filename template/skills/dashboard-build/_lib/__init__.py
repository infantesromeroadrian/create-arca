"""Internal helpers for skills/dashboard-build/parser-core.py.

Split out per the T11 constraint that parser-core.py stay <= 800 LOC. The
HTML template hydrator and a small set of dataclass + exception helpers live
here; the parser core itself owns the markdown -> JSON pipeline only.
"""

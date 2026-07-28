"""Deterministic, locally-administered MAC derived from a Koti device id.

Used only as this Device's own `connections` identifier (see entity.py) —
not used for any cross-integration Device merge (the Bluetooth proxy
registers its scanner directly under this same Device; see bluetooth.py).
"""

from __future__ import annotations


def mac_from(device_id: str) -> str:
    """Return a locally-administered MAC for `device_id`."""
    hex_part = (device_id + "0" * 12)[:12].upper()
    pairs = ["02"]
    for i in range(2, 12, 2):
        pairs.append(hex_part[i : i + 2])
    return ":".join(pairs)

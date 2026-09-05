import json

from .agents import enrich
from .catalog import import_catalog


async def seed_catalog(db, merchant):
    bases = [
        (
            "HDP",
            "Airwave Pro Wireless",
            "headphones",
            7499,
            4600,
            {"wireless": True, "battery_hours": 40, "weight_g": 210, "microphone": True},
            "Lightweight wireless headphones for gaming and office meetings. Clear microphone and long battery life.",
        ),
        (
            "MON",
            "Viewpoint 24 IPS",
            "monitors",
            12499,
            7800,
            {"size_inches": 24, "resolution": "1080p", "refresh_hz": 100},
            "Full HD IPS office monitor with HDMI and ergonomic stand.",
        ),
        (
            "KEY",
            "Keycraft Mechanical",
            "keyboards",
            3499,
            1900,
            {"wireless": True, "layout": "TKL"},
            "Compact wireless mechanical keyboard for office and gaming.",
        ),
        (
            "CHR",
            "Volt 65W GaN",
            "chargers",
            2499,
            1200,
            {"watts": 65, "connector": "USB-C"},
            "Compact USB-C fast charger for laptops and devices.",
        ),
        (
            "ADP",
            "Link Bluetooth 5.3",
            "adapters",
            499,
            200,
            {"wireless": True, "connector": "USB-A"},
            "Bluetooth adapter connects wireless headphones to an office PC.",
        ),
        (
            "MOU",
            "Glide Silent Mouse",
            "mice",
            1299,
            650,
            {"wireless": True, "weight_g": 70},
            "Light wireless office mouse with silent clicks.",
        ),
        (
            "LAP",
            "Workstation Air 14",
            "laptops",
            64999,
            45000,
            {"ram_gb": 16, "storage_gb": 512},
            "Portable office laptop with a 14-inch display and USB-C charging.",
        ),
        (
            "HDS",
            "Studio Wired Reference",
            "headphones",
            5499,
            3200,
            {"wireless": False, "weight_g": 280},
            "Wired studio headphones for detailed sound.",
        ),
        (
            "M32",
            "Viewpoint 32 QHD",
            "monitors",
            24999,
            16000,
            {"size_inches": 32, "resolution": "1440p"},
            "Large QHD productivity monitor with vivid IPS display.",
        ),
        (
            "HUB",
            "Dock Seven USB-C",
            "adapters",
            3999,
            2200,
            {"connector": "USB-C", "ports": 7},
            "Seven port USB-C dock with HDMI and USB accessories.",
        ),
    ]
    rows = []
    for variant in range(10):
        for prefix, name, category, price, cost, attributes, description in bases:
            rows.append(
                {
                    "sku": f"{prefix}-{variant + 1:03}",
                    "name": name + (f" · Series {variant + 1}" if variant else ""),
                    "category": category,
                    "price": price + variant * 100,
                    "cost": cost,
                    "stock": 0 if variant == 9 else 60 - variant * 3,
                    "attributes": attributes,
                    "description": description,
                    "delivery_days": 3 + variant % 3,
                    "return_days": 7,
                    "warranty": "1 year manufacturer warranty",
                    "compatibility": [f"HDP-{variant + 1:03}"]
                    if prefix == "ADP"
                    else ([f"LAP-{variant + 1:03}"] if prefix in ("HUB", "CHR") else []),
                }
            )
    result = import_catalog(db, merchant, json.dumps(rows).encode(), "sample.json")
    await enrich(db, merchant, result["product_ids"])
    return result

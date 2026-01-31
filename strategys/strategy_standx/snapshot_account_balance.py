#!/usr/bin/env python3
"""
StandX Account Snapshot Tool
- open orders
- positions
"""

import sys
import os
import json
import argparse
from decimal import Decimal
from datetime import datetime, timezone

# ---------- 路径处理 ----------
current_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.dirname(os.path.dirname(current_dir))
sys.path.insert(0, project_root)

import yaml
from adapters import create_adapter


# ---------- utils ----------
def load_config(config_file="config.yaml"):
    if not os.path.isabs(config_file):
        config_path = os.path.join(current_dir, config_file)
    else:
        config_path = config_file

    if not os.path.exists(config_path):
        raise FileNotFoundError(f"config not found: {config_path}")

    with open(config_path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def decimal_to_str(x):
    if isinstance(x, Decimal):
        return str(x)
    return x


# ---------- main ----------
def main():
    parser = argparse.ArgumentParser("StandX Snapshot")
    parser.add_argument("-c", "--config", default="config.yaml")
    parser.add_argument("--private_key", required=True)
    parser.add_argument("--account_id", required=False)
    args = parser.parse_args()

    account_id = args.account_id or "UNKNOWN"

    # ---------- load config ----------
    config = load_config(args.config)
    config["exchange"]["private_key"] = args.private_key

    SYMBOL = config["symbol"]

    adapter = create_adapter(config["exchange"])
    adapter.connect()

    snapshot = {
        "account_id": account_id,
        "symbol": SYMBOL,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "open_orders": [],
        "open_orders_count": 0,
        "positions": [],
        "position_summary": "FLAT",
        "balances": [],
        "balance_summary": "FLAT",
    }

    # ---------- open orders ----------
    try:
        orders = adapter.get_open_orders(symbol=SYMBOL)
        snapshot["open_orders_count"] = len(orders)

        for o in orders:
            snapshot["open_orders"].append({
                "order_id": str(o.order_id),
                "side": o.side,
                "price": decimal_to_str(o.price),
                "qty": decimal_to_str(o.quantity),
                "status": o.status,
            })
    except Exception as e:
        snapshot["open_orders_error"] = str(e)

    # ---------- positions ----------
    try:
        positions = adapter.get_positions(symbol=SYMBOL)
        if positions:
            summary = []
            for p in positions:
                snapshot["positions"].append({
                    "symbol": p.symbol,
                    "side": p.side,
                    "size": decimal_to_str(p.size),
                    "entry_price": decimal_to_str(p.entry_price),
                    "mark_price": decimal_to_str(p.mark_price),
                    "unrealized_pnl": decimal_to_str(p.unrealized_pnl),
                    "leverage": p.leverage,
                    "margin_mode": p.margin_mode,
                })
                summary.append(f"{p.side}:{p.size}:{p.unrealized_pnl}")
            snapshot["position_summary"] = ",".join(summary)
        else:
            snapshot["position_summary"] = "FLAT"
    except Exception as e:
        snapshot["positions_error"] = str(e)


        # ---------- balance ----------
    try:
        balances = adapter.get_balance()
        if balances:
            summary_b = []
            for b in balances:
                snapshot["balances"].append({
                    "total_balance": decimal_to_str(b.total_balance),
                    "available_balance": decimal_to_str(b.available_balance),
                    "equity": decimal_to_str(b.equity),
                    "margin_used": decimal_to_str(b.margin_used),
                    "margin_available": decimal_to_str(b.margin_available),
                })
                summary_b.append(f"{b.total_balance}:{b.available_balance}")
            snapshot["balance_summary"] = ",".join(summary_b)
        else:
            snapshot["balance_summary"] = "FLAT"
    except Exception as e:
        snapshot["balance_error"] = str(e)

    # ---------- output ----------
    print(json.dumps(snapshot, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(json.dumps({
            "error": str(e)
        }))
        sys.exit(1)

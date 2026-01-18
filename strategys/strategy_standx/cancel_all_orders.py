#!/usr/bin/env python3
"""
StandX 批量撤单脚本（生产版）
"""

import sys
import argparse
from decimal import Decimal

from adapters import create_adapter


STANDX_CANCEL_CONFIG = None
SYMBOL = None

def initialize_config(config):
    """初始化全局配置变量"""
    global STANDX_CONFIG, SYMBOL, GRID_CONFIG, RISK_CONFIG, CANCEL_STALE_ORDERS_CONFIG

    STANDX_CONFIG = config['exchange']
    SYMBOL = config['symbol']
    GRID_CONFIG = config['grid']
    RISK_CONFIG = config.get('risk', {})
    CANCEL_STALE_ORDERS_CONFIG = config.get('cancel_stale_orders', {})

def main():
    # 解析命令行参数
    parser = argparse.ArgumentParser(description='StandX 策略脚本')
    parser.add_argument(
        '-c', '--config',
        type=str,
        default='config.yaml',
        help='指定配置文件路径（默认: config.yaml）'
    )
    parser.add_argument("--private_key", type=str)
    parser.add_argument("--account_id",type=str,required=False,help="Logical account identifier, e.g. account_hp17")
    args = parser.parse_args()

    account_id = args.account_id or "UNKNOWN"
    print(f"[BOOT] account_id={account_id}")

    # 加载配置文件
    try:      
        config = load_config(args.config)
        # 在这里覆盖
        config["exchange"]["private_key"] = args.private_key      
        initialize_config(config)
    except FileNotFoundError as e:
        print(f"youryour error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"whywhywhy load config file failed: {e}")
        sys.exit(1)

    adapter = create_adapter(STANDX_CANCEL_CONFIG)
    adapter.connect()

    # 2. 查询 open orders（仅用于日志）
    open_orders = adapter.get_open_orders(symbol=args.symbol)

    if not open_orders:
        print(f"[{args.account}] no open orders")
        return
    # 3. 执行撤单
    adapter.cancel_all_orders(symbol=args.symbol)
    print(f"[{args.account}] cancel_all_orders done")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"[ERROR] {e}")
        sys.exit(1)

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

def load_config(config_file="config.yaml"):
    """
    加载配置文件
    
    Args:
        config_file: 配置文件路径，可以是相对路径或绝对路径
    
    Returns:
        dict: 配置字典
    """
    # 如果是相对路径，相对于脚本目录
    if not os.path.isabs(config_file):
        config_path = os.path.join(current_dir, config_file)
    else:
        config_path = config_file
    
    if not os.path.exists(config_path):
        raise FileNotFoundError(f"配置文件不存在: {config_path}")
    
    with open(config_path, 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)
    
    return config

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
    print(f"[BOOT] cancel account={args.account_id}")

    # 加载配置文件
    try:      
        config = load_config(args.config)
        # 在这里覆盖
        config["exchange"]["private_key"] = args.private_key      
        STANDX_CANCEL_CONFIG = config["exchange"]
        SYMBOL = config["symbol"]
    except FileNotFoundError as e:
        print(f"youryour error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"whywhywhy load config file failed: {e}")
        sys.exit(1)

    adapter = create_adapter(STANDX_CANCEL_CONFIG)
    adapter.connect()

    # 2. 查询 open orders（仅用于日志）
    open_orders = adapter.get_open_orders(symbol=SYMBOL)

    if not open_orders:
        print(f"[CANCEL] no open orders for {SYMBOL}")
        return
    print(f"[CANCEL] found {len(open_orders)} open orders")

    # 3. 执行撤单
    adapter.cancel_all_orders(symbol=SYMBOL)
    print(f"[CANCEL] cancel_all_orders done ({len(open_orders)} orders)")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"[ERROR] {e}")
        sys.exit(1)


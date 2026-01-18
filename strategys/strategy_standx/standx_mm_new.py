#!/usr/bin/env python3
"""
StandX 策略脚本 - 获取 BTC 价格
"""
import sys
import os
import yaml
import time
import random
import argparse
from decimal import Decimal
import logging

current_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.dirname(os.path.dirname(current_dir))
sys.path.insert(0, project_root)

from adapters import create_adapter
from risk import IndicatorTool

# 全局配置变量
STANDX_CONFIG = None
SYMBOL = None
GRID_CONFIG = None
RISK_CONFIG = None
CANCEL_STALE_ORDERS_CONFIG = None
account_id = None

# 来源chatgpt对话
POSITION_STATE = {
    "open_time": None,
    "last_reduce_time": None
}


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


def initialize_config(config):
    """初始化全局配置变量"""
    global STANDX_CONFIG, SYMBOL, GRID_CONFIG, RISK_CONFIG, CANCEL_STALE_ORDERS_CONFIG

    STANDX_CONFIG = config['exchange']
    SYMBOL = config['symbol']
    GRID_CONFIG = config['grid']
    RISK_CONFIG = config.get('risk', {})
    CANCEL_STALE_ORDERS_CONFIG = config.get('cancel_stale_orders', {})


def generate_grid_arrays(current_price, price_step, grid_count, price_spread):
    """根据当前价格和价格间距生成做多数组和做空数组，过滤超过当前价格上下1%的价格"""
    if price_step <= 0:
        raise ValueError("price_step 必须大于 0")
    if grid_count < 0:
        raise ValueError("grid_count 必须大于等于 0")
    if price_spread < 0:
        raise ValueError("price_spread 必须大于等于 0")
    
    # 计算价格上下限（当前价格的上下1%）
    price_upper_limit = current_price * 1.01  # 上限：当前价格 +1%
    price_lower_limit = current_price * 0.99   # 下限：当前价格 -1%
    
    # 计算 bid 和 ask 价格
    bid_price = current_price - price_spread
    ask_price = current_price + price_spread
    
    # 将 bid 价格向下取整到最近的 price_step 倍数
    bid_base = int(bid_price / price_step) * price_step
    
    # 将 ask 价格向上取整到最近的 price_step 倍数
    ask_base = int((ask_price + price_step - 1) / price_step) * price_step
    
    # 做多数组：从 bid_base 向下 grid_count 个（包括 bid_base）
    long_grid = []
    for i in range(grid_count):
        price = bid_base - i * price_step
        # 过滤：做多价格不能低于当前价格的1%（即不能低于 price_lower_limit）
        if price >= price_lower_limit:
            long_grid.append(price)
    long_grid = sorted(long_grid)
    
    # 做空数组：从 ask_base 向上 grid_count 个（包括 ask_base）
    short_grid = []
    for i in range(grid_count):
        price = ask_base + i * price_step
        # 过滤：做空价格不能超过当前价格的1%（即不能高于 price_upper_limit）
        if price <= price_upper_limit:
            short_grid.append(price)
    short_grid = sorted(short_grid)
    
    return long_grid, short_grid


def get_pending_orders_arrays(adapter, symbol):
    """获取当前账号未成交订单数组，按做多和做空分类，同时返回价格到订单ID的映射
    
    Returns:
        (long_prices, short_prices, long_price_to_ids, short_price_to_ids):
        - long_prices: 做多价格数组
        - short_prices: 做空价格数组
        - long_price_to_ids: 做多价格到订单ID列表的字典映射
        - short_price_to_ids: 做空价格到订单ID列表的字典映射
    """
    try:
        open_orders = adapter.get_open_orders(symbol=symbol)
        
        # 做多订单：side 为 "buy" 或 "long"
        long_prices = []
        long_price_to_ids = {}  # 价格 -> 订单ID列表
        # 做空订单：side 为 "sell" 或 "short"
        short_prices = []
        short_price_to_ids = {}  # 价格 -> 订单ID列表
        
        for order in open_orders:
            # 只处理未成交的订单（状态为 pending, open, partially_filled）
            if order.status in ["pending", "open", "partially_filled"]:
                if order.price is not None:
                    price = int(float(order.price))
                    try:
                        order_id = int(order.order_id)
                    except (ValueError, TypeError):
                        continue  # 跳过无效的订单ID
                    
                    if order.side in ["buy", "long"]:
                        if price not in long_prices:
                            long_prices.append(price)
                        if price not in long_price_to_ids:
                            long_price_to_ids[price] = []
                        long_price_to_ids[price].append(order_id)
                    elif order.side in ["sell", "short"]:
                        if price not in short_prices:
                            short_prices.append(price)
                        if price not in short_price_to_ids:
                            short_price_to_ids[price] = []
                        short_price_to_ids[price].append(order_id)
        
        return sorted(long_prices), sorted(short_prices), long_price_to_ids, short_price_to_ids
    except NotImplementedError:
        # 如果适配器未实现，返回空数组
        return [], [], {}, {}
    except Exception as e:
        return [], [], {}, {}


def cancel_stale_order_ids(adapter, symbol, stale_seconds=5, cancel_probability=0.5):
    """随机取消未成交时间大于指定秒数的订单
    
    Args:
        adapter: 适配器实例
        symbol: 交易对符号
        stale_seconds: 未成交时间阈值（秒），默认5秒
        cancel_probability: 取消概率（0-1之间），默认0.5（50%）
    """
    try:
        open_orders = adapter.get_open_orders(symbol=symbol)
        stale_order_ids = []
        current_time = int(time.time() * 1000)  # 当前时间（毫秒）
        
        for order in open_orders:
            # 只处理未成交的订单
            if order.status in ["pending", "open", "partially_filled"]:
                if order.created_at:
                    # 计算未成交时间（毫秒）
                    elapsed_time = current_time - order.created_at
                    if elapsed_time > stale_seconds * 1000:  # 转换为毫秒
                        # 根据概率决定是否取消
                        if random.random() < cancel_probability:
                            try:
                                order_id = int(order.order_id)
                                stale_order_ids.append(order_id)
                            except (ValueError, TypeError):
                                pass
        
        # 如果有需要取消的订单，执行批量撤单
        if stale_order_ids:
            try:
                if hasattr(adapter, 'cancel_orders_by_ids'):
                    adapter.cancel_orders_by_ids(order_id_list=stale_order_ids)
            except:
                pass
    except Exception:
        pass


def cancel_orders_by_prices(cancel_long, cancel_short, long_price_to_ids, short_price_to_ids, adapter):
    """根据价格列表撤单
    
    Args:
        cancel_long: 需要撤单的做多价格列表
        cancel_short: 需要撤单的做空价格列表
        long_price_to_ids: 做多价格到订单ID列表的字典映射
        short_price_to_ids: 做空价格到订单ID列表的字典映射
        adapter: 适配器实例
    """
    if not cancel_long and not cancel_short:
        return
    
    # 根据价格映射获取订单ID
    all_order_ids = []
    for price in cancel_long:
        if price in long_price_to_ids:
            all_order_ids.extend(long_price_to_ids[price])
    for price in cancel_short:
        if price in short_price_to_ids:
            all_order_ids.extend(short_price_to_ids[price])
    
    if not all_order_ids:
        return
    
    # 批量撤单
    try:
        if hasattr(adapter, 'cancel_orders_by_ids'):
            adapter.cancel_orders_by_ids(order_id_list=all_order_ids)
        else:
            # 如果适配器没有批量撤单方法，逐个撤单
            for order_id in all_order_ids:
                try:
                    adapter.cancel_order(order_id=str(order_id))
                except:
                    pass
    except:
        pass


def place_orders_by_prices(place_long, place_short, adapter, symbol, quantity):
    """根据价格列表下单
    
    Args:
        place_long: 需要下单的做多价格列表
        place_short: 需要下单的做空价格列表
        adapter: 适配器实例
        symbol: 交易对符号
        quantity: 订单数量
    """
    if not place_long and not place_short:
        return
    
    quantity_decimal = Decimal(str(quantity))
    
    # 做多订单：buy
    for price in place_long:
        try:
            order = adapter.place_order(
                symbol=symbol,
                side="buy",
                order_type="limit",
                quantity=quantity_decimal,
                price=Decimal(str(price)),
                time_in_force="gtc",
                reduce_only=False
            )
        except Exception as e:
            pass
    
    # 做空订单：sell
    for price in place_short:
        try:
            order = adapter.place_order(
                symbol=symbol,
                side="sell",
                order_type="limit",
                quantity=quantity_decimal,
                price=Decimal(str(price)),
                time_in_force="gtc",
                reduce_only=False
            )
        except Exception as e:
            pass


def calculate_cancel_orders(target_long, target_short, current_long, current_short):
    """计算需要撤单的多空数组
    
    Args:
        target_long: 目标做多数组（应该存在的订单价格）
        target_short: 目标做空数组（应该存在的订单价格）
        current_long: 当前做多数组（实际存在的订单价格）
        current_short: 当前做空数组（实际存在的订单价格）
    
    Returns:
        (cancel_long, cancel_short): 需要撤单的做多数组和做空数组
    """
    # 将目标数组转换为集合，便于查找
    target_long_set = set(target_long)
    target_short_set = set(target_short)
    
    # 撤单做多数组：在当前做多数组中，但不在目标做多数组中的价格
    cancel_long = [price for price in current_long if price not in target_long_set]
    
    # 撤单做空数组：在当前做空数组中，但不在目标做空数组中的价格
    cancel_short = [price for price in current_short if price not in target_short_set]
    
    return sorted(cancel_long), sorted(cancel_short)
# 新增-来源chatgpt对话
def calculate_maker_cancel_orders(current_long, current_short, last_price, price_spread, price_step):
    """
    Maker-only 撤单逻辑：只撤离现价过远、明显失效的订单
    """

    max_distance = price_spread + price_step * 2

    cancel_long = [
        p for p in current_long
        if abs(p - last_price) > max_distance
    ]

    cancel_short = [
        p for p in current_short
        if abs(p - last_price) > max_distance
    ]

    return sorted(cancel_long), sorted(cancel_short)

# 新增-来源chatgpt对话
def place_maker_close_orders(
    adapter,
    symbol,
    position,
    price_step,
    price_spread,
    close_ratio=0.3
):
    """
    Maker-only 平仓：
    用限价单，慢慢减仓，不制造 Taker 行为
    """

    size = abs(position.size)
    side = position.side  # long / short

    # 每次只平一部分
    close_size = (size * Decimal(str(close_ratio))).quantize(Decimal("0.0001"))
    if close_size <= Decimal("0"):
        return

    price_info = adapter.get_ticker(symbol)
    mid_price = (
        price_info.get("mark_price")
        or price_info.get("mid_price")
        or price_info.get("last_price")
    )

    if side in ["long", "buy"]:
        # 多头 → 挂卖单，价格高一点
        close_price = mid_price + price_spread + price_step
        close_side = "sell"
    else:
        # 空头 → 挂买单，价格低一点
        close_price = mid_price - price_spread - price_step
        close_side = "buy"

    try:
        adapter.place_order(
            symbol=symbol,
            side=close_side,
            order_type="limit",
            quantity=close_size,
            price=Decimal(str(int(close_price))),
            time_in_force="gtc",
            reduce_only=True
        )
        logging.info(
            "[MAKER-CLOSE] side=%s, price=%d, size=%s",
            close_side,
            int(close_price),
            close_size
        )
    except Exception as e:
        # print(f"[MAKER-CLOSE][FAIL] {e}")
        pass


def calculate_place_orders(target_long, target_short, current_long, current_short):
    """计算需要下单的多空数组
    
    Args:
        target_long: 目标做多数组（应该存在的订单价格）
        target_short: 目标做空数组（应该存在的订单价格）
        current_long: 当前做多数组（实际存在的订单价格）
        current_short: 当前做空数组（实际存在的订单价格）
    
    Returns:
        (place_long, place_short): 需要下单的做多数组和做空数组
    """
    # 将当前数组转换为集合，便于查找
    current_long_set = set(current_long)
    current_short_set = set(current_short)
    
    # 下单做多数组：在目标做多数组中，但不在当前做多数组中的价格
    place_long = [price for price in target_long if price not in current_long_set]
    
    # 下单做空数组：在目标做空数组中，但不在当前做空数组中的价格
    place_short = [price for price in target_short if price not in current_short_set]
    
    return sorted(place_long), sorted(place_short)


def close_position_if_exists(adapter, symbol):
    """检查持仓，如果有持仓则市价平仓
    
    注意: StandX 适配器的持仓查询接口可能未实现，此功能可能无法使用
    
    Args:
        adapter: 适配器实例
        symbol: 交易对符号
    """
    try:
        position = adapter.get_position(symbol)
        if position and position.size != Decimal("0"):
            # print(f"检测到持仓: {position.size} {position.side}, 市价平仓中...")
            adapter.close_position(symbol, order_type="market")
            # print("平仓完成")
        # 如果 position 为 None，说明 StandX 适配器的持仓查询接口可能未实现
    except Exception as e:
        # 如果持仓查询失败，静默处理（StandX 可能没有持仓查询接口）
        pass


def calculate_dynamic_price_spread(adx, current_price, default_spread, adx_threshold, adx_max=60):
    """根据 ADX 值动态计算 price_spread
    
    Args:
        adx: ADX 指标值
        current_price: 当前价格
        default_spread: 默认 price_spread
        adx_threshold: ADX 阈值，低于此值使用默认值（通常为25）
        adx_max: ADX 最大值，超过此值按此值处理（默认60）
    
    Returns:
        int: 计算后的 price_spread
    """
    max_spread = current_price * 0.01  # 最大为价格的1%
    
    if adx is not None:
        # print(f"ADX(5m): {adx:.2f}")
        # ADX <= threshold 时使用默认值
        if adx <= adx_threshold:
            price_spread = default_spread
        else:
            # 超过 60 按 60 处理
            effective_adx = min(adx, adx_max)
            # ADX 在 [threshold, 60] 范围内映射到 [默认值, 最大值]
            ratio = (effective_adx - adx_threshold) / (adx_max - adx_threshold)  # ADX 25-60 映射到 0-1
            dynamic_spread = default_spread + ratio * (max_spread - default_spread)
            price_spread = int(min(dynamic_spread, max_spread))
        # print(f"DAYNAMIC price_spread: {price_spread} (默认: {default_spread}, 最大: {int(max_spread)})")
        return price_spread
    else:
        # print(f"ADX(5m): ADX NOT GET USE DEFAULT price_spread: {default_spread}")
        return default_spread


def run_strategy_cycle(adapter):
    """
    Maker-only 策略循环
    目标：最大化 Maker Points
    """

    # ========= 1. 获取价格（优先 mark / mid） =========
    price_info = adapter.get_ticker(SYMBOL)
    last_price = (
        price_info.get('mark_price')
        or price_info.get('mid_price')
        or price_info.get('last_price')
    )

    # print(f"[PRICE] {SYMBOL}: {last_price:.2f}")

    # ========= 2. 计算 price_spread（保留你的 ADX 逻辑） =========
    default_spread = GRID_CONFIG['price_spread']

    if RISK_CONFIG.get('enable', False):
        indicator_tool = IndicatorTool()
        adx = indicator_tool.get_adx(SYMBOL, "5m", period=14)
        adx_threshold = RISK_CONFIG.get('adx_threshold', 25)
        price_spread = calculate_dynamic_price_spread(
            adx, last_price, default_spread, adx_threshold
        )
    else:
        price_spread = default_spread

    # ========= 3. 生成 Maker-friendly 网格 =========
    long_grid, short_grid = generate_grid_arrays(
        last_price,
        GRID_CONFIG['price_step'],
        GRID_CONFIG['grid_count'],
        price_spread
    )

    # print(f"long_grid: {long_grid}")
    # print(f"short_grid: {short_grid}")

    # ========= 4. 查询当前挂单 =========
    (
        long_pending,
        short_pending,
        long_price_to_ids,
        short_price_to_ids
    ) = get_pending_orders_arrays(adapter, SYMBOL)

    # print(f"current long_pending: {long_pending}")
    # print(f"current short_pending: {short_pending}")

    # ========= 5. Maker-only 撤单（极度保守） =========
    cancel_long, cancel_short = calculate_maker_cancel_orders(
        long_pending,
        short_pending,
        last_price,
        price_spread,
        GRID_CONFIG['price_step']
    )

    if cancel_long or cancel_short:
        # print(f"cancel_long: {cancel_long}")
        # print(f"cancel_short: {cancel_short}")
        # 执行撤单
        cancel_orders_by_prices(
            cancel_long,
            cancel_short,
            long_price_to_ids,
            short_price_to_ids,
            adapter
        )

    # ========= 6. 下单（只补缺，不抢盘口） =========
    place_long, place_short = calculate_place_orders(
        long_grid,
        short_grid,
        long_pending,
        short_pending
    )

    if place_long or place_short:
        # print(f"下单做多数组: {place_long}")
        # print(f"下单做空数组: {place_short}")
        place_orders_by_prices(
            place_long,
            place_short,
            adapter,
            SYMBOL,
            GRID_CONFIG.get('order_quantity', 0.0001)
        )

    # chatgpt最新一次对话
    # ========= 7. 持仓与风险控制（完整做市控制器） =========
    try:
        position = adapter.get_position(SYMBOL)
        now = time.time()

        if position and position.size != Decimal("0"):
            if POSITION_STATE["open_time"] is None:
                POSITION_STATE["open_time"] = now

            position_age = now - POSITION_STATE["open_time"]
            exposure = abs(position.size)

            # print(
            #     f"[HOLDING] size={position.size}, "
            #     f"age={int(position_age)}s, "
            #     f"trend={trend_state}"
            # )

            # --- 优先级 1：规模失控 ---
            if exposure > MAX_POSITION_SIZE:
                place_maker_close_orders(
                    adapter, SYMBOL, position,
                    GRID_CONFIG["price_step"],
                    price_spread,
                    close_ratio=0.5
                )

            # --- 优先级 2：时间过长 ---
            elif position_age > MAX_POSITION_AGE:
                if (
                    POSITION_STATE["last_reduce_time"] is None or
                    now - POSITION_STATE["last_reduce_time"] > REDUCE_INTERVAL
                ):
                    place_maker_close_orders(
                        adapter, SYMBOL, position,
                        GRID_CONFIG["price_step"],
                        price_spread,
                        close_ratio=0.3
                    )
                    POSITION_STATE["last_reduce_time"] = now

            # --- 优先级 3：趋势行情 ---
            elif trend_state == "trend":
                place_maker_close_orders(
                    adapter, SYMBOL, position,
                    GRID_CONFIG["price_step"],
                    price_spread,
                    close_ratio=0.4
                )

        else:
            POSITION_STATE["open_time"] = None
            POSITION_STATE["last_reduce_time"] = None

    except Exception:
        pass



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
    parser.add_argument("--price_spread", type=int, default=200)
    parser.add_argument("--upper_price", type=int, default=100000)
    parser.add_argument("--lower_price", type=int, default=90000)
    parser.add_argument("--price_step", type=int, default=20)
    parser.add_argument("--grid_count", type=int, default=5)
    parser.add_argument("--order_quantity", type=float, default=0.0001)
    parser.add_argument("--sleep_interval", type=int, default=5)
    parser.add_argument("--account_id",type=str,required=False,help="Logical account identifier, e.g. account_hp17")
    args = parser.parse_args()

    account_id = args.account_id or "UNKNOWN"
    print(f"[BOOT] account_id={account_id}")
    logging.basicConfig(
        filename=f"logs/{account_id}.log",
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s")

    # 加载配置文件
    try:
        # print(f"加载配置文件: {args.config}")
        
        config = load_config(args.config)
        # 在这里覆盖
        config["exchange"]["private_key"] = args.private_key
        config["grid"]["price_spread"] = args.price_spread
        config["grid"]["upper_price"] = args.upper_price
        config["grid"]["lower_price"] = args.lower_price
        config["grid"]["price_step"] = args.price_step
        config["grid"]["grid_count"] = args.grid_count
        config["grid"]["order_quantity"] = args.order_quantity
        config["grid"]["sleep_interval"] = args.sleep_interval
        
        initialize_config(config)
        
    except FileNotFoundError as e:
        print(f"youryour error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"whywhywhy load config file failed: {e}")
        sys.exit(1)
    
    try:
        adapter = create_adapter(STANDX_CONFIG)
        adapter.connect()
        
        print("begin begin la~~~~~~~~~~~~~")
        
        sleep_interval = GRID_CONFIG.get('sleep_interval', 60)
        
        while True:
            try:
                run_strategy_cycle(adapter)
                time.sleep(sleep_interval)
            except KeyboardInterrupt:
                print("\n\n weiweiwei the proc stop")
                break
            except Exception as e:
                print(f"weiweiwei proc cycle error: {e}")
                print(f"wait {sleep_interval} second reload...\n")
                time.sleep(sleep_interval)
        
    except Exception as e:
        print(f"youryour error: {e}")
        return None


if __name__ == "__main__":
    main()

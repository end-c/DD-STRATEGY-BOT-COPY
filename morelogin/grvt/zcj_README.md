# GRVT 自动化交易脚本使用说明

## 概述

`zcj.py` 是一个用于 GRVT 交易所的自动化交易脚本，支持：
- 批量打开多个 MoreLogin 浏览器配置文件
- 自动执行限价单和市价单交易
- 智能持仓管理和风险控制
- 使用统一的 Adapter 接口查询价格
- 自动复用已打开的页面，避免重复打开

## 功能特点

- ✅ **批量环境管理**：同时管理多个 MoreLogin 浏览器环境
- ✅ **页面智能复用**：自动检测并复用已打开的页面，提高效率
- ✅ **自动化交易**：支持限价单和市价单的自动下单
- ✅ **持仓监控**：定期检查持仓并自动处理
- ✅ **价格查询**：使用统一的 Adapter 接口获取实时价格
- ✅ **风险控制**：支持持仓检查和自动平仓
- ✅ **错误处理**：完善的异常处理和重试机制

## 安装依赖

```bash
pip install pyyaml playwright requests
playwright install chromium
```

## 配置说明

编辑 `config.yaml` 文件：

```yaml
# 环境ID列表（MoreLogin环境ID）
# 至少需要2个环境ID
env_ids:
  - "1923208407345078272"
  - "1923208407286358016"

# 交易对配置（二选一）
# 方式1: 使用交易对（推荐）- 自动构建URL
trading_pair: "XPL-USDT"  # 例如: "BTC-USDT", "XPL-USDT", "ETH-USDT"

# 方式2: 直接指定URL（可选）
# target_url: "https://grvt.io/exchange/perpetual/XPL-USDT"

# API配置
api:
  # MoreLogin API 基础URL
  base_url: "http://localhost:40000"
  # API请求超时时间（秒）
  timeout: 10
  # 关闭环境时的超时时间（秒）
  close_timeout: 2

# 浏览器配置
browser:
  # 页面加载超时时间（毫秒）
  page_load_timeout: 30000
  # 页面加载等待策略: "load" | "domcontentloaded" | "networkidle" | "commit"
  # "domcontentloaded" 更快，适合大多数场景
  # "networkidle" 最慢但最完整，等待所有网络请求完成
  wait_until: "domcontentloaded"

# 等待时间配置（秒）
delays:
  # 浏览器启动后的等待时间
  after_browser_start: 1
  # 打开下一个环境前的等待时间
  between_profiles: 0.5

# 交易配置
trading:
  # 限价单价格偏移量（在最佳买价基础上加的值）
  price_offset: 0.0001
  # 交易数量
  amount: 30
  # 持仓检查间隔（每N次循环检查一次持仓）
  position_check_interval: 3
```

### 配置项说明

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `env_ids` | MoreLogin 环境ID列表，至少需要2个 | 必填 |
| `trading_pair` | 交易对，如 "XPL-USDT" | 必填 |
| `api.base_url` | MoreLogin API 地址 | `http://localhost:40000` |
| `api.timeout` | API 请求超时时间（秒） | `10` |
| `browser.page_load_timeout` | 页面加载超时（毫秒） | `30000` |
| `browser.wait_until` | 页面加载策略 | `domcontentloaded` |
| `trading.price_offset` | 限价单价格偏移量 | `0.0001` |
| `trading.amount` | 每次交易数量 | `30` |
| `trading.position_check_interval` | 持仓检查间隔（循环次数） | `3` |

## 使用方法

### 1. 准备工作

- 确保 MoreLogin 客户端已启动并成功登录
- 确保 MoreLogin 版本 >= 2.32
- 获取你的环境ID（可以使用 `../MoreLogin-Python/list_browser_profiles.py`）

### 2. 配置环境ID和交易对

编辑 `config.yaml`，填写：
- `env_ids`: 至少2个环境ID
- `trading_pair`: 要交易的交易对，如 "XPL-USDT"

### 3. 运行脚本

```bash
cd morelogin/grvt
python zcj.py
```

### 4. 脚本行为

脚本会执行以下操作：

1. **启动环境**：依次启动所有配置的环境ID
2. **打开页面**：
   - 自动检测已打开的页面并复用（避免重复打开）
   - 如果没有已打开的页面，则创建新页面
3. **自动交易循环**：
   - 随机选择两个环境进行交易
   - 环境1：下限价单做多
   - 环境2：下市价单做空
4. **持仓检查**（每 N 次循环）：
   - 检查所有环境的持仓情况
   - 根据持仓自动处理：
     - **最后一个环境**：取消未成交订单后限价平仓
     - **其他环境**：当前环境限价单，下一个环境市价单对冲

### 5. 退出脚本

按 `Ctrl+C` 退出脚本。脚本退出时不会自动关闭浏览器环境（已注释关闭代码）。

## 核心功能

### 1. 页面复用机制

脚本会自动检测已打开的页面：

```python
# 优先复用已存在的页面
for ctx in browser.contexts:
    for pg in ctx.pages:
        if target_url in pg.url:
            pg.bring_to_front()  # 将页面置前
            return pg  # 复用现有页面
```

**优势**：
- 避免重复打开相同页面
- 提高启动速度
- 保留页面状态

### 2. 价格查询（使用 Adapter）

脚本使用统一的 Adapter 接口查询价格：

```python
# 使用 GRVT Adapter 获取价格
adapter = get_grvt_adapter()
ticker = adapter.get_ticker("XPL_USDT_Perp")
bid_price = ticker.get("bid_price")
ask_price = ticker.get("ask_price")
```

**优势**：
- 统一的接口，便于维护
- 支持多交易所切换
- 自动处理价格格式转换

### 3. 交易策略

#### 开仓策略
- **环境1**：限价单做多（在最佳买价基础上加偏移量）
- **环境2**：市价单做空（立即成交）

#### 持仓管理策略
- **持仓检查间隔**：每 N 次循环检查一次（可配置）
- **最后一个环境**：取消所有未成交订单后限价平仓
- **其他环境**：
  - 持仓为正：当前环境限价空单，下一个环境市价多单
  - 持仓为负：当前环境限价多单，下一个环境市价空单

### 4. 错误处理

- API 连接检查：启动前检查 MoreLogin API 是否可用
- 重试机制：价格查询和持仓检查支持重试
- 异常捕获：单个环境失败不影响其他环境

## 注意事项

### 1. 前置条件

- ✅ MoreLogin 客户端必须已启动
- ✅ 至少需要 2 个环境ID
- ✅ 确保环境ID有效且已登录
- ✅ 确保网络连接正常

### 2. 风险提示

⚠️ **重要提示**：
- 这是一个自动化交易脚本，请谨慎使用
- 建议先在测试环境或小额资金下测试
- 确保理解交易策略和风险
- 定期检查持仓和订单状态
- 建议设置止损和风险控制

### 3. 性能优化

- **页面复用**：已打开的页面会被自动复用，无需重复打开
- **等待策略**：使用 `domcontentloaded` 比 `networkidle` 更快
- **持仓检查间隔**：可根据需要调整 `position_check_interval`

### 4. 常见问题

**Q: 脚本提示"无法连接到 MoreLogin API"**
- A: 确保 MoreLogin 客户端已启动，默认端口 40000

**Q: 页面打开失败**
- A: 检查环境ID是否正确，网络是否正常

**Q: 价格查询失败**
- A: 检查网络连接，确保 GRVT 交易所可访问

**Q: 持仓检查不准确**
- A: 可能需要等待页面完全加载，或调整 `position_check_interval`

## 示例输出

```
打开 2 个环境...
✓ 1923208407345078272
✓ 1923208407286358016

成功: 2/2
按 Ctrl+C 退出

1环境ID: [1923208407345078272]
2环境ID: [1923208407286358016]

=== 第 1 次持仓检查 ===
  [1923208407345078272] 当前持仓: 30.0000
  [1923208407345078272] 限价空单: 30.0000
  [1923208407286358016] 市价多单: 30.0000
```

## 技术架构

- **Playwright**：浏览器自动化
- **MoreLogin API**：浏览器环境管理
- **Adapter 模式**：统一的交易所接口
- **YAML 配置**：灵活的配置管理

## 更新日志

- ✅ 支持页面自动复用
- ✅ 使用 Adapter 接口查询价格
- ✅ 支持持仓自动管理
- ✅ 完善的错误处理和重试机制

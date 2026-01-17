
from web3 import Web3
from eth_account import Account

# ⚠️ 必须开启（官方明确要求）
Account.enable_unaudited_hdwallet_features()

# 12 或 24 个助记词
MNEMONIC = ""

# 标准以太坊派生路径
DERIVATION_PATH = "m/44'/60'/0'/0/0"

"""
请帮我把这里单个MNEMONIC = ""改为从txt文件中读取，其中txt的格式如下：
account1:word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12
account2:word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12
account3:word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12
...


然后把生成的派生账户的private_key_hex_0x信息存入新txt,生成的txt格式如下：
account1:private_key_hex_0x
account2:private_key_hex_0x
account3:private_key_hex_0x
"""
# 从助记词派生账户
acct = Account.from_mnemonic(
    mnemonic=MNEMONIC,
    account_path=DERIVATION_PATH
)
# 私钥（hex 字符串，带 0x）
private_key_hex_0x = Web3.to_hex(acct.key)

print("私钥 hex (0x):", private_key_hex_0x)
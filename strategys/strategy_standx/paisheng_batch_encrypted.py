from web3 import Web3
from eth_account import Account
from cryptography.fernet import Fernet
import base64
import hashlib
import getpass
import os


# ⚠️ 必须开启（官方明确要求）
Account.enable_unaudited_hdwallet_features()

# 标准以太坊派生路径
DERIVATION_PATH = "m/44'/60'/0'/0/0"

# 当前脚本所在目录
current_dir = os.path.dirname(os.path.abspath(__file__))

# 输入 / 输出文件
MNEMONIC_FILE = os.path.join(current_dir, "mnemonics.txt")
ENCRYPTED_OUTPUT_FILE = os.path.join(current_dir, "private_keys.enc")

# ========= 安全核心 =========
def password_to_fernet_key(password: str) -> bytes:
    """
    使用 SHA256 将密码派生为 Fernet Key
    """
    digest = hashlib.sha256(password.encode()).digest()
    return base64.urlsafe_b64encode(digest)

def load_mnemonics(filepath: str) -> dict:
    """
    从 txt 读取助记词
    返回格式：
    {
        "account1": "word1 word2 ... word12",
        "account2": "word1 word2 ... word12"
    }
    """
    accounts = {}
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or ":" not in line:
                continue

            name, mnemonic = line.split(":", 1)
            accounts[name.strip()] = mnemonic.strip()

    return accounts


def derive_private_keys(accounts: dict) -> str:
    """
    派生私钥并拼成一个字符串（不落盘）
    """
    lines = []
    for name, mnemonic in accounts.items():
        acct = Account.from_mnemonic(
            mnemonic=mnemonic,
            account_path=DERIVATION_PATH
        )
        private_key_hex_0x = Web3.to_hex(acct.key)
        lines.append(f"{name}:{private_key_hex_0x}")
    return "\n".join(lines)


def encrypt_and_save(data: str, password: str, output_file: str):
    key = password_to_fernet_key(password)
    fernet = Fernet(key)
    encrypted = fernet.encrypt(data.encode())

    with open(output_file, "wb") as f:
        f.write(encrypted)


def prompt_password_twice() -> str:
    """
    安全地输入两次密码，必须一致
    """
    while True:
        pwd1 = getpass.getpass("请输入加密密码: ")
        pwd2 = getpass.getpass("请再次输入加密密码: ")

        if not pwd1:
            print("密码不能为空")
            continue

        if pwd1 != pwd2:
            print("两次密码不一致，请重试")
            continue

        return pwd1
    
if __name__ == "__main__":

    # ====== 1. 安全输入密码 ======
    password = prompt_password_twice()

    # ====== 2. 读取助记词（只存在内存）======
    mnemonic_accounts = load_mnemonics(MNEMONIC_FILE)

    # ====== 3. 派生私钥（只存在内存）======
    private_key_blob = derive_private_keys(mnemonic_accounts)

    # ====== 4. 加密并保存 ======
    encrypt_and_save(
        data=private_key_blob,
        password=password,
        output_file=ENCRYPTED_OUTPUT_FILE
    )

    # ====== 5. 内存清理（尽量）======
    del private_key_blob
    del mnemonic_accounts

    print(f"私钥已加密保存为 {os.path.basename(ENCRYPTED_OUTPUT_FILE)}")
    print("请立即删除 mnemonics.txt")

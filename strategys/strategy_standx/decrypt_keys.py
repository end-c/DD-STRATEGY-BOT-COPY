# decrypt_keys.py
import sys
import base64
import hashlib
import os
from cryptography.fernet import Fernet

TARGET_DIR = r"D:\google_downloads_3\DD-strategy-bot-main\strategys\strategy_standx"
ENC_FILE = os.path.join(TARGET_DIR,"private_keys.enc")

def password_to_key(password: str) -> bytes:
    return base64.urlsafe_b64encode(
        hashlib.sha256(password.encode()).digest()
    )

def main():
    if len(sys.argv) != 4:
        print("Usage: python decrypt_keys.py <password> <key_prefix> <index>", file=sys.stderr)
        sys.exit(1)

    password = sys.argv[1]
    key_prefix = sys.argv[2].strip()
    target_index = sys.argv[3].strip()

    ALLOWED_PREFIXES = {"account_hp", "account_hw","account_mac"}

    if key_prefix not in ALLOWED_PREFIXES:
        print(f"Invalid key prefix: {key_prefix}", file=sys.stderr)
        sys.exit(3)

    key_name = f"{key_prefix}{target_index}"

    key = password_to_key(password)
    fernet = Fernet(key)

    with open(ENC_FILE, "rb") as f:
        decrypted = fernet.decrypt(f.read()).decode()

    for line in decrypted.splitlines():
        if ":" not in line:
            continue
        index, pk = line.split(":", 1)
        if index.strip() == key_name:
            print(pk.strip())
            return

    sys.exit(2)  # index 不存在

if __name__ == "__main__":
    main()

## 运行
cd xxx
chmod +x run_prod_new.sh
cd ..

./RunScripts_mac/run_prod_new.sh account_mac 5-10


## 停止运行并撤单、平仓
./stop_and_cancel.sh account_mac 5-10

## 只是停止程序运行
# 进程层面
chmod +x stop.sh
./stop.sh

# 系统层面
杀掉所有 python 进程：pkill -9 -f python
查看 python 进程：  ps aux | grep python

## 查看状态
chmod +x status.sh

# 查看全部账户（一次性）
./RunScripts_mac/status.sh account_mac

# 查看指定账户
./RunScripts_mac/status.sh account_mac 12-14

# 实时刷新（每 3 秒）
./RunScripts_mac/status.sh account_mac 12-14 3
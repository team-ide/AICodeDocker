#!/bin/bash

# 移至脚本目录
cd `dirname $0`

echo `pwd`
arg1="$1"
arg2="$2"

port="9000"
host="0.0.0.0"
mkdir -p logs

# 添加启动命令
function start(){
    echo "start... arg2:$arg2"
    run_command="claude-code-webui --port $port --host $host"
    echo "----run command info start-----"
    echo "$run_command"
    echo "----run command info end-----"
    if [ "$arg2" = "-D" ]; then
      echo "后台启动"
      nohup $run_command \
            > logs/start.log \
            2>&1 \
            & echo $! > start.pid

      if [ $? -eq 0 ]; then
        cat start.pid
        echo "claude-code-webui started successfully!"
      else
        echo "claude-code-webui started failure!"
        exit 1
      fi
      return 0
    else
      echo "直接启动，非后台启动，如果需要后台启动，可以使用：./server.sh start -D"
      exec $run_command
    fi
}

# 添加停止命令
function stop(){
    echo "stop..."

    ps aux |grep claude-code-webui |grep -v grep |awk '{print "kill -15 " $2}'|sh
    sleep 3
    echo "stop successful"
    return 0
}

case $1 in
"start")
    start
    ;;
"stop")
    stop
    ;;
"restart")
    stop && start
    ;;
*)
    echo "请输入: start, stop, restart"
    ;;
esac
#/bin/sh

set -ex;


# 移至脚本目录
cd `dirname $0`

echo `pwd`

cd ../

currentDir=$(pwd)
echo "当前目录：$currentDir"


docker build -t teamide/ubuntu-node:1.2 -f Dockerfile-ubuntu-node-v1.2 .
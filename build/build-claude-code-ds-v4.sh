#/bin/sh

set -ex;


# 移至脚本目录
cd `dirname $0`

echo `pwd`

cd ../

currentDir=$(pwd)
echo "当前目录：$currentDir"


docker build -t teamide/claude-code-ds-v4:1.1 -f Dockerfile-claude-code-ds-v4-v1.1 .
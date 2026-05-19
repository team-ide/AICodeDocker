# 使用说明

* 拉取镜像

```shell

docker pull teamide/claude-code-ds-v4:1.1

```

* **宿主机 新建 ~/.claude.json 文件，如果已经了请忽略**

```shell
echo '{"hasCompletedOnboarding": true}' > ~/.claude.json
mkdir -p ~/.claude
```

* 后台启动

```shell
docker run -itd --name=claude-test \
    -v $(pwd):/data \
    -v ~/.claude:/root/.claude \
    -v ~/.claude.json:/root/.claude.json \
    -p 8765:8765 \
    -p 9000:9000 \
    --workdir=/data teamide/claude-code-ds-v4:1.1 bash
```


* 进入容器
```shell
docker exec -it claude-test bash
```

* 进入 容器后
  * 设置 DeepSeek API Key
    export ANTHROPIC_AUTH_TOKEN=<你的 DeepSeek API Key>
    `export ANTHROPIC_AUTH_TOKEN=`

  * 启动 claude
    `claude`

  * 启动 claude-code-webui
    `/opt/claude-code-webui/server.sh start -D`
    宿主机访问 `http://127.0.0.1:9000/`

  * 启动 claude web
    `/opt/claude-web/server.sh start -D`
    宿主机访问 `http://127.0.0.1:8765/`

* 如果报错
  * Unable to connect to Anthropic services
  * Failed to connect to api.anthropic.com: ERR_BAD_REQUEST

  * 因为claude code首次启动时会检查用户地区
  * 修改 ~/.claude.json
  * 添加 "hasCompletedOnboarding": true

* docker stop claude-test
* docker rm claude-test
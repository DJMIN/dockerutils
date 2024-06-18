#!/bin/bash

# 获取当前目录下的 .py 文件列表
PY_FILES=($(ls *.py))

# 检查是否有 .py 文件
if [ ${#PY_FILES[@]} -eq 0 ]; then
  echo "当前目录下没有 .py 文件。"
  exit 1
fi

# 提供 .py 文件选择菜单
echo "请选择要打包的 .py 文件："
select FASTAPI_FILE in "${PY_FILES[@]}"; do
  if [ -n "$FASTAPI_FILE" ]; then
    echo "选择的文件是：$FASTAPI_FILE"
    break
  else
    echo "无效的选择，请重新选择。"
  fi
done

# 提示用户输入新的镜像名
read -p "请输入新的镜像名（留空则使用文件名）：" NEW_IMAGE_NAME

# 定义镜像名称和标签
if [ -z "$NEW_IMAGE_NAME" ]; then
  IMAGE_NAME=$(echo $FASTAPI_FILE | cut -d'.' -f1)
else
  IMAGE_NAME=$NEW_IMAGE_NAME
fi
IMAGE_TAG="latest"

# 定义镜像仓库地址
REGISTRY="192.168.0.90:8080"

# 分析 Python 文件中的第三方库依赖
echo "正在分析第三方库依赖..."
REQUIREMENTS=$(grep -E '^(from|import)' $FASTAPI_FILE | grep -oE '^\s*(from|import)\s+([a-zA-Z0-9_]+)' | grep -vE '^\s*(from|import)\s+(traceback|logging|uuid|hashlib|pathlib|base64|OpenSSL|os|sys|json|typing|argparse|re|random|itertools|time|threading|queue|datetime|socket)' | sed -E 's/^\s*(from|import)\s+//g' | sort -u)

# 固定添加fastapi、pyOpenSSL和guesstime三个库
FIXED_REQUIREMENTS="fastapi pyOpenSSL guesstime itsdangerous"
REQUIREMENTS="$REQUIREMENTS $FIXED_REQUIREMENTS"

# 去重并按字母顺序排序
REQUIREMENTS=$(echo "$REQUIREMENTS" | tr ' ' '\n' | sort -u)

# 生成 requirements.txt 文件
echo "正在生成 requirements.txt 文件..."
echo "$REQUIREMENTS" > requirements.txt

# 生成 Dockerfile
echo "正在生成 Dockerfile..."
cat > Dockerfile <<EOF
FROM python:3.11.6-slim

WORKDIR /app

COPY $FASTAPI_FILE .

RUN apt-get update
RUN apt-get install -y vim net-tools procps iputils-ping dnsutils curl wget nano
RUN apt-get install -y less iproute2 tcpdump
RUN apt-get install -y strace lsof telnet sysstat
RUN apt-get install -y htop iotop nethogs iftop lshw
RUN apt-get install -y fdisk
RUN apt-get install -y smartmontools
RUN apt-get install -y gdb
RUN apt-get install -y screen 
#valgrind stress
RUN apt-get install -y gcc python3-dev
RUN rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

CMD ["python3.11", "$FASTAPI_FILE"]
#CMD ["uvicorn", "$FASTAPI_FILE:app", "--host", "0.0.0.0", "--port", "80"]
EOF

# 构建 Docker 镜像
echo "正在构建 Docker 镜像..."
docker build -t $IMAGE_NAME:$IMAGE_TAG .

# 提供可选菜单上传镜像到服务器
echo "是否上传镜像到服务器 $REGISTRY？"
select choice in "是" "否"; do
  case $choice in
    是 )
      echo "正在上传镜像到服务器 $REGISTRY..."
      docker tag $IMAGE_NAME:$IMAGE_TAG $REGISTRY/$IMAGE_NAME:$IMAGE_TAG
      docker push $REGISTRY/$IMAGE_NAME:$IMAGE_TAG
      break;;
    否 )
      echo "镜像构建完成，未上传到服务器。"
      break;;
  esac
done

echo "打包完成！"


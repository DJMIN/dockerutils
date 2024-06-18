#!/bin/bash

# 检查参数数量
if [ $# -ne 3 ]; then
  echo "使用方法: $0 <image_name> <image_tag> <local_registry>"
  exit 1
fi

# 获取命令行参数
image_name=$1
image_tag=$2
local_registry=$3

# 拉取镜像
echo "正在从Docker Hub拉取镜像..."
docker pull "$image_name:$image_tag"

# 给镜像打标签
echo "正在给镜像打标签..."
docker tag "$image_name:$image_tag" "$local_registry/$image_name:$image_tag"

# 推送镜像到本地仓库
echo "正在推送镜像到本地仓库..."
docker push "$local_registry/$image_name:$image_tag"

echo "完成！"

#!/bin/bash

# 定义颜色常量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查是否安装了 jq
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}未检测到 jq 命令,正在自动安装...${NC}"
    if command -v apt-get &> /dev/null; then
        # Debian/Ubuntu
        sudo apt-get update
        sudo apt-get install -y jq
    elif command -v yum &> /dev/null; then
        # CentOS/RHEL
        sudo yum install -y jq
    elif command -v brew &> /dev/null; then
        # macOS with Homebrew
        brew install jq
    else
        echo -e "${RED}无法自动安装 jq,请手动安装后再运行脚本。${NC}"
        exit 1
    fi
fi

# 显示标题
echo -e "${YELLOW}===================================${NC}"
echo -e "${YELLOW}     Docker 容器导入导出工具      ${NC}"
echo -e "${YELLOW}===================================${NC}"

# 显示菜单选项
echo -e "${BLUE}请选择操作：${NC}"
echo -e "1. 导出容器"
echo -e "2. 导入容器"
echo -e "3. 通过 scp 传输文件"
echo -e "4. 退出"

# 读取用户选择
read -p "请输入选项 [1-4]: " choice

case $choice in
    1)
        # 导出容器
        echo -e "${GREEN}正在导出容器...${NC}"

        # 列出可导出的容器
        echo -e "${BLUE}可导出的容器列表：${NC}"
        docker ps -a --format "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Ports}}"

        read -p "请输入要导出的容器ID: " container_id
        read -p "请输入导出的镜像名称: " image_name
        read -p "请输入导出的镜像标签: " image_tag

        mkdir -p docker_img

        # 判断是否已有指定的镜像名称
        if docker images | grep -q "$image_name"; then
            echo -e "${YELLOW}镜像 $image_name 已存在，跳过提交容器步骤。${NC}"
        else
            echo -e "${BLUE}正在提交容器...${NC}"
            docker commit $container_id $image_name:$image_tag
        fi

        echo -e "${BLUE}正在保存镜像...${NC}"
        docker save $image_name:$image_tag | pv -pterb -s $(docker image ls -q $image_name:$image_tag --format "{{.Size}}") > docker_img/$image_name-$image_tag.tar

        echo -e "${BLUE}正在导出容器启动命令参数...${NC}"
        container_info=$(docker inspect $container_id)
        mounts=$(echo "$container_info" | jq -r '.[0].Mounts[] | "--volume \(.Source):\(.Destination)"')
        ports=$(echo "$container_info" | jq -r '.[0].NetworkSettings.Ports | to_entries[] | "--publish \(.key):\(.value[0].HostPort)"')

        if echo "$container_info" | jq -e '.[0].Config.Tty' >/dev/null 2>&1; then
            tty_option="-t"
        else
            tty_option=""
        fi

        if echo "$container_info" | jq -e '.[0].Config.OpenStdin' >/dev/null 2>&1; then
            stdin_option="-i"
        else
            stdin_option=""
        fi

        command_options="docker run -d $tty_option $stdin_option $mounts $ports --name <container_name> $image_name:$image_tag"
        echo "$command_options" > docker_img/$image_name-$image_tag.cmd

        echo -e "${GREEN}容器导出完成！${NC}"
        echo -e "导出的文件路径为: ${YELLOW}$(pwd)/docker_img/$image_name-$image_tag.tar${NC}"
        echo -e "导出的启动命令参数文件路径为: ${YELLOW}$(pwd)/docker_img/$image_name-$image_tag.cmd${NC}"
        ;;
    2)
        # 导入容器
        echo -e "${GREEN}正在导入容器...${NC}"

        # 列出 docker_img 目录下的 .tar 文件
        echo -e "${BLUE}可导入的 .tar 文件列表：${NC}"
        ls -1 docker_img/*.tar 2>/dev/null | cat -n

        read -p "请输入要导入的 .tar 文件编号（留空则手动输入路径）: " file_number
        if [ -z "$file_number" ]; then
            read -p "请输入要导入的 .tar 文件路径: " tar_file
        else
            tar_file=$(ls -1 docker_img/*.tar 2>/dev/null | sed -n "${file_number}p")
        fi

        echo -e "${BLUE}正在加载镜像...${NC}"
        pv $tar_file | docker load

        # 获取镜像名称和标签
        image_name_tag=$(docker images --format "{{.Repository}}:{{.Tag}}" | head -1)

        # 检查是否存在对应的 .cmd 文件
        cmd_file="${tar_file%.tar}.cmd"
        if [ -f "$cmd_file" ]; then
            echo -e "${BLUE}发现容器启动命令参数文件，将使用该文件中的参数创建容器...${NC}"

            # 读取 .cmd 文件中的命令参数
            command_options=$(cat "$cmd_file")

            read -p "请输入导入后的容器名称: " container_name

            # 将 <container_name> 替换为实际的容器名称
            command_options="${command_options/<container_name>/$container_name}"

            echo -e "${BLUE}正在创建容器...${NC}"
            eval $command_options
        else
            echo -e "${YELLOW}未找到容器启动命令参数文件，将使用默认参数创建容器...${NC}"

            read -p "请输入导入后的容器名称: " container_name

            echo -e "${BLUE}正在创建容器...${NC}"
            docker run -d --name $container_name $image_name_tag
        fi

        echo -e "${GREEN}容器导入完成！${NC}"
        echo -e "容器名称为: ${YELLOW}$container_name${NC}"
        ;;
    3)
        # 通过 scp 传输文件
        echo -e "${GREEN}正在通过 scp 传输文件...${NC}"

        # 列出 docker_img 目录下的 .tar 文件
        echo -e "${BLUE}可传输的 .tar 文件列表：${NC}"
        ls -1 docker_img/*.tar 2>/dev/null | cat -n

        read -p "请输入要传输的 .tar 文件编号（留空则手动输入路径）: " file_number
        if [ -z "$file_number" ]; then
            read -p "请输入要传输的文件路径: " file_path
        else
            file_path=$(ls -1 docker_img/*.tar 2>/dev/null | sed -n "${file_number}p")
        fi

        read -p "请输入远程服务器的用户名: " remote_user
        read -p "请输入远程服务器的主机名或IP: " remote_host
        read -p "请输入远程服务器的目标路径: " remote_path

        echo -e "${BLUE}正在通过scp传输文件...${NC}"
        scp $file_path $remote_user@$remote_host:$remote_path

        # 检查是否存在对应的 .cmd 文件
        cmd_file="${file_path%.tar}.cmd"
        if [ -f "$cmd_file" ]; then
            echo -e "${BLUE}正在通过scp传输容器启动命令参数文件...${NC}"
            scp $cmd_file $remote_user@$remote_host:$remote_path
        fi

        echo -e "${GREEN}文件传输完成！${NC}"
        ;;
    4)
        # 退出
        echo -e "${RED}正在退出...${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}无效的选项！${NC}"
        ;;
esac
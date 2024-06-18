# 1.VPS 启动docker镜像服务
```shell
docker run -d -p 55575:5000 --restart always --name registry registry:2
```

# 2.VPS 上拉取镜像并上传到docker镜像服务端口55575
```shell
chmod -X push_image.sh
./push_image.sh python 3.11.6-slim localhost:55575
```

# 3.本地服务器配置docker镜像服务器认证
```shell
vim /etc/docker/daemon.json
```
添加参数：
```json
{
  // ... 其余保留
  "insecure-registries" : ["VPS的IP:55575"]
}
```
重启docker服务
```shell
sudo systemctl restart docker
```

# 4.开始拉取镜像
```shell
docker pull VPS的IP:55575/python:3.11.6-slim
```

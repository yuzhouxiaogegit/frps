#!/bin/bash

# ==================================================
#	系统要求：CentOS 6/7/8
#	描述：视频推流脚本
#	版本：1.0
#	作者：宇宙小哥
# 	github：https://github.com/yzhouxiaogegit/frps
# ==================================================

read -p "请输入bind_port端口(默认：7000)：" bind_port

read -p "请输入vhost_http_port端口(默认：7080):" vhost_http_port

if [[ $bind_port = '' ]]; 
then
bind_port=7000
fi

if [[ $vhost_http_port = '' ]]; 
then
vhost_http_port=7080
fi

#获取frp 最新版本号
getFrpV=$(wget -qO- https://github.com/fatedier/frp/releases/latest | grep "<title>" |sed -r 's/.*Release (.+) · fatedier.*/\1/')

#删除v字符串保留完整版本号
getFrpV=${getFrpV: 1}

#从github中下载 frp
wget https://github.com/fatedier/frp/releases/download/v${getFrpV}/frp_${getFrpV}_linux_amd64.tar.gz

#解压frp
tar -xzvf frp_${getFrpV}_linux_amd64.tar.gz

#创建frp 安装目录
rm -rf /usr/local/frps/
mkdir -p /usr/local/frps

#移动到frp 安装目录
mv frp_${getFrpV}_linux_amd64 frps
mv frps /usr/local

#删除frp压缩包
rm -rf frp_${getFrpV}_linux_amd64.tar.gz

#添加frp进系统服务
echo '[Unit]
Description = frps
After = network.target syslog.target
Wants = network.target

[Service]
Type = simple
ExecStart = /usr/local/frps/frps -c /usr/local/frps/frps.ini

[Install]
WantedBy = multi-user.target' > /etc/systemd/system/frps.service

#生成uuid
token=$(cat /proc/sys/kernel/random/uuid)

#生成配置文件
echo "[common]
bind_port = ${bind_port}
token = ${token}
vhost_http_port = ${vhost_http_port}
vhost_https_port = ${vhost_https_port}" > /usr/local/frps/frps.ini

#重载服务
systemctl daemon-reload

#查看frps启动状态
systemctl start frps.service

#设置frps开机启动
systemctl enable frps.service

# 查看frp状态
systemctl status frps.service


# 打印文字颜色方法
echoTxtColor(){
	
	colorV="1"
	
	if [[ $2 = 'red' ]];
	then
		colorV="1"
	elif [[ $2 = 'green' ]];
	then
		colorV="2"
	elif [[ $2 = 'yellow' ]];
	then
		colorV="3"
	fi
	
	echo -e "\033[3${colorV}m ${1} \033[0m"
}
# 调用示例

echo "
	frps.ini配置内容

	bind_port = ${bind_port}
	token = ${token}
	vhost_http_port = ${vhost_http_port}

	配置目录：/usr/local/frps/frps.ini
"

echoTxtColor "frp安装成功！" "green"; echoTxtColor "请手动开放 ${bind_port},${vhost_http_port} 端口后进行使用" "yellow"


exit

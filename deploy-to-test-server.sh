#!/bin/bash
set -e

# 配置
SERVER="91.233.10.29"
PORT="22"
USER="root"
PASSWORD="IJWwgsZTd8peVX7G1Is7"

# 本地项目路径
LOCAL_PROJECT="/Users/jack/Library/Mobile Documents/iCloud~md~obsidian/Documents/Jack Luo/开发平台/智谱/Fork-Nft"
REMOTE_DIR="/root/Fork-Nft"

echo "开始部署到测试服务器 $SERVER..."

# 1. 在远程服务器上准备目录
echo "准备远程目录..."
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -p $PORT $USER@$SERVER "mkdir -p $REMOTE_DIR && rm -rf $REMOTE_DIR/*"

# 2. 同步代码到远程服务器（使用 tar + ssh，避免 rsync 依赖）
echo "同步代码到远程服务器..."
cd "$LOCAL_PROJECT"
tar --exclude='node_modules' \
    --exclude='.git' \
    --exclude='dist' \
    --exclude='*.log' \
    -czf - . | sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -p $PORT $USER@$SERVER "cd $REMOTE_DIR && tar -xzf -"

# 3. 在远程服务器上构建后端
echo "在远程服务器上构建后端..."
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -p $PORT $USER@$SERVER << 'ENDSSH'
cd /root/Fork-Nft/go-backend
docker build -t fork-nft-backend:latest .
ENDSSH

# 4. 在远程服务器上构建前端
echo "在远程服务器上构建前端..."
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -p $PORT $USER@$SERVER << 'ENDSSH'
cd /root/Fork-Nft/vite-frontend
docker build -t fork-nft-frontend:latest .
ENDSSH

# 5. 部署服务
echo "部署服务..."
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -p $PORT $USER@$SERVER << 'ENDSSH'
cd /root/Fork-Nft

# 创建 docker-compose.override.yml
cat > docker-compose.override.yml << 'YAML'
services:
  backend:
    image: fork-nft-backend:latest
  frontend:
    image: fork-nft-frontend:latest
YAML

# 停止现有服务
docker compose -f docker-compose-v4.yml -f docker-compose.override.yml down || true

# 启动服务
docker compose -f docker-compose-v4.yml -f docker-compose.override.yml up -d

# 等待服务启动
sleep 10

# 检查服务状态
docker compose -f docker-compose-v4.yml -f docker-compose.override.yml ps
ENDSSH

echo "部署完成！"
echo "前端访问地址: http://$SERVER:6366/"
echo "后端 API 地址: http://$SERVER:6365/"

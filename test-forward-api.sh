#!/bin/bash

# Fork-Nft API 测试脚本
# 测试转发模式和协议功能

BASE_URL="http://91.233.10.29:6365"
USERNAME="admin_user"
PASSWORD="admin_user"

echo "=========================================="
echo "Fork-Nft API 测试"
echo "=========================================="

# 1. 登录获取 token
echo ""
echo "1. 登录..."
LOGIN_RESPONSE=$(curl -s -X POST "$BASE_URL/api/user/login" \
  -H "Content-Type: application/json" \
  -d "{\"userName\":\"$USERNAME\",\"password\":\"$PASSWORD\"}")

echo "登录响应: $LOGIN_RESPONSE"

TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
  echo "错误：无法获取 token"
  echo "请检查登录凭据"
  exit 1
fi

echo "Token: $TOKEN"
echo "登录成功！"

# 2. 检查隧道列表
echo ""
echo "2. 获取隧道列表..."
TUNNELS=$(curl -s -X GET "$BASE_URL/api/tunnel/list" \
  -H "Authorization: $TOKEN")
echo "隧道列表: $TUNNELS"

# 检查是否有隧道
TUNNEL_ID=$(echo "$TUNNELS" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
if [ -z "$TUNNEL_ID" ]; then
  echo "警告：没有找到隧道，请先创建隧道"
  exit 1
fi

echo "使用隧道 ID: $TUNNEL_ID"

# 3. 创建端口转发（TCP）
echo ""
echo "3. 创建端口转发（TCP，port_forward）..."
FORWARD1=$(curl -s -X POST "$BASE_URL/api/forward/create" \
  -H "Authorization: $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"测试-TCP-端口转发\",
    \"tunnelId\": $TUNNEL_ID,
    \"remoteAddr\": \"1.1.1.1:80\",
    \"strategy\": \"fifo\",
    \"engine\": \"auto\",
    \"forwardType\": \"port_forward\",
    \"protocols\": \"tcp\"
  }")

echo "创建结果: $FORWARD1"

# 4. 创建 UDP 转发
echo ""
echo "4. 创建 UDP 转发（tunnel_forward）..."
FORWARD2=$(curl -s -X POST "$BASE_URL/api/forward/create" \
  -H "Authorization: $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"测试-UDP-隧道转发\",
    \"tunnelId\": $TUNNEL_ID,
    \"remoteAddr\": \"1.1.1.2:80\",
    \"strategy\": \"round\",
    \"engine\": \"auto\",
    \"forwardType\": \"tunnel_forward\",
    \"protocols\": \"udp\"
  }")

echo "创建结果: $FORWARD2"

# 5. 创建 TCP+UDP 转发
echo ""
echo "5. 创建 TCP+UDP 转发（port_forward）..."
FORWARD3=$(curl -s -X POST "$BASE_URL/api/forward/create" \
  -H "Authorization: $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"测试-TCP+UDP-端口转发\",
    \"tunnelId\": $TUNNEL_ID,
    \"remoteAddr\": \"1.1.1.3:80\",
    \"strategy\": \"fifo\",
    \"engine\": \"auto\",
    \"forwardType\": \"port_forward\",
    \"protocols\": \"both\"
  }")

echo "创建结果: $FORWARD3"

# 6. 查询转发列表，验证 forwardType 和 protocols 字段
echo ""
echo "6. 查询转发列表..."
FORWARDS=$(curl -s -X GET "$BASE_URL/api/forward/list" \
  -H "Authorization: $TOKEN")

echo "转发列表: $FORWARDS"

# 检查是否包含 forwardType 和 protocols 字段
if echo "$FORWARDS" | grep -q "forwardType"; then
  echo "✅ forwardType 字段存在"
else
  echo "❌ forwardType 字段缺失"
fi

if echo "$FORWARDS" | grep -q "protocols"; then
  echo "✅ protocols 字段存在"
else
  echo "❌ protocols 字段缺失"
fi

echo ""
echo "=========================================="
echo "测试完成"
echo "=========================================="
echo ""
echo "请访问前端页面验证显示："
echo "http://91.233.10.29:6366/"
echo ""
echo "检查项："
echo "1. 转发列表是否显示模式列（端口/隧道）"
echo "2. 转发列表是否显示协议列（TCP/UDP/TCP+UDP）"
echo "3. 创建/编辑表单是否有转发模式和协议选择"

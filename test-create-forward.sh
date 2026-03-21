#!/bin/bash

# Fork-Nft 创建测试转发脚本
# 使用 VLESS 服务器作为目标进行测试

BASE_URL="http://91.233.10.29:32768"

# VLESS 服务器配置（作为目标）
TARGET_SERVER="45.141.36.130:80"

echo "=========================================="
echo "Fork-Nft 测试转发创建"
echo "=========================================="
echo ""
echo "目标服务器：$TARGET_SERVER"
echo ""

# 1. 创建测试用户
echo "1. 创建测试用户..."
CREATE_USER_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/user/create" \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"test_user\",\"pwd\":\"test_user123\",\"quota\":107374182400}")

echo "创建用户响应: $CREATE_USER_RESPONSE"

# 2. 登录获取 token
echo ""
echo "2. 登录..."
LOGIN_RESPONSE=$(curl -s -X POST "$BASE_URL/api/user/login" \
  -H "Content-Type: application/json" \
  -d "{\"userName\":\"test_user\",\"password\":\"test_user123\"}")

echo "登录响应: $LOGIN_RESPONSE"

TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"token":"[^"]*' | sed 's/.*"token":"//;s/".*//')

if [ -z "$TOKEN" ]; then
  echo "错误：无法获取 token"
  echo "响应：$LOGIN_RESPONSE"
  exit 1
fi

echo "Token: ${TOKEN:0:20}..."
echo "登录成功！"
echo ""

# 3. 创建节点（使用 VLESS 服务器）
echo "3. 创建节点..."
NODE_RESPONSE=$(curl -s -X POST "$BASE_URL/api/node/create" \
  -H "Authorization: $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"德国无聊云-NAT2\",
    \"host\": \"45.141.36.130\",
    \"port\": 59746,
    \"type\": \"vless\",
    \"tcp\": {
      \"type\": \"tcp\",
      \"encryption\": \"none\",
      \"security\": \"reality\",
      \"pbk\": \"Smfr6VO2aXRHX8pbppbD1UBfkb7JF1lrJ8pZlicuNmE\",
      \"fp\": \"chrome\",
      \"sni\": \"www.icloud.com\",
      \"sid\": \"15e94ba2e3\",
      \"spx\": \"%2F\",
      \"flow\": \"xtls-rprx-vision\"
    },
    \"engine\": \"auto\"
  }")

echo "节点创建响应: $NODE_RESPONSE"

# 提取节点 ID
NODE_ID=$(echo "$NODE_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
if [ -z "$NODE_ID" ]; then
  echo "错误：无法创建节点"
  echo "可能节点已存在，尝试获取现有节点"
  # 尝试获取现有节点
  NODES=$(curl -s -X GET "$BASE_URL/api/node/list" -H "Authorization: $TOKEN")
  echo "现有节点: $NODES"
  NODE_ID=$(echo "$NODES" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
fi

echo "节点 ID: $NODE_ID"
echo ""

# 4. 创建隧道
echo "4. 创建隧道..."
TUNNEL_RESPONSE=$(curl -s -X POST "$BASE_URL/api/tunnel/create" \
  -H "Authorization: $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"测试隧道\",
    \"entryNodeIds\": [$NODE_ID],
    \"protocol\": \"vless\",
    \"trafficRatio\": 1.0
  }")

echo "隧道创建响应: $TUNNEL_RESPONSE"

# 提取隧道 ID
TUNNEL_ID=$(echo "$TUNNEL_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
if [ -z "$TUNNEL_ID" ]; then
  echo "错误：无法创建隧道"
  echo "可能隧道已存在，尝试获取现有隧道"
  # 尝试获取现有隧道
  TUNNELS=$(curl -s -X GET "$BASE_URL/api/tunnel/list" -H "Authorization: $TOKEN")
  echo "现有隧道: $TUNNELS"
  TUNNEL_ID=$(echo "$TUNNELS" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
fi

echo "隧道 ID: $TUNNEL_ID"
echo ""

# 5. 创建端口转发（TCP）
echo "5. 创建端口转发（TCP，port_forward）..."
FORWARD1=$(curl -s -X POST "$BASE_URL/api/forward/create" \
  -H "Authorization: $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"测试-TCP-端口转发\",
    \"tunnelId\": $TUNNEL_ID,
    \"remoteAddr\": \"$TARGET_SERVER\",
    \"strategy\": \"fifo\",
    \"engine\": \"auto\",
    \"forwardType\": \"port_forward\",
    \"protocols\": \"tcp\",
    \"inx\": 1
  }")

echo "创建结果: $FORWARD1"
echo ""

# 6. 创建 UDP 转发（隧道转发）
echo "6. 创建 UDP 转发（tunnel_forward）..."
FORWARD2=$(curl -s -X POST "$BASE_URL/api/forward/create" \
  -H "Authorization: $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"测试-UDP-隧道转发\",
    \"tunnelId\": $TUNNEL_ID,
    \"remoteAddr\": \"$TARGET_SERVER\",
    \"strategy\": \"round\",
    \"engine\": \"auto\",
    \"forwardType\": \"tunnel_forward\",
    \"protocols\": \"udp\",
    \"inx\": 2
  }")

echo "创建结果: $FORWARD2"
echo ""

# 7. 创建 TCP+UDP 转发
echo "7. 创建 TCP+UDP 转发（port_forward）..."
FORWARD3=$(curl -s -X POST "$BASE_URL/api/forward/create" \
  -H "Authorization: $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"测试-TCP+UDP-端口转发\",
    \"tunnelId\": $TUNNEL_ID,
    \"remoteAddr\": \"$TARGET_SERVER\",
    \"strategy\": \"fifo\",
    \"engine\": \"auto\",
    \"forwardType\": \"port_forward\",
    \"protocols\": \"both\",
    \"inx\": 3
  }")

echo "创建结果: $FORWARD3"
echo ""

# 8. 查询转发列表，验证 forwardType 和 protocols 字段
echo "8. 查询转发列表..."
FORWARDS=$(curl -s -X GET "$BASE_URL/api/forward/list" \
  -H "Authorization: $TOKEN")

echo "转发列表长度: $(echo "$FORWARDS" | wc -c)"

# 检查是否包含 forwardType 和 protocols 字段
echo ""
echo "验证字段："
if echo "$FORWARDS" | grep -q "forwardType"; then
  echo "✅ forwardType 字段存在"
  echo "$FORWARDS" | grep -o '"forwardType":"[^"]*' | head -3
else
  echo "❌ forwardType 字段缺失"
fi

if echo "$FORWARDS" | grep -q "protocols"; then
  echo "✅ protocols 字段存在"
  echo "$FORWARDS" | grep -o '"protocols":"[^"]*' | head -3
else
  echo "❌ protocols 字段缺失"
fi

echo ""
echo "=========================================="
echo "测试完成"
echo "=========================================="
echo ""
echo "请访问前端页面验证显示："
echo "http://91.233.10.29:32769/"
echo ""
echo "登录信息："
echo "用户名：test_user"
echo "密码：test_user123"
echo ""
echo "检查项："
echo "1. 转发列表是否显示模式列（端口/隧道）"
echo "2. 转发列表是否显示协议列（TCP/UDP/TCP+UDP）"
echo "3. 转发模式是否正确：port_forward/tunnel_forward"
echo "4. 协议类型是否正确：tcp/udp/both"
echo ""
echo "创建的转发："
echo "- 测试-TCP-端口转发（port_forward + tcp）"
echo "- 测试-UDP-隧道转发（tunnel_forward + udp）"
echo "- 测试-TCP+UDP-端口转发（port_forward + both）"

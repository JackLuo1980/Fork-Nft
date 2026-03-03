# Issue #211: 转发自定义监听IP / 隧道指定连接IP

## 需求总结
1. **节点**: 高级配置增加"额外IP地址"字段（逗号分隔）
2. **转发**: 创建/编辑时可指定入口监听IP
3. **隧道**: 配置出口节点时可指定连接IP

---

## 任务清单

### 后端
- [x] 1. 数据模型扩展 - Node/ForwardPort/ChainTunnel 增加字段
- [x] 2. Repository - CreateNode/UpdateNode 处理 extraIPs
- [x] 3. Repository - resolveForwardIngress 使用 forward_port.in_ip
- [x] 4. Repository - GetNodeAllIPs 辅助函数（返回节点所有可用IP）
- [x] 5. Handler - 转发创建/更新处理 inIp 参数
- [x] 6. Handler - 隧道出口节点处理 connectIp 参数
- [x] 7. Handler - 节点API返回 extraIPs 字段

### 前端
- [x] 8. 节点编辑页 - 高级配置增加"额外IP"输入
- [x] 9. 转发编辑弹窗 - 增加"监听IP"下拉选择
- [x] 10. 隧道配置页 - 出口节点增加"连接IP"输入

---

## 完成进度
- 开始时间: 2026-03-02
- 完成时间: 2026-03-02
- 完成任务: 10/10
- 后端完成: ✅
- 前端完成: ✅

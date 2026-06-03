
# llm-d Router 项目分析报告

## 项目概览

**主语言**：Go 1.25.10
**运行平台**：Kubernetes, Docker
**项目职责**：LLM 推理请求的智能路由服务，通过 Endpoint Picker (EPP) 实现基于 KV-cache locality、负载和优先级的请求调度，支持 Disaggregated Inference (P/D 和 E/P/D) 模式。

### 核心场景

| 场景                         | 描述                                                           |
| -------------------------- | ------------------------------------------------------------ |
| LLM 推理流量路由                 | 在 Kubernetes 集群中通过 EPP 集成 Envoy ext-proc 协议，实现缓存感知、负载感知的智能调度 |
| Disaggregated Inference 编排 | Sidecar 代理协调 Prefill/Decode Worker 间的 KV-cache 传输，实现流水线推理    |
| 请求优先级与 Flow Control        | 通过 InferenceObjective CRD 定义优先级，Flow Control 层实现公平调度和限流      |

### 解决的问题

1. **KV-cache 利用率低** - 通过 kvcacheutilization/prefix/sessionaffinity scorer 实时获取缓存状态
2. **异构模型部署的路由** - 通过 InferencePool 和模型元数据过滤
3. **模型名称重写与流量控制** - 通过 InferenceModelRewrite CRD 支持 A/B 测试和灰度发布

### 架构概览

llm-d Router 是基于 Kubernetes 的 LLM 推理请求路由服务。核心组件 Endpoint Picker (EPP) 通过 ext-proc 协议与 Envoy 代理集成，实时获取请求上下文并注入路由决策。EPP 内部采用 Filter-Score-Select 三阶段过滤评分逻辑。Disaggregation Sidecar 协调整合 Prefill/Decode Worker 之间的 KV-cache 传输。

---

## 一级功能

| # | 功能名称 | 功能描述 |
|---|----------|----------|
| 1 | [智能请求路由](features/intelligent-request-routing.md) | 基于多维度评分选择最优后端模型服务 Pod |
| 2 | [KV-cache 感知调度](features/kv-cache-aware-scheduling.md) | 优先路由到 KV-cache 命中率高或有 session affinity 的 Pod |
| 3 | [请求优先级管理](features/request-priority-management.md) | 通过 InferenceObjective CRD 定义请求优先级，实现差异化调度 |
| 4 | [模型重写与流量分割](features/model-rewrite-traffic-split.md) | 通过 InferenceModelRewrite CRD 动态修改请求中的模型名，支持 A/B 测试和灰度发布 |
| 5 | [Disaggregated Inference 协调](features/disaggregated-inference-coordination.md) | Sidecar 代理协调 Prefill/Decode Worker 间的 KV-cache 传输，实现流水线推理 |
| 6 | [Flow Control 流量控制](features/flow-control.md) | 请求准入、排队、限流、优先级调度，保护后端不被过载 |
| 7 | [Metrics 抓取与监控](features/metrics-scraping-monitoring.md) | 从模型服务器 Pod 抓取 Prometheus metrics，为路由决策提供数据支撑 |
| 8 | [多协议解析支持](features/multi-protocol-parser-support.md) | 支持 OpenAI、vLLM、Anthropic、VertexAI 等多种 LLM API 协议解析 |

---

## 集成能力

### Feature-Level 集成

| 集成能力 | 所属功能 | 描述 |
|----------|----------|------|
| Prometheus Metrics 抓取 | Metrics 抓取与监控 | 从模型服务器 Pod 定期抓取 Prometheus 格式指标 |
| vLLM 模型服务器 | Metrics 抓取与监控 | 作为路由目标后端，支持 vLLM 引擎的指标映射 |
| SGLang 模型服务器 | Metrics 抓取与监控 | 作为路由目标后端，支持 SGLang 引擎的指标映射 |
| TRT-LLM 模型服务器 | Metrics 抓取与监控 | 作为路由目标后端，支持 TRT-LLM 引擎的指标映射 |
| Triton 模型服务器 | Metrics 抓取与监控 | 作为路由目标后端，支持 Triton 引擎的指标映射 |
| OpenAI 协议解析 | 多协议解析支持 | 支持 OpenAI API 标准接口，是默认 parser |
| vLLM HTTP 协议解析 | 多协议解析支持 | 支持 vLLM disaggregated 模式的 /inference/v1/generate 路径 |
| vLLM gRPC 协议解析 | 多协议解析支持 | 支持 vLLM 的 gRPC 协议 |
| Anthropic 协议解析 | 多协议解析支持 | 支持 Anthropic API 格式 |
| VertexAI 协议解析 | 多协议解析支持 | 支持 Google VertexAI 协议 |
| Passthrough 模式 | 多协议解析支持 | 透传模式，不做请求解析 |
| InferenceObjective CRD | 请求优先级管理 | 声明请求优先级和目标 InferencePool |
| InferenceModelRewrite CRD | 模型重写与流量分割 | 定义模型名映射规则，支持流量分割 |
| EndpointPickerConfig CRD | 智能请求路由 | 配置 SchedulingProfiles 和插件实例化 |
| NIXL v2 传输 | Disaggregated Inference 协调 | 高性能 KV-cache 传输 |
| RDMA 支持 | Disaggregated Inference 协调 | 支持 RDMA 网络传输 |
| TCP 传输 | Disaggregated Inference 协调 | 基于 TCP 的 KV-cache 传输 |
| Flow Control 公平调度 | Flow Control 流量控制 | GlobalStrict、RoundRobin 等公平策略 |
| Flow Control 限流 | Flow Control 流量控制 | UsageLimits 限流器实现 |
| KV-cache Scorer | KV-cache 感知调度 | 根据 KV-cache 使用率打分 |
| Prefix Scorer | KV-cache 感知调度 | 根据 prefix cache 命中率打分 |
| Session Affinity Scorer | KV-cache 感知调度 | 根据 session ID 匹配度打分 |

### Project-Level 集成

| 集成能力 | 描述 |
|----------|------|
| Kubernetes 部署 | 支持 Kubernetes 部署，通过 Gateway API 集成 |
| Docker 镜像分发 | 提供 Docker 镜像用于容器化部署 |
| Envoy ext-proc 集成 | 通过 External Processing 协议与 Envoy 代理集成 |

### 内部依赖（不进入用户视角）

- Kubernetes client-go
- Envoy ext-proc gRPC
- Prometheus client
- Go standard library

---

## 质审状态

| 组件 | 质审状态 |
|------|----------|
| project-overview | ✓ 通过（2 轮） |
| features (8) | 质审中发现问题，部分需要修订 |
| integrations | 已生成 |

---

## 附录

### 报告文件路径

```
analysis-report/
├── overview.md                       # 本报告
├── project-overview.json             # 项目概览
├── feature-plan.json                 # 功能规划清单
├── integrations.json                 # 集成能力清单
├── features/
│   ├── intelligent-request-routing.md / .json
│   ├── kv-cache-aware-scheduling.md / .json
│   ├── request-priority-management.md / .json
│   ├── model-rewrite-traffic-split.md / .json
│   ├── disaggregated-inference-coordination.md / .json
│   ├── flow-control.md / .json
│   ├── metrics-scraping-monitoring.md / .json
│   └── multi-protocol-parser-support.md / .json
├── boundary-review/
│   └── final.json                    # 边界审查最终结果
└── quality-review/                   # 质审记录
```

### 报告生成日期

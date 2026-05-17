# 架构决策：部署模式与多集群管理

## 运维模式

**单一运维团队管理，多项目多租户模式。**

```
┌─────────────────────────────────────────────────┐
│              Platform / SRE Team                 │
│         （唯一的 Argo CD 管理者）                  │
├─────────────────────────────────────────────────┤
│                                                 │
│   ┌───────────┐  ┌───────────┐  ┌───────────┐  │
│   │  Team A   │  │  Team B   │  │  Team C   │  │
│   │  devops   │  │  frontend │  │  data-eng │  │
│   │           │  │           │  │           │  │
│   │ ns: a-*   │  │ ns: b-*   │  │ ns: c-*   │  │
│   └───────────┘  └───────────┘  └───────────┘  │
│                                                 │
│       通过 AppProject 逻辑隔离，PR 自服务          │
└─────────────────────────────────────────────────┘
```

---

## 部署模式选择：Cluster-wide

### 为什么选 Cluster-wide

| 考量 | 决策 |
|------|------|
| 运维团队数量 | 单一团队 → 不需要多实例隔离 |
| 租户隔离需求 | 逻辑隔离即可（AppProject） → 不需要物理隔离 |
| 集群级资源管理 | 需要创建 Namespace、ClusterRole → 必须 Cluster-wide |
| 管理复杂度 | 一个 Argo CD 管一切 → 运维成本最低 |

### 两种模式对比

| 维度 | Cluster-wide（我们的选择） | Namespace-scoped |
|------|---|---|
| Argo CD 实例数 | 1 个管所有 | 每个团队/环境 1 个 |
| 权限 | ClusterRole（全集群） | Role（仅限指定 namespace） |
| 租户隔离 | AppProject 逻辑隔离 | 物理隔离（独立实例） |
| 集群级资源 | ✅ 可管理 Namespace/CRD/ClusterRole | ❌ 无法管理 |
| 运维成本 | 低（一套配置） | 高（N 套配置） |
| 适合 | 单运维团队 + 多项目 | 严格合规 / 多运维团队互不信任 |

### 安全边界实现

Cluster-wide 不代表没有隔离。通过 AppProject 实现精细控制：

```yaml
# bootstrap/values.yaml 中配置 tenant 权限
tenants:
  - name: team-a
    namespace: team-a
    path: tenants/team-a
    sourceRepos:                    # 只能从指定仓库拉代码
      - "https://github.com/org/team-a-app.git"

# 自动生成的 AppProject 包含：
# spec:
#   sourceNamespaces: ["team-a"]   # 只允许 team-a namespace 的 Application
#   sourceRepos: [本仓库, 业务仓库] # 自动包含本仓库
#   destinations:                  # 只能部署到自己的 namespace
#     - namespace: "team-a"
#     - namespace: "team-a-*"     # 覆盖 team-a-dev, team-a-uat 等
#   clusterResourceWhitelist:     # 精确控制集群级资源
#     - Namespace, ClusterRole, ClusterRoleBinding
```

---

## 多集群管理模式：Hub-and-Spoke

### 架构

```
                    ┌──────────────────┐
                    │   Hub Cluster    │
                    │  (Argo CD 所在)   │
                    │                  │
                    │  ┌────────────┐  │
                    │  │  Argo CD   │  │
                    │  │ Cluster-   │  │
                    │  │   wide     │  │
                    │  └─────┬──────┘  │
                    └────────┼─────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
     ┌────────────┐  ┌────────────┐  ┌────────────┐
     │  Spoke 1   │  │  Spoke 2   │  │  Spoke 3   │
     │  dev       │  │  staging   │  │  prod      │
     │            │  │            │  │            │
     │ 只跑业务Pod │  │ 只跑业务Pod │  │ 只跑业务Pod │
     └────────────┘  └────────────┘  └────────────┘
```

### 核心原则

1. **Hub 集群只装 Argo CD** — 业务 Pod 不跑在 Hub 上
2. **Spoke 集群不装 Argo CD** — 只接受 Hub 的管理
3. **所有配置集中在 Git** — Hub 上的 Argo CD 从 Git 拉取，推送到各 Spoke

### 适用场景

| 场景 | 是否适合 Hub-and-Spoke |
|------|---|
| 单运维团队管理多环境（dev/staging/prod） | ✅ 最佳匹配 |
| 多区域部署（cn-east, us-west） | ✅ 集中管控 |
| 多团队共享基础设施但隔离业务 | ✅ AppProject + 多集群 |
| 各团队完全独立，互不信任 | ❌ 用多 Argo CD 实例 |
| 合规要求控制面和数据面物理分离 | ✅ Hub 是控制面 |

### 当前状态与演进路径

```
现在（单集群）:
  Hub = Spoke = 同一个集群（in-cluster）
  Argo CD 管理自身所在集群

未来（多集群）:
  1. 当前集群升级为 Hub（专跑 Argo CD）
  2. 新集群注册为 Spoke
  3. argocd cluster add <context> --name <name>
  4. clusters/ 目录添加元数据
  5. Application 的 destination.server 指向 Spoke
```

### 接入新集群步骤

```bash
# 1. 确保 kubeconfig 有目标集群的 context
kubectl config get-contexts

# 2. 在 Argo CD 注册新集群（使用 name 而非 URL）
argocd cluster add prod-context --name prod-hk-01

# 3. 在 Git 仓库添加集群元数据
cp -r clusters/_template clusters/prod-hk-01
vim clusters/prod-hk-01/config.yaml

# 4. 修改 Application 的 destination 指向新集群
# destination:
#   server: https://kubernetes.default.svc  ← 改为
#   name: prod-hk-01                        ← 使用集群名称
```

### 多集群下的 Application 分发策略

| 策略 | 方式 | 适合 |
|------|------|------|
| 手动指定 | 每个 Application YAML 写 `destination.name` | 应用少，集群少 |
| ApplicationSet List Generator | 列出集群名，模板化生成 | 应用少，集群多 |
| ApplicationSet Git Generator | 扫描 `clusters/*/config.yaml` | 应用多，集群多 |
| ApplicationSet Cluster Generator | 按集群标签自动匹配 | 最自动化 |

**我们的演进路径：** 当前手动指定 → 接入第 2 个集群时切换到 ApplicationSet。

---

## 资源追踪方式：Annotation

### 配置

```yaml
# platform/values/base.yaml
configs:
  cm:
    application.resourceTrackingMethod: annotation
```

### 作用

Argo CD 需要标记集群中每个资源"属于哪个 Application"，用于：
- 检测配置漂移（有人手动改了集群资源）
- `selfHeal: true` 自动恢复被修改的资源
- `prune: true` 删除 Git 中已移除的资源
- UI 中展示 Application 的资源树

### 三种模式对比

| 方式 | 机制 | 适用场景 |
|------|------|----------|
| `label` | 加 `app.kubernetes.io/instance` label | 旧版默认，容易和 Helm/Kustomize 冲突 |
| **`annotation`（我们的选择）** | 加 `argocd.argoproj.io/tracking-id` annotation | 推荐，不与其他工具冲突 |
| `annotation+label` | 同时加两者 | 从 label 迁移到 annotation 的过渡期 |

### 为什么选 annotation

1. **避免冲突** — `app.kubernetes.io/instance` 是通用 label，Helm chart 经常使用它，会导致 Argo CD 误判资源归属
2. **无长度限制** — label 值限制 63 字符，annotation 无此限制，可存完整 tracking ID
3. **官方推荐** — Argo CD 2.2+ 推荐 annotation 模式

### 实际效果

Argo CD 同步资源后，会在每个 managed 资源上添加：

```yaml
metadata:
  annotations:
    argocd.argoproj.io/tracking-id: "<app-name>:<group>/<kind>:<namespace>/<name>"
```

示例：
```yaml
argocd.argoproj.io/tracking-id: "devops-example-app:apps/Deployment:devops-dev/guestbook-ui"
```

---

## Application in Any Namespace 模式

### 概述

Argo CD 2.5+ 支持在任意 namespace 中创建 Application 资源（而非全部集中在 argocd namespace）。我们启用此模式，让每个租户的 Application 存放在租户自己的 namespace 中。

### 为什么切换

| 问题（传统模式） | 解决（Application in Namespace） |
|---|---|
| 所有 Application 挤在 argocd namespace，不好管理 | 各租户 Application 在自己的 namespace，按 NS 过滤 |
| 租户只能通过 AppProject 逻辑隔离 | 可叠加 k8s 原生 RBAC（控制谁能操作该 NS 的 Application） |
| 无法给租户 kubectl 查看权限（不想暴露 argocd NS） | 租户可 `kubectl get app -n their-ns` 自行查看 |

### 关键配置参数

#### 1. Argo CD Server — 允许哪些 namespace

```yaml
# platform/values/base.yaml
argo-cd:
  configs:
    params:
      application.namespaces: "*"   # "*" 允许所有，或 "devops,team-b" 指定列表
```

#### 2. AppProject — 由 bootstrap 模板自动生成

AppProject 不再需要手动创建 `project.yaml` 文件，由 `bootstrap/templates/root-app.yaml` 自动生成。
配置来源是 `bootstrap/values.yaml` 中的 tenant 条目：

```yaml
# bootstrap/values.yaml
tenants:
  - name: example
    namespace: example        # Application 资源存放的 namespace
    path: tenants/example
    sourceRepos:              # 该 tenant 允许拉取的业务仓库
      - "https://github.com/argoproj/argocd-example-apps.git"
```

自动生成的 AppProject 包含 `sourceNamespaces: ["example"]`，允许 example namespace 中的 Application 引用此 project。

> **重要：** 如果不配置 `sourceNamespaces`，非 argocd namespace 中的 Application 无法使用该 project。

#### 3. Application — metadata.namespace 为租户 namespace

```yaml
# tenants/example/apps/guestbook-dev.yaml
metadata:
  name: example-guestbook-dev
  namespace: example          # 不再是 argocd，而是租户自己的 namespace
spec:
  project: example            # 引用的 project 已自动配置 sourceNamespaces: ["example"]
```

### 资源分布图

```
┌───────────────────────────────────────┐
│         namespace: argocd             │
│                                       │
│  AppProject: example (限定权限)        │  ← bootstrap 自动生成
└───────────────────────────────────────┘

┌───────────────────────────────────────┐
│         namespace: example            │
│                                       │
│  Application: tenant-example          │  ← bootstrap 创建，同步 apps/ 目录
│  Application: example-guestbook-dev   │  ← 租户的业务 Application
│  Application: example-guestbook-uat   │
└───────────────────────────────────────┘

┌──────────────────┐  ┌──────────────────┐
│ ns: example-dev  │  │ ns: example-uat  │
│                  │  │                  │
│ Pod: guestbook   │  │ Pod: guestbook   │  ← 实际业务 workload
│ Svc: guestbook   │  │ Svc: guestbook   │
└──────────────────┘  └──────────────────┘
```

### 注意事项

1. **AppProject 仍在 argocd namespace** — 只有 Application 可以跨 namespace，Project 不行
2. **namespace 必须先存在** — bootstrap 模板中已设置 `CreateNamespace=true`
3. **RBAC 叠加** — 可以通过 k8s Role/RoleBinding 控制谁能 CRUD 该 namespace 的 Application
4. **UI 过滤** — Argo CD UI 支持按 namespace 过滤 Application，方便各团队查看自己的
5. **向后兼容** — 仍在 argocd namespace 中的 Application 继续正常工作

### 租户 RBAC 示例（可选）

如果需要让 devops 团队用 kubectl 管理自己的 Application：

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: application-manager
  namespace: devops
rules:
  - apiGroups: ["argoproj.io"]
    resources: ["applications"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: devops-app-manager
  namespace: devops
subjects:
  - kind: Group
    name: devops-team
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: application-manager
  apiGroup: rbac.authorization.k8s.io
```

---

## 总结：为什么这么设计

| 设计决策 | 原因 |
|----------|------|
| Cluster-wide 模式 | 单运维团队，需要管理集群级资源 |
| AppProject 逻辑隔离 | 多租户安全边界，无需多实例 |
| Application in Namespace | 租户按 namespace 管理自己的 Application，更清晰 |
| Hub-and-Spoke 架构预留 | 单集群起步，多集群无需重构 |
| Git 声明式管理 | 所有变更可审计，PR 即部署 |
| 使用 Name 引用集群 | URL 会变，Name 是稳定的逻辑标识 |
| Annotation 追踪资源 | 避免 label 冲突，官方推荐方式 |

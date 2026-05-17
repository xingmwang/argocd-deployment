# Namespace 设计规范

## 核心概念

在 Application in Any Namespace 模式下，每个 Application YAML 中有两个 namespace 字段，含义完全不同：

```yaml
metadata:
  namespace: example        # ① Application 资源本身存放的位置（按项目分）

destination:
  namespace: example-dev    # ② 业务 workload 部署的位置（按环境分）
```

## 设计模型

```
一个 Tenant = 一个项目
一个项目包含多个环境的 Application
所有 Application 资源统一存放在项目 namespace 中
AppProject 必须在 argocd namespace（Argo CD 硬约束）
```

## Namespace 分布

| Namespace | 用途 | 由谁创建 |
|-----------|------|----------|
| `argocd` | Argo CD 本体 + 所有 AppProject | Helm install |
| `{project}` | 存放该项目所有 Application 资源 | bootstrap `kubectl apply` |
| `{project}-dev` | 开发环境 workload | Application syncPolicy (CreateNamespace) |
| `{project}-uat` | UAT 环境 workload | Application syncPolicy (CreateNamespace) |
| `{project}-staging` | 预发布环境 workload | Application syncPolicy (CreateNamespace) |
| `{project}-prod` | 生产环境 workload | Application syncPolicy (CreateNamespace) |

## 资源分布图

```
┌────────────────────────────────────────────────────────────┐
│                   namespace: argocd                         │
│                                                            │
│  AppProject: example      ← 权限边界（sourceNamespaces,    │
│                              destinations, sourceRepos）    │
└────────────────────────────────────────────────────────────┘
         │
         │  AppProject.sourceNamespaces: ["example"]
         │
┌────────────────────────────────────────────────────────────┐
│                   namespace: example                        │  ← metadata.namespace
│                                                            │
│  Application: tenant-example           (同步 apps/ 目录)    │
│  Application: example-guestbook-dev    → deploys to example-dev
│  Application: example-guestbook-uat    → deploys to example-uat
└────────────────────────────────────────────────────────────┘
         │                    │
         ▼                    ▼
┌──────────────────┐  ┌──────────────────┐
│ ns: example-dev  │  │ ns: example-uat  │    ← destination.namespace
│                  │  │                  │
│ Pod: guestbook   │  │ Pod: guestbook   │
│ Svc: guestbook   │  │ Svc: guestbook   │
└──────────────────┘  └──────────────────┘
```

## 配置文件对照表

| 文件 | 作用 | 关键字段 |
|------|------|----------|
| `bootstrap/values.yaml` | 注册 tenant、定义权限 | `tenants[].namespace`, `tenants[].sourceRepos` |
| `bootstrap/templates/root-app.yaml` | 生成 Namespace + AppProject + tenant Application | 模板，无需手动修改 |
| `tenants/{name}/apps/*.yaml` | 定义各环境部署 | `metadata.namespace`, `destination.namespace` |

## Application 命名规范

格式：`{project}-{app}-{env}`

示例：
- `example-guestbook-dev`
- `example-guestbook-uat`
- `example-api-service-prod`

## AppProject 权限配置

AppProject 由 bootstrap 模板自动生成（不需要手动创建 project.yaml），配置来自 `bootstrap/values.yaml`：

```yaml
tenants:
  - name: example
    namespace: example
    path: tenants/example
    sourceRepos:                              # 该 tenant 允许拉取的仓库
      - "https://github.com/argoproj/argocd-example-apps.git"
```

生成的 AppProject 自动包含：
- `sourceNamespaces: ["example"]` — 允许 example namespace 中的 Application 引用此 project
- `sourceRepos` — 本仓库地址（自动添加）+ values 中配置的业务仓库
- `destinations: ["example", "example-*"]` — 允许部署到项目自身及所有环境 namespace

## 查看方式

```bash
# 查看某个项目所有环境的应用状态
kubectl get app -n example

# 查看某个环境的 workload
kubectl get pods -n example-dev
kubectl get pods -n example-uat

# 查看 AppProject
kubectl get appproject -n argocd
```

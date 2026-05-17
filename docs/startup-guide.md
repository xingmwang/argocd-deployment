# Startup Guide — 从零到 GitOps 全流程

---

## 前置条件

| 工具 | 用途 | 安装 |
|------|------|------|
| kubectl | 集群管理 | `brew install kubectl` |
| helm 3.x | Chart 部署 | `brew install helm` |
| kind 或 minikube | 本地集群（可选） | `brew install kind` |
| git | 版本控制 | `brew install git` |

---

## 阶段一：环境准备

### 1.1 创建本地集群（如已有集群可跳过）

```bash
make local-cluster
# 或
minikube start --cpus=4 --memory=4096
```

### 1.2 确认集群连接

```bash
kubectl cluster-info
kubectl get nodes
```

---

## 阶段二：安装 Argo CD

### 2.1 下载 Helm Chart（离线模式）

由于网络环境限制，需要手动下载 argo-cd chart：

```bash
# 方式 1：使用代理
export https_proxy=http://127.0.0.1:7890
helm pull argo-cd --repo https://argoproj.github.io/argo-helm --version 7.7.5 -d platform/charts/

# 方式 2：手动下载
curl -L -o platform/charts/argo-cd-7.7.5.tgz \
  https://github.com/argoproj/argo-helm/releases/download/argo-cd-7.7.5/argo-cd-7.7.5.tgz
```

### 2.2 配置镜像源（按需修改）

编辑 `platform/values/base.yaml`，确认 Redis 镜像地址可达：

```yaml
argo-cd:
  redis:
    image:
      repository: docker.m.daocloud.io/library/redis
      tag: 7.2.4-alpine
```

### 2.3 安装

```bash
make install ENV=dev
```

脚本会自动：
1. 创建 `argocd` namespace
2. 检测本地 chart 版本，跳过网络下载
3. `helm upgrade --install` 安装 Argo CD
4. 等待 server 就绪
5. 渲染 bootstrap 模板并 apply（创建 Namespace + AppProject + tenant Application）

### 2.4 访问 Argo CD UI

```bash
# 端口转发
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 获取初始密码
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

# 浏览器打开
open https://localhost:8080
# 用户名: admin  密码: 上面获取的密码
```

### 2.5 安装 Argo CD CLI

```bash
# macOS
brew install argocd

# Linux
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd && sudo mv argocd /usr/local/bin/
```

### 2.6 登录 Argo CD

```bash
# 获取初始密码
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)

# 登录（确保端口转发已运行）
argocd login localhost:8080 --username admin --password "$ARGOCD_PASSWORD" --insecure

# 验证登录成功
argocd account get-user-info

# （推荐）修改默认密码
argocd account update-password --account admin --current-password "$ARGOCD_PASSWORD" --new-password <your-new-password>
```

---

## 阶段三：推送仓库到 Git 远端

> **重要：** Argo CD 从 Git 仓库拉取配置，代码必须推送后才能自动同步。

### 3.1 创建远端仓库

在 GitHub/GitLab 创建一个仓库（如 `your-org/argocd-deployment`）。

### 3.2 推送代码

```bash
git add .
git commit -m "feat: initial argocd-deployment structure"
git remote add origin https://github.com/your-org/argocd-deployment.git
git push -u origin main
```

### 3.3 更新 bootstrap 配置

编辑 `bootstrap/values.yaml`：

```yaml
repoURL: "https://github.com/your-org/argocd-deployment.git"  # 改为你的仓库地址
```

### 3.4 在 Argo CD 注册仓库（如为私有仓库）

```bash
argocd repo add https://github.com/your-org/argocd-deployment.git \
  --username <user> --password <token>
```

---

## 阶段四：验证部署

### 4.1 查看 Application 状态

```bash
# tenant Application（在 example namespace 中）
kubectl get app -n example

# 预期输出：
# NAME                      SYNC STATUS   HEALTH STATUS
# tenant-example            Synced        Healthy
# example-guestbook-dev     Synced        Healthy
# example-guestbook-uat     Synced        Healthy
```

### 4.2 查看 workload

```bash
kubectl get pods -n example-dev
kubectl get pods -n example-uat
```

### 4.3 通过 Argo CD CLI 查看

```bash
argocd app list
argocd app get example-guestbook-dev
```

---

## 阶段五：Onboard 新租户

### 5.1 交互式创建

```bash
make add-tenant
```

### 5.2 手动创建

**步骤 1：** 编辑 `bootstrap/values.yaml`，添加 tenant 条目：

```yaml
tenants:
  - name: example
    namespace: example
    path: tenants/example
    sourceRepos:
      - "https://github.com/argoproj/argocd-example-apps.git"
  - name: my-team                              # ← 新增
    namespace: my-team
    path: tenants/my-team
    sourceRepos:
      - "https://github.com/org/my-app.git"
```

**步骤 2：** 创建 apps 目录并添加 Application YAML：

```bash
mkdir -p tenants/my-team/apps
```

```yaml
# tenants/my-team/apps/my-app-dev.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-team-my-app-dev
  namespace: my-team
spec:
  project: my-team
  source:
    repoURL: "https://github.com/org/my-app.git"
    targetRevision: HEAD
    path: deploy/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: my-team-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**步骤 3：** 生效

```bash
# 本地开发阶段
helm template bootstrap bootstrap/ | kubectl apply -f -

# 或 GitOps 模式
git add . && git commit -m "feat(tenants): onboard my-team" && git push
# 然后重新 apply bootstrap
```

---

## 阶段六：日常运维

### 升级 Argo CD 版本

```bash
# 1. 修改版本号
vim platform/Chart.yaml    # 改 dependencies[0].version

# 2. 下载新版 chart
helm pull argo-cd --repo https://argoproj.github.io/argo-helm --version <NEW_VERSION> -d platform/charts/

# 3. 执行升级
make upgrade ENV=dev
```

### 更新 Tenant 配置

修改 `bootstrap/values.yaml` 后重新 apply：

```bash
helm template bootstrap bootstrap/ | kubectl apply -f -
```

### 移除 Tenant

```bash
# 1. 从 bootstrap/values.yaml 删除 tenant 条目
# 2. 重新 apply bootstrap（会删除该 tenant 的 Namespace、AppProject、tenant Application）
helm template bootstrap bootstrap/ | kubectl apply -f -
# 3.（可选）手动清理环境 namespace
kubectl delete ns my-team-dev my-team-uat
# 4. 删除 tenants/my-team/ 目录
```

---

## 快速参考

| 操作 | 命令 |
|------|------|
| 安装/更新 Argo CD | `make install ENV=dev` |
| 升级 Argo CD | `make upgrade ENV=dev` |
| 新增租户 | `make add-tenant` |
| 刷新 bootstrap | `helm template bootstrap bootstrap/ \| kubectl apply -f -` |
| 验证配置 | `make lint` |
| 查看 tenant 应用 | `kubectl get app -n {tenant}` |
| 查看环境 workload | `kubectl get pods -n {tenant}-{env}` |
| 端口转发 UI | `kubectl port-forward svc/argocd-server -n argocd 8080:443` |

---

## 故障排查

| 问题 | 排查 |
|------|------|
| Chart 下载失败 | 手动下载 tgz 放入 `platform/charts/` |
| 镜像拉取失败 | 检查 `platform/values/base.yaml` 中的镜像地址 |
| Application 状态 Unknown | `argocd app get <name>` 或 `kubectl describe app -n {tenant} <name>` |
| "repo not permitted in project" | 检查 `bootstrap/values.yaml` 中 tenant 的 `sourceRepos` |
| "app is not allowed in project" | 确认 AppProject 的 `sourceNamespaces` 包含 tenant namespace |
| "namespace not permitted" | 确认 AppProject 的 `destinations` 包含目标 namespace |
| 仓库连接失败 | `argocd repo list` 确认仓库注册状态 |
| Helm release 冲突 | `helm list -n argocd` 检查已有 release |

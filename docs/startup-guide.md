# Startup Guide — 从零到 GitOps 全流程

本文档串联整个部署流程，从环境准备到第一个应用成功同步。

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
5. 创建 platform AppProject
6. 渲染 bootstrap 模板并 apply

### 2.4 访问 Argo CD UI

```bash
# 端口转发
kubectl port-forward svc/argocd-argocd-server -n argocd 8080:443

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

### 2.7 常用 CLI 命令

```bash
# 查看所有应用
argocd app list

# 查看集群列表
argocd cluster list

# 查看仓库列表
argocd repo list

# 手动同步某个应用
argocd app sync <app-name>

# 查看应用详情
argocd app get <app-name>
```

---

## 阶段三：推送仓库到 Git 远端

> **重要：** Argo CD 通过 Git 仓库拉取配置。在此之前，所有 Application 需手动 apply。

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
targetRevision: HEAD
destinationServer: "https://kubernetes.default.svc"  # 保持默认即可
```

### 3.4 在 Argo CD 注册仓库（如为私有仓库）

```bash
argocd repo add https://github.com/your-org/argocd-deployment.git \
  --username <user> --password <token>
```

---

## 阶段四：启用 GitOps 自动同步（Bootstrap）

### 4.1 Apply bootstrap

```bash
helm template bootstrap bootstrap/ -f bootstrap/values.yaml | kubectl apply -n argocd -f -
```

此命令会创建：
- `root` Application（管理 bootstrap 自身）
- `tenant-*` Application（每个 tenant 一个）
- `ext-*` Application（每个 extension 一个）

### 4.2 验证

```bash
kubectl get application -n argocd
```

预期输出：
```
NAME              SYNC STATUS   HEALTH STATUS
root              Synced        Healthy
tenant-devops     Synced        Healthy
```

### 4.3 自举（可选，让 Argo CD 自管理 bootstrap）

编辑 `bootstrap/static/install-bootstrap.yaml`，更新 `repoURL` 后：

```bash
kubectl apply -f bootstrap/static/install-bootstrap.yaml -n argocd
```

自举后，修改 `bootstrap/values.yaml` 并 push 到 Git，Argo CD 会自动识别变更。

---

## 阶段五：Onboard 租户应用

### 5.1 创建 Tenant 目录

```bash
# 交互式
make add-tenant

# 或手动复制模板
cp -r tenants/_template tenants/my-team
```

### 5.2 配置 AppProject

编辑 `tenants/my-team/project.yaml`：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: my-team
  namespace: argocd
spec:
  sourceRepos:
    - "https://github.com/argoproj/argocd-example-apps.git"  # 应用源码仓库
  destinations:
    - namespace: "my-team-*"    # 只允许部署到自己的 namespace
      server: https://kubernetes.default.svc
  clusterResourceWhitelist: []  # 禁止集群级资源
```

### 5.3 添加 Application

创建 `tenants/my-team/apps/guestbook.yaml`：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-team-guestbook
  namespace: argocd
spec:
  project: my-team
  source:
    repoURL: "https://github.com/argoproj/argocd-example-apps.git"
    targetRevision: HEAD
    path: guestbook
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

### 5.4 注册到 bootstrap

编辑 `bootstrap/values.yaml`，添加 tenant：

```yaml
tenants:
  - name: my-team
    path: tenants/my-team
```

### 5.5 生效

```bash
# 方式 A：仓库已推远端（GitOps 模式）
git add . && git commit -m "feat(tenants): onboard my-team" && git push

# 方式 B：本地开发阶段（手动 apply）
helm template bootstrap bootstrap/ -f bootstrap/values.yaml | kubectl apply -n argocd -f -
```

### 5.6 验证应用部署

```bash
# 查看 Application 状态
kubectl get app -n argocd

# 查看部署的 Pod
kubectl get pods -n my-team-dev

# 或通过 Argo CD CLI
argocd app list
argocd app get my-team-guestbook
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

### 添加 Extension

```bash
# 1. 取消 values.yaml 中的注释
vim bootstrap/values.yaml
# extensions:
#   - name: image-updater
#     path: extensions/image-updater

# 2. 推送或手动 apply
git add . && git commit -m "feat(ext): enable image-updater" && git push
```

### 移除 Tenant

```bash
# 1. 从 bootstrap/values.yaml 删除 tenant 条目
# 2. 推送 → Argo CD 自动 prune 对应 Application
# 3.（可选）删除 tenants/team-name/ 目录
```

---

## 快速参考

| 操作 | 命令 |
|------|------|
| 安装/更新 Argo CD | `make install ENV=dev` |
| 升级 Argo CD | `make upgrade ENV=dev` |
| 新增租户 | `make add-tenant` |
| 验证配置 | `make lint` |
| 刷新 bootstrap | `helm template bootstrap bootstrap/ -f bootstrap/values.yaml \| kubectl apply -n argocd -f -` |
| 查看所有 Application | `kubectl get app -n argocd` |
| 查看同步状态 | `argocd app list` |
| 端口转发 UI | `kubectl port-forward svc/argocd-argocd-server -n argocd 8080:443` |

---

## 故障排查

| 问题 | 排查 |
|------|------|
| Chart 下载失败 | 手动下载 tgz 放入 `platform/charts/` |
| 镜像拉取失败 | 检查 `platform/values/base.yaml` 中的镜像地址 |
| Application 状态 Unknown | `argocd app get <name>` 查看错误详情 |
| Tenant 无权限 | 检查 `project.yaml` 的 sourceRepos 和 destinations |
| 仓库连接失败 | `argocd repo list` 确认仓库注册状态 |
| Helm release 冲突 | `helm list -n argocd` 检查已有 release |

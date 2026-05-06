# Argo CD Vault Plugin (AVP)

## Overview

AVP allows Argo CD to resolve secret placeholders in manifests from HashiCorp Vault,
AWS Secrets Manager, or other secret backends.

## Setup

1. Configure the plugin in `platform/values/base.yaml`:
   ```yaml
   argo-cd:
     repoServer:
       initContainers:
         - name: download-tools
           image: alpine:3.18
           command: [sh, -c]
           args:
             - >-
               wget -O /custom-tools/argocd-vault-plugin
               https://github.com/argoproj-labs/argocd-vault-plugin/releases/download/v1.17.0/argocd-vault-plugin_1.17.0_linux_amd64 &&
               chmod +x /custom-tools/argocd-vault-plugin
           volumeMounts:
             - mountPath: /custom-tools
               name: custom-tools
   ```

2. Add a ConfigManagementPlugin in Argo CD config.

## Status

Placeholder — implement when secret management tool is chosen.

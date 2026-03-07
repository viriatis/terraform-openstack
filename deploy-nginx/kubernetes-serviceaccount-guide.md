# Kubernetes ServiceAccount — Complete Guide

## What is a ServiceAccount?

A ServiceAccount is a Kubernetes-native identity assigned to a pod. When a pod needs to interact with the Kubernetes API or authenticate to external systems, it uses its ServiceAccount token to prove who it is.

Kubernetes automatically mounts the token at:
```
/var/run/secrets/kubernetes.io/serviceaccount/token
```

---

## Why ServiceAccounts instead of Users?

Kubernetes has **no built-in user management**. Human users come from external sources — certificates, OIDC providers, LDAP. Setting up a test user means creating a certificate, signing it with the cluster CA, and building a kubeconfig. That's heavy overhead.

ServiceAccounts are **native k8s objects** — created with one command, stored in etcd, automatically injected into pods. That's why they're the go-to subject for RBAC testing and real workloads alike.

---

## When does a pod actually need a ServiceAccount?

A pod needs a ServiceAccount with real permissions when it needs to **talk to the Kubernetes API**.

### Pods that actively need one:
- **ArgoCD** — reads/writes deployments, services, configmaps to sync apps
- **Jenkins agents** — runs `kubectl apply` inside pipelines
- **Prometheus** — lists/watches pods, nodes, endpoints to scrape metrics
- **External Secrets / Vault Agent** — authenticates to Vault or reads secrets
- **Ingress-nginx controller** — watches Ingress resources to update its config

### Pods that typically don't need one:
- Your standard app pods — a .NET API, a Node.js service, a React frontend. They talk to databases, other services, the internet — but not to the Kubernetes API.

---

## Every pod gets a ServiceAccount anyway

If you don't specify one, Kubernetes assigns the **`default` ServiceAccount** of the namespace. It has no permissions by default in a properly configured cluster, but the token is still mounted.

### Security hardening — disable automount if not needed:
```yaml
spec:
  automountServiceAccountToken: false
```
Good practice for any app pod that doesn't need API access.

---

## RBAC — How permissions work

The flow is:

```
Pod → ServiceAccount → RoleBinding → Role → Permissions
```

Four key objects:

| Object | Scope | Purpose |
|---|---|---|
| `Role` | Namespace | Defines allowed actions on resources |
| `ClusterRole` | Cluster-wide | Same, but for cluster-scoped resources |
| `RoleBinding` | Namespace | Binds a Role to a subject (SA, User, Group) |
| `ClusterRoleBinding` | Cluster-wide | Binds a ClusterRole to a subject |

---

## Hands-on Lab with kind (Mac)

### Setup
```bash
brew install kind kubectl
kind create cluster --name rbac-lab
kubectl cluster-info --context kind-rbac-lab
```

### Create namespace and ServiceAccount
```bash
kubectl create namespace dev-team
kubectl create serviceaccount dev-user -n dev-team
```

### Create a Role (read-only on pods)
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: dev-team
  name: pod-reader
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
```

### Bind the Role to the ServiceAccount
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods-binding
  namespace: dev-team
subjects:
- kind: ServiceAccount
  name: dev-user
  namespace: dev-team
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### Test permissions with `auth can-i`
```bash
# Can the SA list pods in its namespace?
kubectl auth can-i list pods -n dev-team \
  --as=system:serviceaccount:dev-team:dev-user
# → yes

# Can it delete pods?
kubectl auth can-i delete pods -n dev-team \
  --as=system:serviceaccount:dev-team:dev-user
# → no

# Can it list pods in another namespace?
kubectl auth can-i list pods -n default \
  --as=system:serviceaccount:dev-team:dev-user
# → no (Role is namespace-scoped)

# List ALL permissions for a subject
kubectl auth can-i --list \
  --as=system:serviceaccount:dev-team:dev-user -n dev-team
```

### Test from inside a pod (real token)
```bash
kubectl run test-pod \
  --image=curlimages/curl \
  --serviceaccount=dev-user \
  -n dev-team \
  --rm -it -- sh

# Inside the pod
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

# This works (list pods)
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api/v1/namespaces/dev-team/pods

# This fails with 403 (delete pod)
curl -sk -H "Authorization: Bearer $TOKEN" \
  -X DELETE https://kubernetes.default.svc/api/v1/namespaces/dev-team/pods/some-pod
```

---

## ClusterRole — for cluster-scoped resources

Nodes, PersistentVolumes, Namespaces are cluster-scoped — you can't use a regular Role for these.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: node-reader
rules:
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dev-user-node-reader
subjects:
- kind: ServiceAccount
  name: dev-user
  namespace: dev-team
roleRef:
  kind: ClusterRole
  name: node-reader
  apiGroup: rbac.authorization.k8s.io
```

---

## ServiceAccount in Helm Charts

Standard Helm charts scaffold a ServiceAccount with a `create` flag and `annotations`:

```yaml
# values.yaml
serviceAccount:
  create: true
  annotations: {}
  name: "my-app-sa"
```

```yaml
# serviceaccount.yaml template
{{- if .Values.serviceAccount.create -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "my-app.serviceAccountName" . }}
  annotations:
    {{- toYaml .Values.serviceAccount.annotations | nindent 4 }}
{{- end }}
```

### Why the `create` flag?
In some environments the SA already exists (created by the platform team or another chart). `create: false` skips creation without breaking the chart.

### Why the `annotations` field?
Primarily for **cloud provider IAM binding**:

```yaml
# AWS IRSA
annotations:
  eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/my-app-role

# GCP Workload Identity
annotations:
  iam.gke.io/gcp-service-account: my-app@project.iam.gserviceaccount.com
```

### On-prem (Tanzu / kubeadm) — Vault integration
Without a cloud provider, the main use case is **HashiCorp Vault**:

```yaml
annotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "my-app-role"
```

Vault's Kubernetes auth method verifies the pod's SA token against the k8s API to confirm identity, then issues a Vault token with the right policies. It needs a **specific named SA** — you can't do this cleanly with the `default` SA.

### Should you remove it?
Keep it. Even if annotations are empty now:
- The app has its own identity instead of sharing `default`
- Ready for Vault integration without template changes
- Cost is zero — it's a lightweight k8s object

---

## Quick Reference

```bash
# Create SA
kubectl create serviceaccount <name> -n <namespace>

# Test permissions (impersonate)
kubectl auth can-i <verb> <resource> -n <namespace> \
  --as=system:serviceaccount:<namespace>:<sa-name>

# List all permissions for a SA
kubectl auth can-i --list \
  --as=system:serviceaccount:<namespace>:<sa-name> -n <namespace>

# Get SA details
kubectl get serviceaccount <name> -n <namespace> -o yaml

# Cleanup kind cluster
kind delete cluster --name rbac-lab
```

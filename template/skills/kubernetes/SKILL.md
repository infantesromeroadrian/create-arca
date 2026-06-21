---
name: kubernetes
description: Complete guide for Kubernetes including core concepts, deployments, services, ingress, ConfigMaps, Secrets, persistent storage, Helm, debugging, and ML workloads. Use when deploying containerized applications, managing clusters, or orchestrating ML infrastructure.
paths:
  - "**/k8s/**"
  - "**/helm/**"
  - "**/*.yaml"
---

# Kubernetes

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Control Plane                          │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐           │
│  │ API Server  │ │   etcd      │ │ Scheduler   │           │
│  └─────────────┘ └─────────────┘ └─────────────┘           │
│  ┌─────────────────────────────┐                           │
│  │    Controller Manager       │                           │
│  └─────────────────────────────┘                           │
└─────────────────────────────────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
┌───────────────┐ ┌───────────────┐ ┌───────────────┐
│    Node 1     │ │    Node 2     │ │    Node 3     │
│  ┌─────────┐  │ │  ┌─────────┐  │ │  ┌─────────┐  │
│  │ kubelet │  │ │  │ kubelet │  │ │  │ kubelet │  │
│  ├─────────┤  │ │  ├─────────┤  │ │  ├─────────┤  │
│  │ kube-   │  │ │  │ kube-   │  │ │  │ kube-   │  │
│  │ proxy   │  │ │  │ proxy   │  │ │  │ proxy   │  │
│  ├─────────┤  │ │  ├─────────┤  │ │  ├─────────┤  │
│  │  Pods   │  │ │  │  Pods   │  │ │  │  Pods   │  │
│  └─────────┘  │ │  └─────────┘  │ │  └─────────┘  │
└───────────────┘ └───────────────┘ └───────────────┘
```

---

## kubectl Essentials

### Configuration

```bash
# View config
kubectl config view
kubectl config current-context

# Switch context
kubectl config use-context my-cluster

# Set namespace for context
kubectl config set-context --current --namespace=my-namespace

# Multiple kubeconfigs
export KUBECONFIG=~/.kube/config:~/.kube/cluster2.yaml
```

### Common Commands

```bash
# Get resources
kubectl get pods
kubectl get pods -A                    # All namespaces
kubectl get pods -o wide               # More info
kubectl get pods -w                    # Watch
kubectl get all                        # All resource types

# Describe (detailed info)
kubectl describe pod my-pod
kubectl describe node my-node

# Create/Apply
kubectl apply -f manifest.yaml
kubectl apply -f ./manifests/         # Directory
kubectl apply -k ./kustomize/         # Kustomize

# Delete
kubectl delete -f manifest.yaml
kubectl delete pod my-pod
kubectl delete pods --all -n namespace

# Logs
kubectl logs my-pod
kubectl logs my-pod -c container      # Specific container
kubectl logs my-pod -f                # Follow
kubectl logs my-pod --previous        # Previous instance
kubectl logs -l app=myapp             # By label

# Exec into pod
kubectl exec -it my-pod -- /bin/bash
kubectl exec -it my-pod -c container -- sh

# Port forward
kubectl port-forward pod/my-pod 8080:80
kubectl port-forward svc/my-service 8080:80

# Copy files
kubectl cp my-pod:/path/file ./local
kubectl cp ./local my-pod:/path/

# Resource usage
kubectl top pods
kubectl top nodes
```

### Useful Shortcuts

```bash
# Aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgd='kubectl get deployments'
alias kn='kubectl config set-context --current --namespace'

# Quick pod for debugging
kubectl run debug --rm -it --image=busybox -- sh
kubectl run debug --rm -it --image=nicolaka/netshoot -- bash

# Dry run + YAML output
kubectl create deployment nginx --image=nginx --dry-run=client -o yaml

# Explain resources
kubectl explain pod.spec.containers
kubectl explain deployment.spec.strategy
```

---

## Core Resources

### Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  labels:
    app: myapp
    version: v1
spec:
  containers:
    - name: main
      image: nginx:1.25
      ports:
        - containerPort: 80
      resources:
        requests:
          memory: "64Mi"
          cpu: "250m"
        limits:
          memory: "128Mi"
          cpu: "500m"
      livenessProbe:
        httpGet:
          path: /healthz
          port: 80
        initialDelaySeconds: 10
        periodSeconds: 5
      readinessProbe:
        httpGet:
          path: /ready
          port: 80
        initialDelaySeconds: 5
        periodSeconds: 3
      env:
        - name: ENV_VAR
          value: "value"
        - name: SECRET_VAR
          valueFrom:
            secretKeyRef:
              name: my-secret
              key: password
      volumeMounts:
        - name: config-volume
          mountPath: /etc/config
  volumes:
    - name: config-volume
      configMap:
        name: my-config
  restartPolicy: Always
```

### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
  labels:
    app: myapp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: main
          image: myapp:v1.0.0
          ports:
            - containerPort: 8080
          resources:
            requests:
              memory: "256Mi"
              cpu: "500m"
            limits:
              memory: "512Mi"
              cpu: "1000m"
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /ready
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
```

### Deployment Commands

```bash
# Scale
kubectl scale deployment my-deployment --replicas=5

# Update image
kubectl set image deployment/my-deployment main=myapp:v2.0.0

# Rollout status
kubectl rollout status deployment/my-deployment

# Rollout history
kubectl rollout history deployment/my-deployment

# Rollback
kubectl rollout undo deployment/my-deployment
kubectl rollout undo deployment/my-deployment --to-revision=2

# Pause/Resume rollout
kubectl rollout pause deployment/my-deployment
kubectl rollout resume deployment/my-deployment
```

### Service

```yaml
# ClusterIP (internal)
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  type: ClusterIP
  selector:
    app: myapp
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP

---
# NodePort (external via node IP)
apiVersion: v1
kind: Service
metadata:
  name: my-nodeport
spec:
  type: NodePort
  selector:
    app: myapp
  ports:
    - port: 80
      targetPort: 8080
      nodePort: 30080  # 30000-32767

---
# LoadBalancer (cloud)
apiVersion: v1
kind: Service
metadata:
  name: my-loadbalancer
spec:
  type: LoadBalancer
  selector:
    app: myapp
  ports:
    - port: 80
      targetPort: 8080

---
# Headless (for StatefulSets)
apiVersion: v1
kind: Service
metadata:
  name: my-headless
spec:
  clusterIP: None
  selector:
    app: myapp
  ports:
    - port: 80
```

### Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - myapp.example.com
      secretName: myapp-tls
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api-service
                port:
                  number: 80
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend-service
                port:
                  number: 80
```

---

## Configuration

### ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-config
data:
  # Key-value pairs
  DATABASE_HOST: "postgres.default.svc"
  LOG_LEVEL: "info"
  
  # File content
  config.json: |
    {
      "setting1": "value1",
      "setting2": "value2"
    }
```

```bash
# Create from literal
kubectl create configmap my-config \
  --from-literal=KEY1=value1 \
  --from-literal=KEY2=value2

# Create from file
kubectl create configmap my-config --from-file=config.json
kubectl create configmap my-config --from-env-file=.env
```

### Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
type: Opaque
data:
  # Base64 encoded
  username: YWRtaW4=
  password: cGFzc3dvcmQxMjM=
stringData:
  # Plain text (encoded automatically)
  api-key: "my-secret-api-key"
```

```bash
# Create from literal
kubectl create secret generic my-secret \
  --from-literal=username=admin \
  --from-literal=password=secret123

# Create from file
kubectl create secret generic my-secret --from-file=./credentials

# TLS secret
kubectl create secret tls my-tls \
  --cert=tls.crt \
  --key=tls.key

# Docker registry
kubectl create secret docker-registry regcred \
  --docker-server=registry.example.com \
  --docker-username=user \
  --docker-password=pass
```

### Using Config/Secrets

```yaml
spec:
  containers:
    - name: app
      # All keys as env vars
      envFrom:
        - configMapRef:
            name: my-config
        - secretRef:
            name: my-secret
      
      # Specific keys
      env:
        - name: DB_HOST
          valueFrom:
            configMapKeyRef:
              name: my-config
              key: DATABASE_HOST
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: my-secret
              key: password
      
      # As files
      volumeMounts:
        - name: config-vol
          mountPath: /etc/config
        - name: secret-vol
          mountPath: /etc/secrets
          readOnly: true
  
  volumes:
    - name: config-vol
      configMap:
        name: my-config
    - name: secret-vol
      secret:
        secretName: my-secret
```

---

## Storage

### PersistentVolumeClaim

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
    - ReadWriteOnce    # RWO: single node
    # - ReadWriteMany  # RWX: multiple nodes
    # - ReadOnlyMany   # ROX: multiple nodes, read-only
  resources:
    requests:
      storage: 10Gi
  storageClassName: standard  # gp2, fast-ssd, etc.
```

### Using PVC

```yaml
spec:
  containers:
    - name: app
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: my-pvc
```

### StatefulSet (for stateful apps)

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 3
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:15
          ports:
            - containerPort: 5432
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
          env:
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: password
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
```

---

## Jobs & CronJobs

### Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: data-migration
spec:
  completions: 1
  parallelism: 1
  backoffLimit: 3
  activeDeadlineSeconds: 600
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: myapp:migrate
          command: ["python", "migrate.py"]
```

### CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  concurrencyPolicy: Forbid  # Allow, Forbid, Replace
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: backup
              image: backup-tool:latest
              command: ["/backup.sh"]
```

---

## Resource Management

### Resource Quotas

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: namespace-quota
  namespace: my-namespace
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    pods: "50"
    services: "10"
    persistentvolumeclaims: "10"
```

### LimitRange

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
spec:
  limits:
    - type: Container
      default:
        cpu: "500m"
        memory: "256Mi"
      defaultRequest:
        cpu: "100m"
        memory: "128Mi"
      max:
        cpu: "2"
        memory: "2Gi"
      min:
        cpu: "50m"
        memory: "64Mi"
```

### HorizontalPodAutoscaler

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-deployment
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Percent
          value: 10
          periodSeconds: 60
```

---

## Helm

### Basic Commands

```bash
# Add repo
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Search
helm search repo nginx
helm search hub prometheus

# Install
helm install my-release bitnami/nginx
helm install my-release bitnami/nginx -f values.yaml
helm install my-release bitnami/nginx --set replicaCount=3

# List releases
helm list
helm list -A  # All namespaces

# Upgrade
helm upgrade my-release bitnami/nginx -f values.yaml

# Rollback
helm rollback my-release 1

# Uninstall
helm uninstall my-release

# Template (dry run)
helm template my-release bitnami/nginx -f values.yaml
```

### Create Chart

```bash
# Create new chart
helm create mychart

# Structure
mychart/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── _helpers.tpl
│   └── NOTES.txt
└── charts/
```

### values.yaml

```yaml
# values.yaml
replicaCount: 3

image:
  repository: myapp
  tag: "v1.0.0"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: true
  host: myapp.example.com

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi

env:
  LOG_LEVEL: info
```

### Template Example

```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "mychart.fullname" . }}
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "mychart.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "mychart.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          ports:
            - containerPort: 80
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          env:
            {{- range $key, $value := .Values.env }}
            - name: {{ $key }}
              value: {{ $value | quote }}
            {{- end }}
```

---

## ML Workloads

### GPU Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-training
spec:
  restartPolicy: Never
  containers:
    - name: trainer
      image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
      command: ["python", "train.py"]
      resources:
        limits:
          nvidia.com/gpu: 1  # Request 1 GPU
      volumeMounts:
        - name: data
          mountPath: /data
        - name: models
          mountPath: /models
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: training-data
    - name: models
      persistentVolumeClaim:
        claimName: model-storage
  nodeSelector:
    accelerator: nvidia-tesla-v100
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
```

### Training Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: model-training
spec:
  backoffLimit: 2
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: trainer
          image: my-ml-image:latest
          command: ["python", "train.py"]
          args:
            - "--epochs=100"
            - "--batch-size=32"
          resources:
            requests:
              memory: "8Gi"
              cpu: "4"
              nvidia.com/gpu: 1
            limits:
              memory: "16Gi"
              cpu: "8"
              nvidia.com/gpu: 1
          env:
            - name: WANDB_API_KEY
              valueFrom:
                secretKeyRef:
                  name: ml-secrets
                  key: wandb-key
          volumeMounts:
            - name: data
              mountPath: /data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: ml-data
      nodeSelector:
        node-type: gpu
```

### Model Serving

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: model-server
spec:
  replicas: 2
  selector:
    matchLabels:
      app: model-server
  template:
    metadata:
      labels:
        app: model-server
    spec:
      containers:
        - name: server
          image: my-model-server:latest
          ports:
            - containerPort: 8080
          resources:
            requests:
              memory: "2Gi"
              cpu: "1"
            limits:
              memory: "4Gi"
              cpu: "2"
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 30
          volumeMounts:
            - name: model
              mountPath: /models
              readOnly: true
      volumes:
        - name: model
          persistentVolumeClaim:
            claimName: model-storage
---
apiVersion: v1
kind: Service
metadata:
  name: model-server
spec:
  selector:
    app: model-server
  ports:
    - port: 80
      targetPort: 8080
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: model-server-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: model-server
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

---

## Debugging

### Pod Issues

```bash
# Pod not starting
kubectl describe pod my-pod
kubectl get events --sort-by='.lastTimestamp'

# Check logs
kubectl logs my-pod
kubectl logs my-pod --previous

# Debug running pod
kubectl exec -it my-pod -- /bin/sh

# Debug with ephemeral container
kubectl debug my-pod -it --image=busybox

# Check resource usage
kubectl top pod my-pod
```

### Network Issues

```bash
# Test DNS
kubectl run debug --rm -it --image=busybox -- nslookup my-service

# Test connectivity
kubectl run debug --rm -it --image=nicolaka/netshoot -- \
  curl http://my-service:80/health

# Check endpoints
kubectl get endpoints my-service

# Check service
kubectl describe svc my-service
```

### Common Issues

| Symptom | Check | Fix |
|---------|-------|-----|
| ImagePullBackOff | Image name, registry auth | Fix image or add imagePullSecrets |
| CrashLoopBackOff | Logs, liveness probe | Fix app or probe config |
| Pending | Events, resources, nodeSelector | Add resources or fix selectors |
| OOMKilled | Memory limits | Increase limits or optimize app |
| Evicted | Node pressure | Increase cluster capacity |

---

## Anti-patterns

| [FAIL] Don't | [PASS] Do |
|----------|-------|
| Use `latest` tag | Use specific image tags |
| Skip resource limits | Always set requests & limits |
| Store secrets in ConfigMaps | Use Secrets (or external vault) |
| Hardcode config in images | Use ConfigMaps and env vars |
| Single replica for prod | Use multiple replicas + PDB |
| Skip health probes | Add liveness & readiness probes |
| Run as root | Use securityContext, non-root |
| Ignore pod disruption | Use PodDisruptionBudget |

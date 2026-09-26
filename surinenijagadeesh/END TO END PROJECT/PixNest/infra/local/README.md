# Run pixnest locally on Kubernetes (minikube)

A full local end-to-end: the real Helm chart deployed to a real (local) Kubernetes cluster.
Postgres runs in-cluster as a StatefulSet (shipped in the chart, same as EKS); only MinIO is a
local-only stand-in for S3. No AWS account needed.

## Prerequisites
Docker running, plus `minikube`, `kubectl`, and `helm`.

## 1. Start the cluster and the ingress controller
```bash
minikube start --driver=docker
minikube addons enable ingress
```

## 2. Build the images and load them into the cluster
```bash
docker build -t pixnest-backend:local  ./backend
docker build -t pixnest-frontend:local ./frontend
minikube image load pixnest-backend:local
minikube image load pixnest-frontend:local
```

## 3. Deploy the local dependency (MinIO + bucket)
```bash
kubectl apply -f infra/local/local-deps.yaml
kubectl -n pixnest rollout status deploy/minio
```

## 4. Deploy the app with the local values overlay
The chart brings its own Postgres (a StatefulSet with a PVC).
```bash
helm upgrade --install pixnest-postgres infra/helm/postgres -n pixnest --create-namespace
helm upgrade --install pixnest-backend  infra/helm/backend  -n pixnest -f infra/helm/backend/values-local.yaml
helm upgrade --install pixnest-frontend infra/helm/frontend -n pixnest -f infra/helm/frontend/values-local.yaml
kubectl -n pixnest rollout status statefulset/pixnest-postgres
kubectl -n pixnest rollout status deploy/pixnest-backend
kubectl -n pixnest rollout status deploy/pixnest-frontend
```

## 5. Open it
```bash
# Simplest: port-forward the frontend and call the API through it is not enough (Ingress does
# the routing), so forward the Ingress controller instead, or use the minikube ingress IP.
kubectl -n pixnest get ingress
minikube ip            # then browse http://<minikube-ip>/  and  http://<minikube-ip>/docs
```
On Docker-driver minikube, run `minikube tunnel` in a separate terminal so the ingress IP is
reachable from the host, then open `http://127.0.0.1/` and `http://127.0.0.1/docs`.

## What this proves
The same Helm chart that targets EKS also runs here, including the Postgres StatefulSet and its
PVC. Ingress path-routing (`/` to the frontend, `/api` and `/docs` to the backend), probes, the
ConfigMap/Secret, and the upload path (file to MinIO, metadata to Postgres) all work exactly as
they will in the cloud. The only differences are where S3 lives (MinIO here, managed S3 on AWS)
and how the backend authenticates to it (static MinIO keys here, EKS Pod Identity on AWS).

## Tear down
```bash
helm -n pixnest uninstall pixnest
kubectl delete -f infra/local/local-deps.yaml
minikube stop     # or: minikube delete
```


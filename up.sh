#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

export BUILDX_NO_DEFAULT_ATTESTATIONS=1
docker build -t assessment-api:local .
docker build -t assessment-image-job:local job

if kind get clusters 2>/dev/null | grep -x assessment >/dev/null; then
  cluster_existed=yes
  echo "cluster already exists"
else
  cluster_existed=no
  kind create cluster --name assessment --config kind.yaml
fi

kind load docker-image assessment-api:local assessment-image-job:local --name assessment

helm upgrade --install monitoring \
  oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack --version 92.22.0 \
  --kube-context kind-assessment --namespace monitoring --create-namespace \
  --values k8s/monitoring/values.yaml --wait --timeout 10m

kubectl --context kind-assessment apply -f k8s/app/namespace.yaml

if kubectl --context kind-assessment -n assessment get secret postgres >/dev/null 2>&1; then
  echo "secret/postgres already exists"
else
  kubectl --context kind-assessment -n assessment create secret generic postgres \
    --from-literal=username=app \
    --from-literal=password="$(openssl rand -hex 16)"
fi

if kubectl --context kind-assessment -n assessment get secret minio >/dev/null 2>&1; then
  echo "secret/minio already exists"
else
  kubectl --context kind-assessment -n assessment create secret generic minio \
    --from-literal=root-user=admin \
    --from-literal=root-password="$(openssl rand -hex 16)"
fi

if kubectl --context kind-assessment -n assessment get secret keycloak-admin >/dev/null 2>&1; then
  echo "secret/keycloak-admin already exists"
else
  kubectl --context kind-assessment -n assessment create secret generic keycloak-admin \
    --from-literal=password="$(openssl rand -hex 16)"
fi

kubectl --context kind-assessment -n assessment create configmap keycloak-realm \
  --from-file=realm-export.json=keycloak/realm-export.json \
  --dry-run=client -o yaml |
  kubectl --context kind-assessment apply -f -

kubectl --context kind-assessment apply -k k8s/app

if [ "$cluster_existed" = yes ]; then
  kubectl --context kind-assessment -n assessment rollout restart deployment/api
fi

kubectl --context kind-assessment -n assessment rollout status statefulset/postgres --timeout=10m
kubectl --context kind-assessment -n assessment rollout status statefulset/minio --timeout=10m
kubectl --context kind-assessment -n assessment rollout status deployment/keycloak --timeout=10m
kubectl --context kind-assessment -n assessment rollout status deployment/api --timeout=10m

kubectl --context kind-assessment -n assessment exec -i postgres-0 -- sh -c \
  'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d images' < job/schema.sql

for name in landsat8.jpg sentinel2a.jpg spot6.jpg; do
  kubectl --context kind-assessment -n assessment exec -i minio-0 -- sh -c '
    export MC_HOST_store="http://$MINIO_ROOT_USER:$MINIO_ROOT_PASSWORD@127.0.0.1:9000"
    mc pipe --part-size 16MiB "store/images/$1"
  ' sh "$name" < "src/main/resources/static/thumbnails/$name"
done

kubectl --context kind-assessment apply -k k8s/monitoring

kubectl config use-context kind-assessment

#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CLUSTER_NAME="demo"
source "${SCRIPT_DIR}/jozu-hub-product/tools/local-dev/global.sh"

if [ "$(uname)" == "Darwin" ]; then
  IP_ADDR="$(ipconfig getifaddr en0)"
  if [ -z "$IP_ADDR" ]; then
    IP_ADDR="$(ipconfig getifaddr en1)"
  fi
else
  IP_ADDR=$(hostname -I | cut -f 1 -d ' ')
fi

echo "Updating CoreDNS to resolve *.${CLUSTER_URL} to ${IP_ADDR}"

cat <<EOF | kubectl apply --server-side --force-conflicts -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
      errors
      health {
        lameduck 5s
      }
      ready
      kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
        ttl 30
      }
      prometheus :9153
      template IN A ${CLUSTER_URL} {
        answer "{{ .Name }} 60 IN A ${IP_ADDR}"
      }
      forward . /etc/resolv.conf {
        max_concurrent 1000
      }
      cache 30
      loop
      reload
      loadbalance
    }
EOF

kubectl delete pod -l k8s-app=kube-dns -n kube-system
echo "Waiting for CoreDNS to be ready..."
kubectl rollout status deploy/coredns -n kube-system --timeout=30s

echo "Restarting Hub pods to pick up new DNS..."
kubectl rollout restart deploy/jozu-hub-api -n jozu-hub
kubectl rollout restart deploy/jozu-hub-workers -n jozu-hub
kubectl rollout status deploy/jozu-hub-api -n jozu-hub --timeout=120s
kubectl rollout status deploy/jozu-hub-workers -n jozu-hub --timeout=120s

echo "Updating /etc/hosts..."
"${SCRIPT_DIR}/jozu-hub-product/tools/local-dev/setup-local-dns.sh" update

echo "DNS updated."

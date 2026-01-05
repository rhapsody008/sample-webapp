#!/bin/bash

PROJECT_NAME="nkp-devops-lab"
PROJECT_NAMESPACE="nkp-devops-lab"
REPO_URL_PREFIX="https://gitlab.com/devops-lab5952301/gitops-"
SECRET_NAME="git"
BRANCH="main"
OUTPUT_PROJECT_FILE="project.yaml"
OUTPUT_GITOPS_FILE="gitops-sources.yaml"
NKP_WORKLOAD_CLUSTER_NAME="nkp-dev-01"

MIDDLEWARE_NAME="stripprefixes"
INGRESS_NAME="nkp-devops-lab-web"
INGRESS_CLASS="kommander-traefik"
TLS_ENABLED="false"   # "true" or "false"
SERVICE_PORT=8080
OUTPUT_INGRESS_FILE="ingress.yaml"

START=1
END=2

###########
# Project #
###########

echo "Generating project YAML..."

: > "$OUTPUT_PROJECT_FILE"  # truncate existing file

cat > "$OUTPUT_PROJECT_FILE" <<EOF
---
apiVersion: workspaces.kommander.mesosphere.io/v1alpha1
kind: Project
metadata:
  annotations:
    kommander.mesosphere.io/description: "Project space for the NKP DevOps Lab"
    kommander.mesosphere.io/display-name: "NKP DevOps Lab Project"
  name: ${PROJECT_NAME}
  namespace: kommander-default-workspace
spec:
  namespaceName: ${PROJECT_NAMESPACE}
  placement:
    clusters:
    - name: ${NKP_WORKLOAD_CLUSTER_NAME}
  workspaceRef:
    name: default-workspace
EOF

echo "Generated project YAML: $OUTPUT_PROJECT_FILE"

###################
#  GitOps Sources #
###################

: > "$OUTPUT_GITOPS_FILE"  # truncate existing file

for i in $(seq "$START" "$END"); do
  USER_ID=$(printf "user%02d" "$i")

  cat >> "$OUTPUT_GITOPS_FILE" <<EOF

---
apiVersion: dispatch.d2iq.io/v1alpha2
kind: GitopsRepository
metadata:
  name: ${USER_ID}
  namespace: ${PROJECT_NAMESPACE}
spec:
  cloneUrl: ${REPO_URL_PREFIX}${USER_ID}.git
  secret: ${SECRET_NAME}
  template:
    ref:
      branch: ${BRANCH}
EOF
done

echo "Generated GitOps Source YAML: $OUTPUT_GITOPS_FILE"

#############
#  Ingress #
############

: > "$OUTPUT_INGRESS_FILE"

# --- Middleware ---
cat >> "$OUTPUT_INGRESS_FILE" <<EOF
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: ${MIDDLEWARE_NAME}
  namespace: ${PROJECT_NAMESPACE}
spec:
  stripPrefix:
    prefixes:
EOF
for i in $(seq "$START" "$END"); do
  printf "      - /user%02d\n" "$i" >> "$OUTPUT_INGRESS_FILE"
done

# separator
echo "" >> "$OUTPUT_INGRESS_FILE"
echo "---" >> "$OUTPUT_INGRESS_FILE"

# --- Ingress ---
cat >> "$OUTPUT_INGRESS_FILE" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${INGRESS_NAME}
  namespace: ${PROJECT_NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: ${INGRESS_CLASS}
    traefik.ingress.kubernetes.io/router.tls: "${TLS_ENABLED}"
    traefik.ingress.kubernetes.io/router.middlewares: ${PROJECT_NAMESPACE}-${MIDDLEWARE_NAME}@kubernetescrd
spec:
  rules:
EOF

for i in $(seq "$START" "$END"); do
  USER="user$(printf "%02d" "$i")"
  cat >> "$OUTPUT_INGRESS_FILE" <<EOF
  - http:
      paths:
      - path: /${USER}
        pathType: Exact
        backend:
          service:
            name: ${USER}-web
            port:
              number: ${SERVICE_PORT}
EOF
done

echo "Generated Ingress File: $OUTPUT_INGRESS_FILE"

echo "!!Apply project & gitops in Mgmt Cluster and Ingress & secret in Workload Cluster!!"
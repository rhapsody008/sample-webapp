#!/bin/bash

# --- Variables ---
PROJECT_NAME="nkp-devops-lab"
PROJECT_NAMESPACE="nkp-devops-lab"
REPO_URL_PREFIX="https://gitlab.ntnxlab.local/lab/gitops-"
SECRET_NAME="git"
BRANCH="main"

# Output Files
OUTPUT_PROJECT_FILE="project.yaml"
OUTPUT_GITOPS_FILE="gitops-sources.yaml"
OUTPUT_SECRET_FILE="secret.yaml"
OUTPUT_INGRESS_FILE="ingress.yaml"

# Cluster / Ingress Config
NKP_WORKLOAD_CLUSTER_NAME="nkp-dev"
MIDDLEWARE_NAME="stripprefixes"
INGRESS_NAME="nkp-devops-lab-web"
INGRESS_CLASS="kommander-traefik"
TLS_ENABLED="false"
SERVICE_PORT=8080

# --- PAT INPUT ---
# You can set this as an environment variable before running: export GITLAB_PAT="your_token_here"
# Or edit the line below:
GITLAB_PAT="${GITLAB_PAT:-your_token_here}"
GITLAB_USER="root"

# Encode to Base64 for K8s Secret
GITLAB_PAT_BASE64=$(echo -n "$GITLAB_PAT" | base64)
GITLAB_USER_BASE64=$(echo -n "$GITLAB_USER" | base64)

# Range for users
START=1
END=3

###########
# Project #
###########

echo "Generating project YAML..."
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

##########
# Secret #
##########

echo "Generating secret YAML..."
cat > "$OUTPUT_SECRET_FILE" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${PROJECT_NAMESPACE}
type: Opaque
data:
  password: ${GITLAB_PAT_BASE64}
  username: ${GITLAB_USER_BASE64}
EOF

###################
#  GitOps Sources #
###################

echo "Generating GitOps Source YAML..."
: > "$OUTPUT_GITOPS_FILE"
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

#############
#  Ingress #
############

echo "Generating Ingress File..."
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

echo -e "\n---" >> "$OUTPUT_INGRESS_FILE"

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

echo "------------------------------------------------------------"
echo "Done!"
echo "Mgmt Cluster:    kubectl apply -f $OUTPUT_PROJECT_FILE -f $OUTPUT_GITOPS_FILE"
echo "Workload Cluster: kubectl apply -f $OUTPUT_SECRET_FILE -f $OUTPUT_INGRESS_FILE"
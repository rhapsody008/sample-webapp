#!/bin/bash

# --- CONFIGURATION ---
GITLAB_URL="https://gitlab.com"
PRIVATE_TOKEN="glpat-MyZVqp522nSwGm8W5P6vc286MQp1OmpiMXVzCw.01.1208so8zv" # Requires 'api' scope
PARENT_NAMESPACE_ID="121715013"
NUM_USERS=2

# --- LOAD LOCAL FILES ---
TEMPLATE_C=$(cat ./ci-templates/pipeline.yaml)
DOCKER_C=$(cat ./goapp/Dockerfile)
SERVER_C=$(cat ./goapp/main.go)
WEBAPP_C=$(cat ./gitops/webapp.yaml)
KUSTOM_C=$(cat ./gitops/kustomization.yaml)

# --- CREATE CI-TEMPLATES REPO ---
echo "Creating global ci-templates repository..."
TEMPLATE_RES=$(curl -k --silent --request POST "$GITLAB_URL/api/v4/projects" \
    --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
    --data "name=ci-templates&namespace_id=$PARENT_NAMESPACE_ID&initialize_with_readme=true")

TEMPLATE_ID=$(echo $TEMPLATE_RES | jq -r '.id')
# Capture the namespace path for use in CI includes later
NAMESPACE_PATH=$(echo $TEMPLATE_RES | jq -r '.namespace.full_path')

# Upload pipeline.yaml to ci-templates
PAYLOAD_TEMPLATE=$(jq -n --arg content "$TEMPLATE_C" \
    '{branch: "main", commit_message: "Add base pipeline template", actions: [
        {action: "create", file_path: "pipeline.yaml", content: $content}
    ]}')

curl -k --silent --request POST "$GITLAB_URL/api/v4/projects/$TEMPLATE_ID/repository/commits" \
    --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
    --header "Content-Type: application/json" \
    --data "$PAYLOAD_TEMPLATE"

echo "ci-templates setup complete."

# --- EXECUTION LOOP ---
for i in $(seq -f "%02g" 1 $NUM_USERS); do
    APP_NAME="webapp-user$i"
    GITOPS_NAME="gitops-user$i"
    echo "------------------------------------------------"
    echo "Setting up environment for User $i..."

    # 1. Create GitOps Project
    GITOPS_RES=$(curl -k --silent --request POST "$GITLAB_URL/api/v4/projects" \
        --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
        --data "name=$GITOPS_NAME&namespace_id=$PARENT_NAMESPACE_ID&initialize_with_readme=false")
    GITOPS_ID=$(echo $GITOPS_RES | jq -r '.id')
    GITOPS_PATH=$(echo $GITOPS_RES | jq -r '.path_with_namespace')

    # 3. Create WebApp Project
    APP_RES=$(curl -k --silent --request POST "$GITLAB_URL/api/v4/projects" \
        --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
        --data "name=$APP_NAME&namespace_id=$PARENT_NAMESPACE_ID")
    APP_ID=$(echo $APP_RES | jq -r '.id')

    # 4. Define .gitlab-ci.yml content using your template and injecting $i
    CI_CONFIG="include:
  - project: '\${CI_PROJECT_NAMESPACE}/ci-templates'
    file: 'pipeline.yaml'
    inputs:
      username: user$i"

    # 5. Push Files to WebApp Repo (Go files + the new .gitlab-ci.yml)
    PAYLOAD_APP=$(jq -n --arg docker "$DOCKER_C" --arg server "$SERVER_C" --arg ci "$CI_CONFIG" \
        '{branch: "main", commit_message: "Initial app files and CI config", actions: [
            {action: "create", file_path: "Dockerfile", content: $docker},
            {action: "create", file_path: "main.go", content: $server},
            {action: "create", file_path: ".gitlab-ci.yml", content: $ci}
        ]}')
    curl -k --silent --request POST "$GITLAB_URL/api/v4/projects/$APP_ID/repository/commits" \
        --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" --header "Content-Type: application/json" --data "$PAYLOAD_APP"

    # 5. Push Files to GitOps Repo (K8s Manifests)
    PAYLOAD_GITOPS=$(jq -n --arg webapp "$WEBAPP_C" --arg kustom "$KUSTOM_C" \
        '{branch: "main", commit_message: "Initial GitOps manifests", actions: [
            {action: "create", file_path: "webapp.yaml", content: $webapp},
            {action: "create", file_path: "kustomization.yaml", content: $kustom}
        ]}')
    curl -k --silent --request POST "$GITLAB_URL/api/v4/projects/$GITOPS_ID/repository/commits" \
        --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" --header "Content-Type: application/json" --data "$PAYLOAD_GITOPS"


    echo "Success: User $i fully provisioned."
done
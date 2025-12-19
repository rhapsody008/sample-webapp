#!/bin/bash

# --- CONFIGURATION ---
GITLAB_URL="https://10.38.193.146"
PRIVATE_TOKEN="glpat-j_YkPITj2c94C8R2ojQMYm86MQp1OjIH.01.0w0adc3kd" # Requires 'api' scope
PARENT_NAMESPACE_ID="3"
NUM_USERS=2

# --- LOAD LOCAL FILES ---
DOCKER_C=$(cat ./webapp/Dockerfile)
SERVER_C=$(cat ./webapp/server.js)
PACKAGE_C=$(cat ./webapp/package.json)
WEBAPP_C=$(cat ./gitops/webapp.yaml)
KUSTOM_C=$(cat ./gitops/kustomization.yaml)

# --- EXECUTION LOOP ---
for i in $(seq -f "%02g" 1 $NUM_USERS); do
    APP_NAME="webapp-user$i"
    GITOPS_NAME="gitops-user$i"
    echo "------------------------------------------------"
    echo "Setting up environment for User $i..."

    # 1. Create GitOps Project
    GITOPS_RES=$(curl -k --silent --request POST "$GITLAB_URL/api/v4/projects" \
        --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
        --data "name=$GITOPS_NAME&namespace_id=$PARENT_NAMESPACE_ID&initialize_with_readme=true")
    GITOPS_ID=$(echo $GITOPS_RES | jq -r '.id')
    GITOPS_PATH=$(echo $GITOPS_RES | jq -r '.path_with_namespace')

    # 2. Create Project Access Token for this GitOps Repo
    # This token expires in 365 days and has 'Developer' (30) access
    TOKEN_RES=$(curl -k --silent --request POST "$GITLAB_URL/api/v4/projects/$GITOPS_ID/access_tokens" \
        --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
        --data "name=GitOps-Push-Token&scopes[]=write_repository&access_level=30")
    GITOPS_PUSH_TOKEN=$(echo $TOKEN_RES | jq -r '.token')

    # 3. Create WebApp Project
    APP_RES=$(curl -k --silent --request POST "$GITLAB_URL/api/v4/projects" \
        --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
        --data "name=$APP_NAME&namespace_id=$PARENT_NAMESPACE_ID")
    APP_ID=$(echo $APP_RES | jq -r '.id')

    # 4. Push Files to WebApp Repo (NodeJS + Docker)
    PAYLOAD_APP=$(jq -n --arg docker "$DOCKER_C" --arg server "$SERVER_C" --arg pack "$PACKAGE_C" \
        '{branch: "main", commit_message: "Initial app files", actions: [
            {action: "create", file_path: "Dockerfile", content: $docker},
            {action: "create", file_path: "server.js", content: $server},
            {action: "create", file_path: "package.json", content: $pack}
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

    # 6. Inject Variables into WebApp Repo
    REPO_URL="${GITLAB_URL#*//}/$GITOPS_PATH.git"
    curl -k --silent --request POST "$GITLAB_URL/api/v4/projects/$APP_ID/variables" \
        --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" --data "key=GITOPS_TOKEN&value=$GITOPS_PUSH_TOKEN&masked=true"
    curl -k --silent --request POST "$GITLAB_URL/api/v4/projects/$APP_ID/variables" \
        --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" --data "key=GITOPS_REPO_URL&value=$REPO_URL"

    echo "Success: User $i fully provisioned."
done
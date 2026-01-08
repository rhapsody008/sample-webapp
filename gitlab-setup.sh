#!/bin/bash

# --- 1. CONFIGURATION ---
PAT="glpat-IseIv8j-0OVexZkzgsrPC286MQp1OjEH.01.0w1lfnadv"
GITLAB_URL="https://gitlab.ntnxlab.local"
REGISTRY_URL="registry.ntnxlab.local"
REGISTRY_PASSWORD="Harbor12345"
VM_SSH="nutanix@10.55.11.170"  # Update with your VM SSH user/IP
GROUP_NAME="lab"
NUM_USERS=3

echo "Starting GitLab Lab Setup..."

# Error handling function
check_status() {
    if [ $? -ne 0 ]; then
        echo "Error during: $1. Exiting."
        exit 1
    fi
}

# --- 2. ENSURE LOCAL FILES EXIST ---
if [[ ! -f "./ci-templates/pipeline.yaml" || ! -f "./gitops/webapp.yaml" || ! -f "./gitops/kustomization.yaml" ]]; then
    echo "Error: Required template files not found locally."
    exit 1
fi

# --- 3. CREATE GROUP VIA API (FIRST STEP) ---
echo "Checking/Creating group '$GROUP_NAME'..."
GROUP_ID=$(curl -k --silent --header "PRIVATE-TOKEN: $PAT" "$GITLAB_URL/api/v4/groups" | jq -r ".[] | select(.path==\"$GROUP_NAME\") | .id")

if [ -z "$GROUP_ID" ] || [ "$GROUP_ID" == "null" ]; then
    GROUP_RES=$(curl -k --silent --request POST --header "PRIVATE-TOKEN: $PAT" \
         --data "name=$GROUP_NAME&path=$GROUP_NAME&visibility=private" \
         "$GITLAB_URL/api/v4/groups")
    GROUP_ID=$(echo $GROUP_RES | jq -r '.id')
    echo "Created Group: $GROUP_NAME (ID: $GROUP_ID)"
else
    echo "Group already exists (ID: $GROUP_ID)"
fi
check_status "Group creation"

# --- 4. RETRIEVE GROUP REGISTRATION TOKEN FROM VM ---
# This pulls the specific token for the 'lab' group using the Rails console
echo "Retrieving Group Runner Registration Token from VM..."
GROUP_RUNNER_TOKEN=$(ssh $VM_SSH "sudo gitlab-rails runner \"print Group.find($GROUP_ID).runners_token\"" 2>/dev/null)

if [ -z "$GROUP_RUNNER_TOKEN" ]; then
    echo "Error: Failed to retrieve Group Runner Token via SSH."
    exit 1
fi

# --- 5. VM CONFIGURATION: SSL & RUNNER REGISTRATION ---
echo "Configuring SSL and registering Group Runner on VM..."
ssh $VM_SSH << EOF
  # Setup Registry SSL
  openssl s_client -showcerts -connect ${REGISTRY_URL}:443 </dev/null 2>/dev/null | openssl x509 -outform PEM > /tmp/ca.crt
  sudo mkdir -p /etc/docker/certs.d/${REGISTRY_URL}/
  sudo cp /tmp/ca.crt /etc/docker/certs.d/${REGISTRY_URL}/ca.crt
  sudo systemctl restart docker

  # Install GitLab Runner if not present
  if ! command -v gitlab-runner &> /dev/null; then
      curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash
      sudo apt-get install -y gitlab-runner
  fi

  # Register Runner for the Group (Idempotent check by description)
  if ! sudo gitlab-runner list 2>&1 | grep -q "group-lab-runner"; then
      sudo gitlab-runner register --non-interactive --url "$GITLAB_URL/" --registration-token "$GROUP_RUNNER_TOKEN" \
        --executor "docker" --docker-image "alpine" --docker-privileged \
        --docker-volumes "/etc/docker/certs.d:/etc/docker/certs.d:ro" \
        --tag-list "labci" --description "group-lab-runner"
  fi

  # Set Concurrency
  sudo sed -i 's/^concurrent = .*/concurrent = 15/' /etc/gitlab-runner/config.toml
  sudo systemctl restart gitlab-runner
EOF
check_status "VM Infrastructure configuration"

# --- 6. SET GROUP CI/CD VARIABLES (REFACTORED FOR COMPATIBILITY) ---
echo "Setting Group CI/CD Variables..."
BASE64_AUTH=$(echo -n "root:$PAT" | base64)
DOCKER_CONFIG_VALUE="{\"auths\":{\"$REGISTRY_URL\":{\"auth\":\"$BASE64_AUTH\"}}}"

set_group_var() {
    local KEY=$1
    local VAL=$2
    # Try PUT (update) first, if 404, then POST (create)
    local STATUS=$(curl -k --silent --request PUT --header "PRIVATE-TOKEN: $PAT" \
        "$GITLAB_URL/api/v4/groups/$GROUP_ID/variables/$KEY" --form "value=$VAL" -w "%{http_code}" -o /dev/null)
    
    if [ "$STATUS" == "404" ]; then
        curl -k --silent --request POST --header "PRIVATE-TOKEN: $PAT" \
            "$GITLAB_URL/api/v4/groups/$GROUP_ID/variables" --form "key=$KEY" --form "value=$VAL" > /dev/null
    fi
}

set_group_var "GITOPS_ACCESS_TOKEN" "$PAT"
set_group_var "REGISTRY_PASSWORD" "$REGISTRY_PASSWORD"
set_group_var "DOCKER_AUTH_CONFIG" "$DOCKER_CONFIG_VALUE"

# --- 7. PROVISION REPOSITORIES FROM LOCAL FILES ---
TEMPLATE_C=$(cat ./ci-templates/pipeline.yaml)
WEBAPP_C=$(cat ./gitops/webapp.yaml)
KUSTOM_C=$(cat ./gitops/kustomization.yaml)

# Provision ci-templates Repo
echo "Provisioning ci-templates..."
TEMPLATE_ID=$(curl -k --silent --header "PRIVATE-TOKEN: $PAT" "$GITLAB_URL/api/v4/groups/$GROUP_ID/projects" | jq -r '.[] | select(.name=="ci-templates") | .id')

if [ -z "$TEMPLATE_ID" ] || [ "$TEMPLATE_ID" == "null" ]; then
    TEMPLATE_ID=$(curl -k --silent --request POST "$GITLAB_URL/api/v4/projects" --header "PRIVATE-TOKEN: $PAT" \
        --data "name=ci-templates&namespace_id=$GROUP_ID&initialize_with_readme=true" | jq -r '.id')
fi

jq -n --arg content "$TEMPLATE_C" '{branch: "main", commit_message: "Add pipeline", actions: [{action: "create", file_path: "pipeline.yaml", content: $content}]}' | \
curl -k --silent --request POST "$GITLAB_URL/api/v4/projects/$TEMPLATE_ID/repository/commits" \
    --header "PRIVATE-TOKEN: $PAT" --header "Content-Type: application/json" --data @- > /dev/null

# Provision User Repos
for i in $(seq -f "%02g" 1 $NUM_USERS); do
    APP_NAME="webapp-user$i"
    GITOPS_NAME="gitops-user$i"
    echo "Processing User $i..."

    # Create GitOps Repo
    G_ID=$(curl -k --silent --header "PRIVATE-TOKEN: $PAT" "$GITLAB_URL/api/v4/groups/$GROUP_ID/projects" | jq -r ".[] | select(.name==\"$GITOPS_NAME\") | .id")
    if [ -z "$G_ID" ] || [ "$G_ID" == "null" ]; then
        G_ID=$(curl -k --silent --request POST "$GITLAB_URL/api/v4/projects" --header "PRIVATE-TOKEN: $PAT" \
            --data "name=$GITOPS_NAME&namespace_id=$GROUP_ID&initialize_with_readme=false&visibility=public" | jq -r '.id')
    fi

    # Create WebApp Repo
    A_ID=$(curl -k --silent --header "PRIVATE-TOKEN: $PAT" "$GITLAB_URL/api/v4/groups/$GROUP_ID/projects" | jq -r ".[] | select(.name==\"$APP_NAME\") | .id")
    if [ -z "$A_ID" ] || [ "$A_ID" == "null" ]; then
        A_ID=$(curl -k --silent --request POST "$GITLAB_URL/api/v4/projects" --header "PRIVATE-TOKEN: $PAT" \
            --data "name=$APP_NAME&namespace_id=$GROUP_ID" | jq -r '.id')
    fi

    # Commit WebApp CI
    CI_CONFIG="include:
  - project: '\${CI_PROJECT_NAMESPACE}/ci-templates'
    file: 'pipeline.yaml'
    inputs:
      username: user$i"
    jq -n --arg ci "$CI_CONFIG" '{branch: "main", commit_message: "Add CI", actions: [{action: "create", file_path: ".gitlab-ci.yml", content: $ci}]}' | \
    curl -k --silent --request POST "$GITLAB_URL/api/v4/projects/$A_ID/repository/commits" --header "PRIVATE-TOKEN: $PAT" --header "Content-Type: application/json" --data @- > /dev/null

    # Commit GitOps Manifests
    jq -n --arg webapp "$WEBAPP_C" --arg kustom "$KUSTOM_C" \
        '{branch: "main", commit_message: "Add manifests", actions: [
            {action: "create", file_path: "webapp.yaml", content: $webapp},
            {action: "create", file_path: "kustomization.yaml", content: $kustom}
        ]}' | curl -k --silent --request POST "$GITLAB_URL/api/v4/projects/$G_ID/repository/commits" --header "PRIVATE-TOKEN: $PAT" --header "Content-Type: application/json" --data @- > /dev/null

    echo "User $i provisioning complete."
done

echo "---------------------------------------------------"
echo "Setup Completed."
echo "---------------------------------------------------"
#!/bin/bash

# --- CONFIGURATION ---
GITLAB_URL="https://gitlab.com"
PRIVATE_TOKEN="" 
PARENT_NAMESPACE_ID="121715013"
NUM_USERS=2

echo "Starting cleanup for Namespace ID: $PARENT_NAMESPACE_ID"

# 1. DELETE CI-TEMPLATES REPO
# We search for the project within the namespace to get its ID safely
echo "Searching for ci-templates..."
TEMPLATE_SEARCH=$(curl -k --silent --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
    "$GITLAB_URL/api/v4/groups/$PARENT_NAMESPACE_ID/projects?search=ci-templates")

TEMPLATE_ID=$(echo $TEMPLATE_SEARCH | jq -r '.[] | select(.name=="ci-templates") | .id')

if [ -n "$TEMPLATE_ID" ] && [ "$TEMPLATE_ID" != "null" ]; then
    echo "Deleting ci-templates (ID: $TEMPLATE_ID)..."
    curl -k --silent --request DELETE --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
        "$GITLAB_URL/api/v4/projects/$TEMPLATE_ID"
    echo "Done."
else
    echo "ci-templates not found. Skipping."
fi

# 2. DELETE USER REPOS (WebApp and GitOps)
for i in $(seq -f "%02g" 1 $NUM_USERS); do
    APP_NAME="webapp-user$i"
    GITOPS_NAME="gitops-user$i"
    
    echo "------------------------------------------------"
    echo "Cleaning up User $i repositories..."

    # Get project IDs for the app and gitops repos
    USER_PROJECTS=$(curl -k --silent --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
        "$GITLAB_URL/api/v4/groups/$PARENT_NAMESPACE_ID/projects?search=user$i")

    # Delete WebApp
    APP_ID=$(echo $USER_PROJECTS | jq -r ".[] | select(.name==\"$APP_NAME\") | .id")
    if [ -n "$APP_ID" ] && [ "$APP_ID" != "null" ]; then
        echo "Deleting $APP_NAME (ID: $APP_ID)..."
        curl -k --silent --request DELETE --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
            "$GITLAB_URL/api/v4/projects/$APP_ID"
    fi

    # Delete GitOps
    GITOPS_ID=$(echo $USER_PROJECTS | jq -r ".[] | select(.name==\"$GITOPS_NAME\") | .id")
    if [ -n "$GITOPS_ID" ] && [ "$GITOPS_ID" != "null" ]; then
        echo "Deleting $GITOPS_NAME (ID: $GITOPS_ID)..."
        curl -k --silent --request DELETE --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
            "$GITLAB_URL/api/v4/projects/$GITOPS_ID"
    fi
done

echo "------------------------------------------------"
echo "Cleanup complete."
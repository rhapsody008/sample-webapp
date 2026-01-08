# DevOps Lab Setup

## Prerequisite
Gitlab, Harbor, NKP is running

a gitlab VM & a harbor VM already available after the script below has run

https://github.com/WinsonSou/nkp-bootstrap-from-scratch/blob/main/scripts/gitlab-install.sh

https://github.com/WinsonSou/nkp-bootstrap-from-scratch/blob/main/scripts/harbor-install.sh

## Setup 
*can manually copy and run the script as test*
```
sudo GITLAB_FQDN=gitlab.ntnxlab.local DOMAIN_NAME=ntnxlab.local GITLAB_ROOT_PASSWORD=ntnx/4NKP ./gitlab-install.sh

sudo REGISTRY_FQDN=registry.ntnxlab.local DOMAIN_NAME=ntnxlab.local HARBOR_URL=http://10.55.251.38/workshop_staging/wskn-nkp/images/harbor-offline-installer-v2.14.1.tgz ./harbor-install.sh
```

1. In Gitlab UI, Create PAT (sign in as root:ntnx/4NKP)
glpat-IseIv8j-0OVexZkzgsrPC286MQp1OjEH.01.0w1lfnadv

2. input variables and run `gitlab-setup.sh` from local laptop for the following:
- install & register gitlab runner 
- inject harbor public cert into gitlab 
- create group, group variables, ci template repo, webapp repo, gitops repo

3. private registry setup:
push `docker:24.0.5`, `docker:24.0.5-dind`, `line/kubectl-kustomize:latest` into private registry
run the following on registry VM:
```
docker pull docker:24.0.5
docker tag docker:24.0.5 registry.ntnxlab.local/library/docker:24.0.5
docker pull docker:24.0.5-dind
docker tag docker:24.0.5-dind registry.ntnxlab.local/library/docker:24.0.5-dind
docker pull line/kubectl-kustomize:latest
docker tag line/kubectl-kustomize:latest registry.ntnxlab.local/library/kubectl-kustomize:latest

docker pull golang:1.23-alpine
docker tag golang:1.23-alpine registry.ntnxlab.local/library/golang:1.23-alpine
docker pull alpine:latest
docker tag alpine:latest registry.ntnxlab.local/library/alpine:latest

docker login registry.ntnxlab.local -u admin (Pswd: Harbor12345 or customized)

docker push registry.ntnxlab.local/library/golang:1.23-alpine
docker push registry.ntnxlab.local/library/alpine:latest
docker push registry.ntnxlab.local/library/docker:24.0.5 
docker push registry.ntnxlab.local/library/docker:24.0.5-dind 
docker push registry.ntnxlab.local/library/kubectl-kustomize:latest
```

4.  The initial pipeline should fail as `Dockerfile` and `main.go` not present

5.  Base setup: `cd base`

Format manifest files to apply (Change variable values):
```
GITLAB_PAT=<> ./base-setup.sh
```
On Management Cluster:
```
kubectl apply -f project.yaml -f gitops-sources.yaml
```
On Workload Cluster:
```
kubectl apply -f ingress.yaml -f secret.yaml
```

6. Gatekeeper OPA setup on Workload Cluster (Ensure Gatekeeper is enabled):
```
cd ./gatekeeper-files
kubectl apply -f template.yaml
kubectl apply -f contraint.yaml
```

7. User Environment Setup:
- export GITLAB_PAT
- set gitlab SSL

### Base Files
- project.yaml: the project of everything
- gitops-sources.yaml: gitops sources
- ingress.yaml: Traefik ingress 
- secret.yaml: git secret for gitops

### Gatekeeper files
- template.yaml: templating replica limits policy
- constraint.yaml: set replicas limit on project namespace

### Web App Files
Files prepared in [webapp/](./webapp/) directory:
- runner ci files - User to change replica count if OPA implemented

### GitOps Files
Files prepared in [webapp/](./webapp/) directory:
- webapp.yaml
- kustomization.yaml - CI will get the latest image tag and update this!

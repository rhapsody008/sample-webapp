# DevOps Lab Setup

## Prerequisite

Local Gitlab, Harbor, NKP is running

Gitlab credentials set

Gitlab API endpoint: 

## Setup 
1. Prepare Gitlab CI script, NodeJS app files & GitOps manifests

2. Generate 30 Gitlab repos named webapp-user## (from user01 to user30) & put original NodeJS app files + CI script (may have to set secrets, env variables etc.)

3. Generate 30 Gitlab repos named gitops-user## (from user01 to user30) & put original manifests & kustomization files

4. Create GitOps resource pointing to base/ dir (for each workload cluster - manually apply or script apply, project first then ingress, then gitops repo)

5. The apps should be deployed and pipeline should be set.

### Base Files
- project.yaml: the project of everything
- gitops-sources.yaml: gitops sources
- ingress.yaml: Traefik ingress 

### Web App Files
Files prepared in [webapp/](./webapp/) directory:
- runner workflow
- Dockerfile
- package.json
- server.js - USER CHANGES THIS!

### GitOps Files
Files prepared in [webapp/](./webapp/) directory:
- webapp.yaml
- kustomization.yaml - CI will get the latest image tag and update this!



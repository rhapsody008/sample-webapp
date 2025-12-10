# DevOps POC

## User Experience


## Workflow Explained

### Diagram

![workflow.uml](./workflow.uml)

### CI - Docker Image Build
1. A simple NodeJS app with Dockerfile present, with message printed & displayed on web server from [server.js](./server.js)

2. After a change made to the message, users should push to the branch that has the unique username (e.g. branch "user01")

3. Upon push received, GitHub Actions Worklow is triggered to start a runner and build the Docker image from Dockerfile. The runner then push the image to the registry.

4. After image was pushed to registry, the runner will update the [GitOps](https://github.com/rhapsody008/devops-lab-gitops) repo with a newly generated Kustomization file, containing new image tag, on the same branch name.

### CD - Deploy to NKP
1. NKP Management cluster, a project is created with CD configured to track the GitOps repo on respective branches for different users.
2. Upon branch commit received, Flux CD in Management cluster will trigger a new deployment to the NKP workload cluster with the updated image tag

3. After deployment completed (usually up to 3 minutes), the web page is updated with the change.



## Reference

- NKP mgmt cluster CD configuration example: 

![NKP mgmt cluster CD configuration](./.github/image.png)


This powershell script was created to cofigure WSL, Ubuntu, Docker, Minikube, and Helm in order to run a local K8 cluster for testing from beginning to end.
It must be run in admin mode.
This will also copy certs (such as zscaler or company certs) into wsl to allow for access to the internet. For example in the case where docker is unable to pull images due to some proxy issues that it claims. 
A linux user is created with the defaule username: linuxuser and password: password. You can change these if you need to.

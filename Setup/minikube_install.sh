#!/bin/bash
# unix eol needed here as well. use notepad > edit > eol > unix to save properly
cd ~
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 -k 
sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64
#install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
#install helm
wget https://get.helm.sh/helm-v3.16.2-linux-amd64.tar.gz --no-check-certificate
tar -xvf  helm-v3.16.2-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/helm
helm version
helm repo add bitnami https://charts.bitnami.com/bitnami

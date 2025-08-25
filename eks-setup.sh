#!/bin/bash

# Step 1: Set up AWS and Kubernetes Tools


# Install required packages
sudo apt-get update && sudo apt-get install -y apt-transport-https wget curl jq


# Install kubectl (Kubernetes CLI)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl

# Install helm (Package manager for Kubernetes)
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

# Install eksctl (CLI for managing EKS clusters)
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
sudo chmod +x /usr/local/bin/eksctl

# Install awscli (CLI for AWS)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo apt install unzip -y
sudo unzip awscliv2.zip
sudo ./aws/install


# Create an EKS cluster
eksctl create cluster --name devops-cluster --region us-east-1 --nodegroup-name bankapp-node-group --node-type t2.medium --nodes 2 --nodes-min 2 --nodes-max 3 --spot --managed

#delete cluster
eksctl delete cluster --name devops-cluster --region us-east-1 


# Step 2: Connect to AWS EKS Cluster
aws configure 

# Update kubeconfig for the EKS Cluster
aws eks --region us-east-1 update-kubeconfig --name devops-cluster

# Associate OIDC provider with EKS (for IAM roles for service accounts)
eksctl utils associate-iam-oidc-provider --region us-east-1 --cluster devops-cluster --approve


# Step 3: Install and Set Up Helm Repositories

# Add Helm Repositories for Argo, Prometheus, and Grafana
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo update


# Step 4: Install Cert-Manager for Kubernetes

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.18.2cert-manager.yaml

#install ingress controller with kubectl
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml



# Install Cert-Manager with Helm
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.18.2 \
  --set crds.enabled=true

# Install NGINX Ingress Controller via Helm
helm install ingress-nginx ingress-nginx/ingress-nginx  --namespace ingress-nginx --create-namespace



# Create Kubernetes secret for Cloudflare API Token
CLOUDFLARE_API_TOKEN="your_cloudflare_api_token_here"  # Replace with your actual Cloudflare API token
kubectl create secret generic cloudflare-api-token --from-literal=apiToken=$CLOUDFLARE_API_TOKEN -n cert-manager

# Apply the ClusterIssuer and certificate
kubectl apply -f ./cert-manager.yaml

# Confirm the certificate is issued
kubectl get clusterissuer letsencrypt-prod
kubectl get certificate prod-certificate -n prod
kubectl describe certificate prod-certificate -n prod 

kubectl get ingress -n prod
kubectl get certificate -n prod
kubectl delete certificate prod-certificate -n prod


# Step 6: Set Up EBS CSI Driver

# Create IAM Service Account for EBS CSI Driver
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster devops-cluster \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --role-only \
  --role-name AmazonEBS_CSI_DriverRole \
  --region us-east-1 \
  --approve

# Install EBS CSI Driver using eksctl (Addon)
eksctl create addon \
  --cluster devops-cluster \
  --name aws-ebs-csi-driver \
  --service-account-role-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/AmazonEBS_CSI_DriverRole \
  --region us-east-1 \
  --force

#optional 

#iam service account for ebs csi driver
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster devops-cluster \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve \
  --override-existing-serviceaccounts


kubectl apply -k \
  "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/ecr/?ref=release-1.47"




# Install Argo CD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Expose Argo CD to the public
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# Retrieve Argo CD credentials
echo "ArgoCD URL: http://$(kubectl get svc -n argocd argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
echo "ArgoCD Password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
echo "ArgoCD Username: admin"



# Confirm the setup of storage, PVC, and PV
kubectl get sc
kubectl get pvc -n prod
kubectl get pv


# Confirm the ingress and service status
kubectl get ingress -n prod


# Resolve DNS
nslookup www.worths.cloud
kubectl get ingress -n prod
kubectl get svc -n prod
kubectl get svc -n ingress-nginx



##MONITORING
# Install Prometheus with Helm
helm install prometheus prometheus-community/kube-prometheus-stack -f values.yaml -n monitoring --create-namespace 

#Retrieve Prometheus URL
kubectl patch svc prometheus-kube-prometheus-prometheus -p '{"spec":{"type":"LoadBalancer"}}' -n monitoring
prometheus-url=$(kubectl get svc prometheus-kube-prometheus-prometheus -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Prometheus URL: http://$prometheus-url:9090"

#Retrieve Grafana password and URL
kubectl patch svc prometheus-grafana -p '{"spec":{"type":"LoadBalancer"}}' -n monitoring
grafana-url=$(kubectl get svc prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Grafana URL: http://$grafana-url"


#patch node exporters & kube-state-metrics services to use LoadBalancer
kubectl patch svc prometheus-node-exporter -p '{"spec":{"type":"ClusterIP"}}' -n monitoring
kubectl patch svc prometheus-kube-state-metrics -p '{"spec":{"type":"ClusterIP"}}' -n monitoring
kubectl patch svc prometheus-blackbox-exporter -p '{"spec":{"type":"ClusterIP"}}' -n monitoring
kubectl patch svc prometheus-alertmanager -p '{"spec":{"type":"LoadBalancer"}}' -n monitoring

#Retrieve node exporter & kube-state-metrics URL
node-exporter-url=$(kubectl get svc prometheus-node-exporter -n monitoring -o jsonpath='{.status.ClusterIP.ingress[0].hostname}')
kube-state-metrics-url=$(kubectl get svc prometheus-kube-state-metrics -n monitoring -o jsonpath='{.status.ClusterIP.ingress[0].hostname}')
blackbox-exporter-url=$(kubectl get svc prometheus-blackbox-exporter -n monitoring -o jsonpath='{.status.ClusterIP.ingress[0].hostname}')
alertmanager-url=$(kubectl get svc prometheus-alertmanager -n monitoring -o jsonpath='{.status.LoadBalancer.ingress[0].hostname}')
echo "Node exporter URL: http://$node-exporter-url:9100"
echo "Kube-state-metrics URL: http://$kube-state-metrics-url:8080"
echo "Blackbox exporter URL: http://$blackbox-exporter-url:9115"
echo "Alertmanager URL: http://$alertmanager-url:9093"


#expose alertmanager to the public
kubectl patch svc prometheus-kube-prometheus-stack-alertmanager -p '{"spec":{"type":"LoadBalancer"}}' -n monitoring
alertmanager-url=$(kubectl get svc prometheus-kube-prometheus-stack-alertmanager -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Alertmanager URL: http://$alertmanager-url:9093"








# Step 10: Create GitHub Image Pull Secret (Optional)

# Create GitHub Container Registry Pull Secret
kubectl create secret docker-registry github-container-registry \
  --docker-server=ghcr.io \
  --docker-username=ghcr.io/your-github-username \
  --docker-password=ghcr.io/paste-your-token \
  --docker-email=example@example.com




#!/bin/bash

#install vault with helm
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update


#create vault namespace
kubectl create namespace vault 
kubectl create namespace prod

#create vault service account
kubectl create serviceaccount vault-auth -n prod

#create kubernetes secret for aws credentials
kubectl create secret generic aws-creds \
  --from-literal=AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  --from-literal=AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
  --from-literal=AWS_KMS_KEY_ID=$AWS_KMS_KEY_ID 
  --namespace vault


#apply vault values file
helm install vault hashicorp/vault -n vault -f vault.yaml 

helm upgrade --install vault hashicorp/vault -n vault -f vault.yaml 



#get service ip for dns resolution
kubectl get svc -n ingress-nginx



#check vault logs
kubectl logs vault-0 -n vault


#check vault status
kubectl exec -it vault-0 -n vault -- vault status

#initialize vault
kubectl exec -it vault-0 -n vault -- vault operator init 


#unseal vault
kubectl exec -it vault-0 -n vault -- vault operator unseal  <unseal_key-1>
kubectl exec -it vault-0 -n vault -- vault operator unseal  <unseal_key-2>
kubectl exec -it vault-0 -n vault -- vault operator unseal   <unseal_key-3>


#vault login
kubectl exec -it vault-0 -n vault -- vault login <root_token>


#export vault address and ca cert
export VAULT_ADDR=https://vault.worths.cloud:8200
export VAULT_CACERT=./rootCA.crt

#join pods to raft cluster
kubectl exec -it vault-1 -n vault -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -it vault-2 -n vault -- vault operator raft join http://vault-0.vault-internal:8200

#or use internal DNS
kubectl exec -it vault-1 -n vault -- vault operator raft join https://vault-0.vault-internal:8200
kubectl exec -it vault-2 -n vault -- vault operator raft join https://vault-0.vault-internal:8200


#list pods in cluster
kubectl exec -it vault-0 -n vault -- vault operator raft list-peers


#unseal all vault pods
kubectl exec -it vault-1 -n vault -- vault operator unseal <unseal_key-1>
kubectl exec -it vault-2 -n vault -- vault operator unseal <unseal_key-1>
kubectl exec -it vault-1 -n vault -- vault operator unseal <unseal_key-2>
kubectl exec -it vault-2 -n vault -- vault operator unseal <unseal_key-2>
kubectl exec -it vault-1 -n vault -- vault operator unseal <unseal_key-3>
kubectl exec -it vault-2 -n vault -- vault operator unseal <unseal_key-3>


#check vault status
kubectl exec -it vault-0 -n vault -- vault status
kubectl exec -it vault-1 -n vault -- vault status
kubectl exec -it vault-2 -n vault -- vault status

#check vault logs
kubectl logs -f vault-0 -n vault
kubectl logs -f vault-1 -n vault
kubectl logs -f vault-2 -n vault


#check vault pods
kubectl get pods -n vault



#enable kubernetes auth
kubectl exec -it -n vault vault-0 -- vault auth enable kubernetes

#configure kubernetes auth for prod namespace
kubectl exec -it vault-0 -n vault -- vault write auth/kubernetes/config \
  token_reviewer_jwt="$(kubectl get secret -n prod $(kubectl get sa vault-auth -n prod -o jsonpath="{.secrets[0].name}") -o jsonpath="{.data.token}" | base64 --decode)" \
  kubernetes_host="$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}')" \
  kubernetes_ca_cert="$(kubectl get secret -n prod $(kubectl get sa vault-auth -n prod -o jsonpath="{.secrets[0].name}") -o jsonpath="{.data['ca.crt']}" | base64 --decode)"

#alternative way to configure kubernetes auth for prod namespace
NAMESPACE=prod
SERVICE_ACCOUNT=vault-auth

TOKEN_REVIEW_JWT=$(kubectl get secret -n $NAMESPACE $(kubectl get sa $SERVICE_ACCOUNT -n $NAMESPACE -o jsonpath="{.secrets[0].name}") -o jsonpath="{.data.token}" | base64 --decode)

KUBE_CA_CERT=$(kubectl get secret -n $NAMESPACE $(kubectl get sa $SERVICE_ACCOUNT -n $NAMESPACE -o jsonpath="{.secrets[0].name}") -o jsonpath="{.data['ca.crt']}" | base64 --decode)

KUBE_HOST=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}')

kubectl exec -it vault-0 -n vault -- vault write auth/kubernetes/config \
  token_reviewer_jwt="$TOKEN_REVIEW_JWT" \
  kubernetes_host="$KUBE_HOST" \
  kubernetes_ca_cert="$KUBE_CA_CERT"



#create vault policy file
cat <<EOF > /tmp/policy.hcl
path "secret/data/mysql" {  
  capabilities = ["read"]
}

path "secret/data/backend" {
  capabilities = ["read"]
}

# Access to list secrets under the path (metadata)
path "secret/metadata/mysql" {
  capabilities = ["list"]
}

path "secret/metadata/backend" {
  capabilities = ["list"]
}
EOF


#copy policy file to vault pod
kubectl cp /tmp/policy.hcl vault-0:/tmp/policy.hcl -n vault

#or use
kubectl cp /tmp/policy.hcl vault/vault-0:/tmp/policy.hcl 

#write policy file
kubectl exec -it -n vault vault-0 -- vault policy write my-policy /tmp/policy.hcl


#configure kubernetes auth role
kubectl exec -it -n vault vault-0 -- vault write auth/kubernetes/role/vault-role \
    bound_service_account_names=vault-auth \
    bound_service_account_namespaces=prod \
    policies=my-policy \
    ttl=24h \
    audience=vault

    

#verify kubernetes auth role
kubectl exec -it -n vault vault-0 -- vault read auth/kubernetes/role/vault-role


#enable secret engine
kubectl exec -it vault-0 -n vault -- vault secrets enable -path=secret kv-v2

#add secrets to vault
kubectl exec -it vault-0 -n vault -- vault kv put secret/mysql \
  MYSQL_ROOT_PASSWORD="StrongPassword123!" \
  MYSQL_USER="root" \
  MYSQL_PASSWORD="StrongestPassword456!" \

  
kubectl exec -it vault-0 -n vault -- vault kv put secret/backend \
  JWT_SECRET="SuperSecretKey123!"
  


#access secrets from vault
kubectl exec -it vault-0 -n vault -- vault kv get secret/mysql
kubectl exec -it vault-0 -n vault -- vault kv get secret/backend

----------------------------------------------------------------------

##troubleshooting

#incase you missed your unseal keys, you can re-initialize vault
kubectl delete pvc -n vault -l app.kubernetes.io/name=vault

kubectl delete statefulset vault -n vault

kubectl exec -it vault-0 -n vault -- vault operator init



#check vault logs
kubectl logs vault-0 -n vault

#check vault configmap

kubectl edit configmap vault-config -n vault


kubectl delete configmap vault-config -n vault

kubectl describe pod vault-0 -n vault

#delete vault pods
kubectl delete pvc -l app.kubernetes.io/name=vault -n vault

------------------------------------------------------------------------




openssl genrsa -out rootCA.key 4096 


# Create self-signed Root CA certificate
MSYS_NO_PATHCONV=1 openssl req -x509 -new -key rootCA.key -sha256 -days 365 \
  -subj "/C=US/ST=State/L=City/O=YourOrg/OU=IT/CN=Vault Root CA" \
  -out rootCA.crt


cat <<EOF > vault-0.cnf
[req]
default_bits       = 2048
prompt             = no
default_md         = sha256
req_extensions     = v3_req
distinguished_name = dn

[dn]
C=US
ST=State
L=City
O=YourOrg
OU=IT
CN=vault.worths.cloud

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = vault-0.vault-internal
DNS.2 = vault-1.vault-internal
DNS.3 = vault-2.vault-internal
DNS.4 = vault
DNS.5 = vault.vault
DNS.6 = vault.vault.svc
DNS.7 = vault.vault.svc.cluster.local
DNS.8 = vault.worths.cloud
IP.1 = 127.0.0.1
EOF


openssl genrsa -out vault.key 2048

openssl req -new -key vault.key -out vault.csr -config vault-0.cnf

openssl x509 -req -in vault.csr -CA rootCA.crt -CAkey rootCA.key \
  -CAcreateserial -out vault.crt -days 365 \
  -extfile vault-0.cnf -extensions v3_req


kubectl create secret generic vault-tls-ha \
  --from-file=tls.crt=vault.crt \
  --from-file=tls.key=vault.key \
  --from-file=ca.crt=rootCA.crt \
  --namespace vault

#verify certificate
openssl x509 -in vault.crt -text -noout

#get secret
kubectl get secret vault-tls-ha -n vault 

kubectl describe secret vault-tls-ha -n vault


#patch mutating webhook configuration to use the new CA bundle
kubectl patch mutatingwebhookconfiguration vault-agent-injector-cfg \
  --type='json' \
  -p='[{"op": "replace", "path": "/webhooks/0/clientConfig/caBundle", "value": "'$(base64 -w0 rootCA.crt)'"}]'


#patch vault-agent-injector deployment 
kubectl -n vault patch deployment vault-agent-injector \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"sidecar-injector","env":[{"name":"AGENT_INJECT_VAULT_ADDR","value":"https://vault.worths.cloud"},{"name":"AGENT_INJECT_VAULT_AUTH_PATH","value":"auth/kubernetes"}]}]}}}}'

#restart vault-agent-injector deployment
kubectl rollout restart deployment vault-agent-injector -n vault

#verify webhook configuration
kubectl get mutatingwebhookconfiguration vault-agent-injector-cfg -o yaml | grep caBundle

# create configmap with CA certificate
kubectl create configmap vault-ca-cert \
  --from-file=ca.crt=./rootCA.crt \
  -n prod



# kubectl delete secret vault-tls-ha -n vault
kubectl delete secret vault-tls-ha -n vault



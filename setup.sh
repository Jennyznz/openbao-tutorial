#!/usr/bin/env bash

# run file with bash and stop script is any commands fail
set -euo pipefail

# clone OpenBao
git clone https://github.com/openbao/openbao.git

# build OpenBao
cd openbao
make dev    # compiles code and puts bao binary into openbao/bin/
cd ..
BAO=./openbao/bin/bao   # save path for later ease

# start a dev-mode server
$BAO server -dev -dev-root-token-id=root &  # runs server in background
SERVER_PID=$! # save server's process ID
sleep 3
export BAO_ADDR=http://127.0.0.1:8200
export BAO_TOKEN=root

# enable userpass
$BAO auth enable userpass
# create a user
$BAO write auth/userpass/users/jenny password=randompw

# enable PKI and generate root CA
$BAO secrets enable pki
$BAO secrets tune -max-lease-ttl=87600h pki # raise max lifetime for longevity
# private key stays with OpenBao
$BAO write -field=certificate pki/root/generate/internal \common_name="example.com" ttl=87600h > root_ca.crt

# create pki config urls
$BAO write pki/config/urls \
    issuing_certificates="$BAO_ADDR/v1/pki/ca" \
    crl_distribution_points="$BAO_ADDR/v1/pki/crl"

# create a pki role (set of rules for which certificates can be issued) for a domain
$BAO write pki/roles/example-dot-com \
    allowed_domains="example.com" \
    allow_subdomains=true \
    max_ttl=72h

# create a policy (which controls what a token can do) for role and assign to a user
cat > pki-policy.hcl <<EOF
path "pki/issue/example-dot-com" {
    capabilities = ["create", "update"]
}
EOF

# create policy that allows holder to issue certificates using only that role
$BAO policy write pki-issuer pki-policy.hcl
# attach policy to current user
$BAO write auth/userpass/users/jenny password=randompw policies=pki-issuer

# issue certificate as the user
USER_TOKEN=$($BAO login -method=userpass -no-store -field=token \
    username=jenny password=randompw)   # login

# request a certificate
BAO_TOKEN=$USER_TOKEN $BAO write pki/issue/example-dot-com \
    common_name="test.example.com" ttl=24h

# kill server process ID to stop background server
kill %1
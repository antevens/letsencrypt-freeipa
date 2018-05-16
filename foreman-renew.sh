#!/bin/bash
kinit "${SUDO_USER:-}" # kinit as sudo user or if variable is not set current user

# Set variables
start_timestamp=$(date +"%Y%m%d%H%M")
host="${HOSTNAME}"
le_dir="/etc/letsencrypt/live/${host}"
kct_dir="/etc/pki/katello-certs-tools"
k_dir="/etc/pki/katello"

# Get new certificate
certbot certonly --manual \
                 --preferred-challenges dns \
                 --manual-public-ip-logging-ok \
                 --manual-auth-hook 'ipa dnsrecord-mod ${CERTBOT_DOMAIN#*.}. _acme-challenge.${CERTBOT_DOMAIN}. --txt-rec=${CERTBOT_VALIDATION}' \
                 -d "${host}" \
                 --agree-tos \
                 --email "support@sdelements.com" \
                 --expand \
                 -n

# Rotate Certs and Keys in place
mv "${kct_dir}/certs/${host}-apache.crt" "${kct_dir}/certs/${host}-apache.crt.${start_timestamp}"
mv "${kct_dir}/certs/${host}-foreman-proxy.crt" "${kct_dir}/certs/${host}-foreman-proxy.crt.${start_timestamp}"
cp "${le_dir}/cert.pem" "${kct_dir}/certs/${host}-apache.crt"
cp "${le_dir}/cert.pem" "${kct_dir}/certs/${host}-foreman-proxy.crt"
chcon system_u:object_r:cert_t:s0 "${kct_dir}/certs/${host}-apache.crt"
chcon system_u:object_r:cert_t:s0 "${kct_dir}/certs/${host}-foreman-proxy.crt"

mv "${kct_dir}/private/${host}-foreman-proxy.key" "${kct_dir}/private/${host}-foreman-proxy.key.${start_timestamp}"
mv "${kct_dir}/private/${host}-apache.key" "${kct_dir}/private/${host}-apache.key.${start_timestamp}"
cp "${le_dir}/privkey.pem" "${kct_dir}/private/${host}-foreman-proxy.key"
cp "${le_dir}/privkey.pem" "${kct_dir}/private/${host}-apache.key"
chmod 600 "${kct_dir}/${host}-foreman-proxy.key" "{$kct_dir}/${host}-apache.key"
chcon system_u:object_r:cert_t:s0 "${kct_dir}/${host}-foreman-proxy.key" "{$kct_dir}/${host}-apache.key"

mv "${k_dir}/certs/katello-apache.crt" "${k_dir}/certs/katello-apache.crt.${start_timestamp}"
cp "${le_dir}/cert.pem" "${k_dir}/certs/katello-apache.crt"
chcon system_u:object_r:cert_t:s0 "${k_dir}/certs/katello-apache.crt"

mv "${k_dir}/private/katello-apache.key" "${k_dir}/private/katello-apache.key.${start_timestamp}"
cp "${le_dir}/privkey.pem" "${k_dir}/private/katello-apache.key"
chcon system_u:object_r:cert_t:s0 "${k_dir}/private/katello-apache.key"
chmod 660 "${k_dir}/private/katello-apache.key"

# Restart Services
systemctl restart httpd.service
systemctl status httpd.service

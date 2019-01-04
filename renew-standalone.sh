#!/bin/bash

# Copyright (c) 2017 Antonia Stevens a@antevens.com

#  Permission is hereby granted, free of charge, to any person obtaining a
#  copy of this software and associated documentation files (the "Software"),
#  to deal in the Software without restriction, including without limitation
#  the rights to use, copy, modify, merge, publish, distribute, sublicense,
#  and/or sell copies of the Software, and to permit persons to whom the
#  Software is furnished to do so, subject to the following conditions:
#
#  The above copyright notice and this permission notice shall be included in
#  all copies or substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
#  OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
#  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
#  DEALINGS IN THE SOFTWARE.

# Set strict mode
set -euo pipefail

# Version
# shellcheck disable=2034
version='0.0.3'

# Exit if not being run as root
if [ "${EUID:-$(id -u)}" -ne "0" ] ; then
    echo "This script needs superuser privileges, suggest running it as root"
    exit 1
fi

# Start Unix time
start_time_epoch="$(date +%s)"

# If there is no TTY then it's not interactive
if ! [[ -t 1 ]]; then
    interactive=false
fi
# Default is interactive mode unless already set
interactive="${interactive:-true}"


# Safely loads config file
# First parameter is filename, all consequent parameters are assumed to be
# valid configuration parameters
function load_config()
{
    config_file="${1}"
    # Verify config file permissions are correct and warn if they are not
    # Dual stat commands to work with both linux and bsd
    shift
    while read -r line; do
        if [[ "${line}" =~ ^[^#]*= ]]; then
            setting_name="$(echo "${line}" | awk --field-separator='=' '{print $1}' | sed --expression 's/^[[:space:]]*//' --expression 's/[[:space:]]*$//')"
            setting_value="$(echo "${line}" | cut --fields=1 --delimiter='=' --complement | sed --expression 's/^[[:space:]]*//' --expression 's/[[:space:]]*$//')"

            if echo "${@}" | grep -q "${setting_name}" ; then
                export "${setting_name}"="${setting_value}"
                echo "Loaded config parameter ${setting_name} with value of '${setting_value}'"
            fi
        fi
    done < "${config_file}";
}

# This script will automatically fetch/renew your LetsEncrypt certificate for all
# defined principals. Before running this script you should run the acompanying
# register script. This script should be scheduled to run from crontab or similar
# as a superuser (root).
# The email address will always default to the hostmaster in the SOA record
# for the first/shortest principal in IPA, this can be overwritten using the
# email environment variable, for example:
# email="admin@example.com" ./renew.sh
load_config '/etc/krb5.conf' default_realm
host="$(hostname)"
# Get kerberos ticket to modify DNS entries
kinit -k -t /etc/lets-encrypt.keytab "lets-encrypt/${host}"
# shellcheck disable=2154
principals="$(ipa host-show "${host}" --raw | grep krbprincipalname | grep 'host/' | sed 's.krbprincipalname: host/..' | sed s/"@${default_realm}"//)"
dns_domain_name="${host#[a-zA-Z0-9,\-\_]*\.}"
soa_record="$(dig SOA "${dns_domain_name}" + short | grep ^"${dns_domain_name}". | grep 'SOA' | awk '{print $6}')"
hostmaster="${soa_record/\./@}"
email="${email:-${hostmaster%\.}}"
letsencrypt_live_dir="/etc/letsencrypt/live"
letsencrypt_pem_dir="$(find -L ${letsencrypt_live_dir} -newermt "@${start_time_epoch}" -type f -name 'privkey.pem' -exec dirname {} \;)"

# Configure the manual auth hook
# shellcheck disable=2016
default_auth_hook='ipa dnsrecord-mod ${CERTBOT_DOMAIN#*.}. _acme-challenge.${CERTBOT_DOMAIN}. --txt-rec=${CERTBOT_VALIDATION}'

# Configure alternative nsupdate hook
nsupdate_auth_server="${NSUPDATE_AUTH_SERVER:-$(nslookup -type=soa "${dns_domain_name}"  | grep 'origin =' | sed -e 's/[[:space:]]*origin = //')}"
#shellcheck disable=2016
nsupdate_commands=(
    "server ${nsupdate_auth_server}"
    'update delete _acme-challenge.${CERTBOT_DOMAIN} TXT'
    'update add _acme-challenge.${CERTBOT_DOMAIN} 320 IN TXT "${CERTBOT_VALIDATION}'
    'send'
)
nsupdate_key_name="${NSUPDATE_KEY_NAME:-}"
nsupdate_key_secret="${NSUPDATE_KEY_SECRET:-}"
nsupdate_key_file="${NSUPDATE_KEY_FILE:-}"
nsupdate_auth_hook='printf "%s\n" '"${nsupdate_commands[*]} | nsupdate -v"
# Prefer key file but also accept key_name/secret combo
if [ -n "${nsupdate_key_file}" ] ; then
    if [ -e "${nsupdate_key_file}" ] ; then
        default_auth_hook="${nsupdate_auth_hook} -k ${nsupdate_key_file}"
    else
        echo "Specified nsupdate key file ${nsupdate_key_file} does not exist, exiting!"
        exit 1
    fi
elif [ -n "${nsupdate_key_name}" ] && [ -n "${nsupdate_key_secret}" ] ; then
    default_auth_hook="${nsupdate_auth_hook} -y ${nsupdate_key_name}:${nsupdate_key_secret}"
fi

# Set the auth hook
auth_hook="${AUTH_HOOK:-${default_auth_hook}}"

domains=($(echo ${principals} | tr " " "\n"))
for domain in "${domains[@]}" ; do
    domain_args+=("-d ${domain}")
done

# Apply for a new cert using CertBot with DNS verification
certbot certonly --manual \
                 --preferred-challenges dns \
                 --manual-public-ip-logging-ok \
                 --manual-auth-hook "${auth_hook}" \
                 "${domain_args[@]}" \
                 --agree-tos \
                 --email "${email}" \
                 --expand \
                 -n

# If the certificate has been updated since start of this script
if [ -n "${letsencrypt_pem_dir}" ] ; then
    echo 'Certificate has been updated, you will now have to restart your web server.'
fi

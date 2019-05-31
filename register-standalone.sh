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

message="
This script will modify your FreeIPA setup so that this server can automatically
apply for LetsEncrypt SSL/TLS certificates for all hostnames/principals associted.

This script needs the host to be already registered in FreeIPA, the IPA client
is installed and that the user running this script is in the IPA admins group.

The following steps will be taken:

1. Installing CertBot (Let's Encrypt client)
2. Create a DNS Administrator role in FreeIPA, members of which can edit DNS Records
3. Create a new service, allow it to manage DNS entries
4. Allow members of the admin group to create and retrieve keytabs for the service
5. Create bogus TXT initialization records for the host.
"

if ${interactive} ; then
    while ! [[ "${REPLY:-}" =~ ^[NnYy]$ ]]; do
	echo "${message}"
	read -rp "Please confirm you want to continue and modify your system/setup (y/n):" -n 1
	echo

	# Get a fresh kerberos ticket if needed
        klist || ( [ "${EUID:-$(id -u)}" -eq 0 ] && kinit "${SUDO_USER:-${USER}}" ) || kinit
    done
else
    REPLY="y"
fi

if [[ ${REPLY} =~ ^[Yy]$ ]]; then
    if [ ! $(command -v certbot) ]; then
        echo 'Installing certbot.'
        sudo yum -y install certbot || (sudo apt-get update && sudo apt-get -y install certbot)
    fi

    if [ ! $(command -v ipa) ]; then
        echo 'Installing freeipa utilities.'
        sudo yum -y install ipa-client || (sudo apt-get update && sudo apt-get -y install freeipa-admintools)
    fi

    load_config '/etc/krb5.conf' default_realm
    host="$(hostname)"
    group='admins'
    # shellcheck disable=2154
    principals="$(ipa host-show "${host}" --raw | grep krbprincipalname | grep 'host/' | sed 's.krbprincipalname: host/..' | sed s/"@${default_realm}"//)"

    ipa service-add "lets-encrypt/${host}@${default_realm}"
    ipa role-add "DNS Administrator"
    ipa role-add-privilege "DNS Administrator" --privileges="DNS Administrators"
    ipa role-add-member "DNS Administrator" --services="lets-encrypt/${host}@${default_realm}"
    ipa service-allow-create-keytab "lets-encrypt/${host}@${default_realm}" --groups=${group}
    ipa service-allow-retrieve-keytab "lets-encrypt/${host}@${default_realm}" --groups=${group}
    ipa-getkeytab -p "lets-encrypt/${host}" -k /etc/lets-encrypt.keytab #add -r to renew

    echo 'FreeIPA service and keytab initialization complete, proceeding with DNS initialization.'
    for principal in ${principals} ; do
        echo "Adding placeholder ACME challenge TXT for ${principal}"
        ipa dnsrecord-add "${principal#[a-zA-Z0-9,\-\_]*\.}." "_acme-challenge.${principal}." --txt-rec='INITIALIZED'
    done

    echo 'DNS initialization complete, running letsencrypt process to obtain fresh certificates.'
    # Apply for the initial certificate if script is available
    renew_script_path="$(dirname "${0}")/renew-standalone.sh"
    if [ -f "${renew_script_path}" ] ; then
        sudo bash -c "${renew_script_path}"
    fi
else
    echo "Let's Encrypt registration cancelled by user"
    exit 1
fi

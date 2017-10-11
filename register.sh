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
version='0.0.1'

# If there is no TTY then it's not interactive
if ! [[ -t 1 ]]; then
    interactive=false
fi
# Default is interactive mode unless already set
interactive="${interactive:-true}"

message="
This script will modify your FreeIPA setup so that this server can automatically
apply for LetsEncrypt SSL/TLS certificates for all hostnames/principals associted.

This script needs the host to be already registered in FreeIPA, the IPA client
is installed and that the user running this script is in the IPA admins group.

The following steps will be taken:

1. Adding the Let's Encrypt Root and Intermediate CAs as trusted CAs in your cert store.
2. Installing CertBot (Let's Encrypt client)
3. Create a DNS Administrator role in FreeIPA, members of which can edit DNS Records
4. Create a new service, allow it to manage DNS entries
5. Allow members of the admin group to create and retrieve keytabs for the service
6. Create bogus TXT initialization records for the host.
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
    host="$(hostname)"
    realm="$(grep default_realm /etc/krb5.conf | awk -F= '{print $NF}' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    group='admins'
    principals="$(ipa host-show ${host} --raw | grep krbprincipalname | grep 'host/' | sed 's.krbprincipalname: host/..' | sed s/@${realm}//)"

    wget https://letsencrypt.org/certs/isrgrootx1.pem | sudo ipa-cacert-manage install isrgrootx1.pem -n ISRGRootCAX1 -t C,,
    wget https://letsencrypt.org/certs/letsencryptauthorityx3.pem | sudo ipa-cacert-manage install letsencryptauthorityx3.pem -n ISRGRootCAX3 -t C,,
    if [ "${EUID}" -ne 0 ] && ${interactive} ; then
        sudo bash -c "export KRB5CCNAME='${KRB5CCNAME:-}' && ipa-certupdate -v"
    else
        ipa-certupdate
    fi

    sudo yum -y install certbot || sudo apt-get -y install certbot
    ipa service-add "lets-encrypt/${host}@${realm}"
    ipa role-add "DNS Administrator"
    ipa role-add-privilege "DNS Administrator" --privileges="DNS Administrators"
    ipa role-add-member "DNS Administrator" --services="lets-encrypt/${host}@${realm}"
    ipa service-allow-create-keytab "lets-encrypt/${host}@${realm}" --groups=${group}
    ipa service-allow-retrieve-keytab "lets-encrypt/${host}@${realm}" --groups=${group}
    ipa-getkeytab -p "lets-encrypt/${host}" -k /etc/lets-encrypt.keytab #add -r to renew

    for principal in ${principals} ; do
        zone="$(echo "${principal}" | sed -e 's/^[a-zA-Z0-9\-\_]*\.//')"
        ipa dnsrecord-add "${zone}." "_acme-challenge.${principal}." --txt-rec='INITIALIZED'
    done

    # Apply for the initial certificate if script is available
    if [ -f "$(dirname ${0})/renew.sh" ] ; then
        sudo bash -c "$(dirname ${0})/renew.sh"
    fi
else
    echo "Let's Encrypt registration cancelled by user"
    exit 1
fi

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

# If there is no TTY then it's not interactive
if ! [[ -t 1 ]]; then
    interactive=false
fi
# Default is interactive mode unless already set
interactive="${interactive:-true}"

if ${interactive} ; then
    while ! [[ "${REPLY:-}" =~ ^[NnYy]$ ]]; do
	read -rp "Please confirm you want to download and install letsencrypt FreeIPA scripts (y/n):" -n 1
	echo
    done
else
    REPLY="y"
fi

if [[ ${REPLY} =~ ^[Yy]$ ]]; then
    destination='/usr/sbin/renew_letsencrypt_cert.sh'
    cronfile="/etc/cron.d/$(basename ${destination})"
    export interactive
    old_umask="$(umask)"
    umask 0002
    wget https://raw.githubusercontent.com/antevens/letsencrypt-freeipa/master/register.sh -O - | bash
    wget https://raw.githubusercontent.com/antevens/letsencrypt-freeipa/master/renew.sh -O "${destination}"
    chown root:root "${destination}"
    chmod 0700 "${destination}"
    umask "${old_umask}"
    bash "${destination}"

    echo  "Your system has been configured for using LetsEncrypt, adding a cronjob for renewals"

    minute="${RANDOM}"
    hour="${RANDOM}"
    day="${RANDOM}"

    (( minute %= 60 ))
    (( hour %= 6 ))
    (( day %= 28 ))
    cronjob="${minute} ${hour} ${day} * * root ${destination}"

    echo "Adding Cronjob: ${cronjob} to ${cronfile}"
    echo "${cronjob}" > "${cronfile}"

else
    echo "Let's Encrypt FreeIPA installation cancelled by user"
    exit 1
fi

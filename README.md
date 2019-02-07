# letsencrypt-freeipa
Scripts to automate installation, configuration and renewal of LetsEncrypt certificates on FreeIPA Servers.

Note that these scripts assume that FreeIPA is managing the DNS servers required to authorize the issuing of certificates for the domains in question.

The register script will modify your FreeIPA setup so that the server you run
it on can apply for LetsEncrypt SSL/TLS certificates for all hostnames/principals
associted with it in FreeIPA.

This script was tested with IPA v. 4.4 but should work with 4.2 and newer due
to depending on the ipa-server-certinstall command.

This script needs the host to be registered in FreeIPA and the IPA client
installed and that the user running the script is in the IPA admins group.

The following steps are taken during registration:

1. Adding the Let's Encrypt Root and Intermediate CAs as trusted CAs in your cert store.
2. Installing CertBot (Let's Encrypt client)
3. Create a DNS Administrator role in FreeIPA, members of which can edit DNS Records
4. Create a new service, allow it to manage DNS entries
5. Allow members of the admin group to create and retrieve keytabs for the service
6. Create bogus TXT initialization records for the host.
7. Run renewal code to fetch first certificate

The following steps are takeng during renewal:

1. Kerberos ticket for lets-encrypt service loaded from keytab located in /etc
2. Certbot is run, this generates a random validation string for each
   host/principal. For every principal we create a TXT DNS record in IPA which
   is then validated by LetsEncrypt servers
3. Certificate is installed for both web and ldap servers


To install, register and apply for a cert run the following command on the IPA
server as a root user with a valid admin kerberos ticket:

wget https://raw.githubusercontent.com/antevens/letsencrypt-freeipa/master/install.sh -O - | bash


Note that when upgrading from Centos/RHEL 7.3 to 7.4 you might encounter the
following error/bug:
https://pagure.io/freeipa/issue/7141
https://bugzilla.redhat.com/show_bug.cgi?id=1484428

DEBUG stderr=certutil: Could not find cert: Server-Cert
: PR_FILE_NOT_FOUND_ERROR: File not found


The following steps should mitigate the issue and allow the upgrade to proceed
yum update -y # Will throw an error
yum -y install patch
cd /usr/lib/python2.7/site-packages/ipaserver
wget https://pagure.io/freeipa/raw/52853875e298e38a1e5a9a56c02aac9e30916044 -O ipa45_cert_upgrade_error.patch
patch -p 2 < ipa45_cert_upgrade_error.patch

mv /usr/lib/python2.7/site-packages/ipalib/install/certstore.py /usr/lib/python2.7/site-packages/ipalib/install/certstore.py.old
wget https://pagure.io/freeipa/raw/master/f/ipalib/install/certstore.py -O /usr/lib/python2.7/site-packages/ipalib/install/certstore.py

ipa-server-upgrade

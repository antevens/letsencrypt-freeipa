# letsencrypt-freeipa
Scripts to automate installation, configuration and renewal of LetsEncrypt certificates on FreeIPA Servers.

The register script will modify your FreeIPA setup so that the server you run
it on can apply for LetsEncrypt SSL/TLS certificates for all hostnames/principals
associted with it in FreeIPA.

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

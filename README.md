# local-CA
Set up to create a local certificate authority in a VM. Currently focused on XCP-ng environment. The goal is to provide a local certificate authority that uses ACME to generate certificates for different applications within a network. It will use short-lived 24/48-hour certificates, as revocation is not part of Smallstep. 

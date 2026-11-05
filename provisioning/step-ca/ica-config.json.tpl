{
  "root": "/etc/step-ca/certs/root_ca.crt",
  "federate": [],
  "crt": "/etc/step-ca/certs/intermediate_ca.crt",
  "key": "/etc/step-ca/secrets/intermediate_ca_key",
  "address": ":443",
  "dnsNames": [
    "ica.dc.paradigm-works.com"
  ],
  "logger": {
    "format": "text"
  },
  "db": {
    "type": "bbolt",
    "dataSource": "/var/lib/step-ca/db"
  },
  "authority": {
    "provisioners": [
      {
        "type": "ACME",
        "name": "acme",
        "claims": {
          "minTLSCertDuration": "1h",
          "maxTLSCertDuration": "24h",
          "defaultTLSCertDuration": "24h"
        },
        "options": {
          "x509": {
            "templateFile": "/etc/step-ca/templates/x509-leaf.tpl"
          }
        }
      }
    ],
    "template": {
      "x509": "/etc/step-ca/templates/x509-leaf.tpl"
    }
  },
  "tls": {
    "cipherSuites": [
      "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
      "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305"
    ],
    "minVersion": 1.2,
    "maxVersion": 1.3
  }
}

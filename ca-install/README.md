# CA Install
This template provides an example where a CA certificate can be mounted within a workspaces and added as a trusted certificate.

This is useful in cases where using an internal CA or self-signed certificate and not wanting to create a custom image that includes the certificate.

It uses an emptyDir volume for the trusted certificates mounted to /etc/ssl/certs and relies on the ca-certificates package.

## Steps

### Create CA (optional)
```shell
openssl genrsa -aes256 -out my-ca.key 4096
openssl req -x509 -new -nodes -key my-ca.key -sha256 -days 1826 -out my-ca.crt -subj '/CN=MyOrg Root CA/C=US/ST=Texas/L=Austin/O=MyOrg'
```

### Add Certificate as Secret
```shell
kubectl create secret generic my-ca --from-file=./my-ca.crt 
```

### Set Cert Variable
```shell
coder templates create my-template-with-ca --variable namespace=coder --variable cert_name=my-ca
```

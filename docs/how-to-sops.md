# How to Use SOPS to Encrypt the Configuration File (**outdated**)

Sometimes configuration files contain sensitive data, such as passwords or private keys. To protect this data, you can use SOPS to encrypt the file. SOPS encrypts the sensitive data using PGP encryption, which can only be decrypted by those who have the secret key. Here are the steps to use SOPS to encrypt a configuration file:

## Generate a PGP key pair

Before you can use sops to encrypt a file, you need to generate a PGP key pair. You can do this using the `gpg` command. Here's an example of how to generate a PGP key pair:
```
gpg --batch --generate-key <<EOF
%no-protection
Key-Type: default
Subkey-Type: default
Name-Real: Validator
Name-Email: validator@ponkila.com
Expire-Date: 0
EOF
```

## Find the public fingerprint for the newly generated key

To use SOPS to encrypt a file, you need to specify the PGP key to use. You can do this by specifying the key's public fingerprint. Here's an example of how to find the public fingerprint for the newly generated key:
```
gpg --list-keys "validator@ponkila.com" | grep pub -A 1 | grep -v pub
```

## Use SOPS to encrypt the sensitive fields in the file

Once you have a PGP key pair and the public fingerprint for the key, you can use sops to encrypt the sensitive fields in the configuration file. Here's an example of how to use sops to encrypt the fields that match the regular expression `^(public_key|private_key|endpoint)$`:
```
sops --encrypt --in-place --encrypted-regex '^(public_key|private_key|endpoint)$' --pgp <KEY> config.yml
```
In this command, `<KEY>` should be replaced with the public fingerprint for the PGP key.

## Decrypt the configuration file

To decrypt the configuration file, you can use the `sops` command with the `--decrypt` option. Here's an example of how to decrypt the file:
```
sops --decrypt config.yml
```
## Export and Import the PGP keys

To use the PGP keys on a different machine or to share the keys with someone else, you can export the keys using the `gpg` command:
```
gpg --export -a "validator@ponkila.com" > public.key
gpg --export-secret-key -a "validator@ponkila.com" > private.key
```
To import the keys, use the `gpg --import` command:
```
gpg --import public.key
gpg --allow-secret-key-import --import private.key
```

## Links
- https://github.com/mozilla/sops
- https://poweruser.blog/how-to-encrypt-secrets-in-config-files-1dbb794f7352
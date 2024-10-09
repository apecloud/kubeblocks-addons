{{- $key := sshKeyGen }}
id_rsa={{ $key.PrivateKey | quote }}
id_rsa.pub={{ $key.PublicKey | quote }}
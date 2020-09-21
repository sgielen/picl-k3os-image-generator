# Config files

Name each file using MAC address with `.yml` suffix

## Examples


Master node config file named `dc:a6:32:16:e9:8b.yaml`

```yaml
# n1
ssh_authorized_keys:
- ssh-rsa AAAAB3N...
hostname: n1
k3os:
  ntp_servers:
  - NTP_SERVER_IP_OR_HOSTNAME
  k3s_args:
  - server
```


Worker node config file named `dc:a6:32:76:34:b5.yaml`

```yaml
# n2
ssh_authorized_keys:
- ssh-rsa AAAAB3N...
hostname: n2
k3os:
  ntp_servers:
  - NTP_SERVER_IP_OR_HOSTNAME
  k3s_args:
  - agent
  token: MASTER_TOKEN
  server_url: https://MASTER_IP:6443
```

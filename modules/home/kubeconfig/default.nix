{ lib, pkgs, config, ... }:
# Generates ~/.kube/config at activation time from sops-encrypted secrets.
#
# TLS notes:
#  - it2go-main pins the k3s server CA (caData) and authenticates with the
#    admin client cert below. k3s rotates the cert server-side; to refresh:
#      ssh root@157.180.115.27 cat /etc/rancher/k3s/k3s.yaml
#    then update clientCertData here and re-encrypt clientKeyData into
#    secrets/kubeconfig/it2go-main.json with sops.
#  - tmobile-prod/test keep insecure-skip-tls-verify because the Rancher
#    ingress presents the ephemeral nginx "Kubernetes Ingress Controller Fake
#    Certificate" — there is no stable CA to pin until the ingress gets a real
#    certificate. Fixing that is a cluster-side change.
let
  dagLib =
    if config ? lib && config.lib ? dag then
      config.lib.dag
    else if lib ? hm then
      lib.hm.dag
    else
      throw "home kubeconfig module: unable to locate DAG helpers (expected config.lib.dag or lib.hm.dag).";
  kubeConfigPath = "${config.home.homeDirectory}/.kube/config";
  kubeConfigDir = builtins.dirOf kubeConfigPath;
  ageKeyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
  sopsBin = lib.getExe pkgs.sops;
  jqBin = lib.getExe pkgs.jq;
  mktempBin = "${pkgs.coreutils}/bin/mktemp";
  installBin = "${pkgs.coreutils}/bin/install";
  escape = lib.escapeShellArg;
  secretsDirCandidates = [
    "${config.home.homeDirectory}/nixos2/secrets/kubeconfig"
    "${config.home.homeDirectory}/home/secrets/kubeconfig"
  ];
  secretsDirCandidatesShell = lib.concatMapStringsSep " " escape secretsDirCandidates;
  caData = ''
LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUJkekNDQVIyZ0F3SUJBZ0lCQURBS0JnZ3Foa2pPUFFRREFqQWpNU0V3SHdZRFZRUUREQmhyTTNNdGMyVnkKZG1WeUxXTmhRREUzTkRnMU9UWTRPRGN3SGhjTk1qVXdOVE13TURreU1USTNXaGNOTXpVd05USTRNRGt5TVRJMwpXakFqTVNFd0h3WURWUVFEREJock0zTXRjMlZ5ZG1WeUxXTmhRREUzTkRnMU9UWTRPRGN3V1RBVEJnY3Foa2pPClBRSUJCZ2dxaGtqT1BRTUJCd05DQUFSenJCSUs5Q1ZFSkRVd0VtYUJqOUFYczM5YUtVQi9ONm1KWUJzUUp5WDMKZmx6N3lVaXkvclFGaFFaRlVqbko4bkhYSWRFRXBuZTQydUdIcVZVcExGSG9vMEl3UURBT0JnTlZIUThCQWY4RQpCQU1DQXFRd0R3WURWUjBUQVFIL0JBVXdBd0VCL3pBZEJnTlZIUTRFRmdRVTdycjVCZHpyOUl1Q2dLb3dXWmRqCk5UUHFiUFl3Q2dZSUtvWkl6ajBFQXdJRFNBQXdSUUlnYTJVM3VreDhvU3ZqbUM4b05STThWdkZhbFl3RmZVaWsKRlc5c2ttUStVMGdDSVFDcm5MYVRhSGZzM0psQ2M4Q2c4bjU5QnQraktvMVgzTGx2Tk9PeHZKdm9VQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K'';
  # Issued 2025-05-30, expires 2027-06-04 (see renewal instructions above).
  clientCertData = ''
LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUJrRENDQVRlZ0F3SUJBZ0lJRHp6S0YwekRyL2t3Q2dZSUtvWkl6ajBFQXdJd0l6RWhNQjhHQTFVRUF3d1kKYXpOekxXTnNhV1Z1ZEMxallVQXhOelE0TlRrMk9EZzNNQjRYRFRJMU1EVXpNREE1TWpFeU4xb1hEVEkzTURZdwpOREV4TVRFek9Wb3dNREVYTUJVR0ExVUVDaE1PYzNsemRHVnRPbTFoYzNSbGNuTXhGVEFUQmdOVkJBTVRESE41CmMzUmxiVHBoWkcxcGJqQlpNQk1HQnlxR1NNNDlBZ0VHQ0NxR1NNNDlBd0VIQTBJQUJJdVJwUnkxbDBYRXhQanEKOHZqWEZIYVlXUUh4a2UvQnFpTjhzSlZkNlQ5OVAyOXR4ZTVxQWpGTFhoMDBJOWJWVVlhbFQyNjA4QVA0YjVxWQpXRmk4RUtPalNEQkdNQTRHQTFVZER3RUIvd1FFQXdJRm9EQVRCZ05WSFNVRUREQUtCZ2dyQmdFRkJRY0RBakFmCkJnTlZIU01FR0RBV2dCVEZPYVhwZXpUaWo1V2RIUnpIbnZhZzRkRE1LVEFLQmdncWhrak9QUVFEQWdOSEFEQkUKQWlBMXJUYkQ5K2NZMnhmRkxBZWxWMUk3RmhhYjNOb2V5cWZWSXl4Q0dPQlJKd0lnR081RUh0dzBTUzJPSnA1bApFWWlYYWxEcU5DUnJlQzZrbGFPai9mQ0k0RnM9Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0KLS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUJlRENDQVIyZ0F3SUJBZ0lCQURBS0JnZ3Foa2pPUFFRREFqQWpNU0V3SHdZRFZRUUREQmhyTTNNdFkyeHAKWlc1MExXTmhRREUzTkRnMU9UWTRPRGN3SGhjTk1qVXdOVE13TURreU1USTNXaGNOTXpVd05USTRNRGt5TVRJMwpXakFqTVNFd0h3WURWUVFEREJock0zTXRZMnhwWlc1MExXTmhRREUzTkRnMU9UWTRPRGN3V1RBVEJnY3Foa2pPClBRSUJCZ2dxaGtqT1BRTUJCd05DQUFRc1NJTGowNHNVVzJTQ0I3MndHVk11cWxQYlA0MWlkenZORTlhM0FiUjEKaHlnWmZXVUh1amlFZ0g3UmlKZ040QjZWVktqb09jQ3ZQRnhlbmZZRGphdTVvMEl3UURBT0JnTlZIUThCQWY4RQpCQU1DQXFRd0R3WURWUjBUQVFIL0JBVXdBd0VCL3pBZEJnTlZIUTRFRmdRVXhUbWw2WHMwNG8rVm5SMGN4NTcyCm9PSFF6Q2t3Q2dZSUtvWkl6ajBFQXdJRFNRQXdSZ0loQUxuNTJ0QURIT01Fb3hnWFRMazN6WUtvQ0x1T1V6L0IKdXZoOGdXaUtyajJPQWlFQW5JdGltNTZZYklnelkvY2FBQWR4b3VtUWtKU2VCSlFsK0Z5b0RJSHFtdk09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K'';
in
lib.mkIf (pkgs.stdenv.isLinux || pkgs.stdenv.isDarwin) {
  # Missing secrets or age key must not abort the whole home-manager
  # activation (fresh machine, key not provisioned yet) — warn and skip.
  home.activation.kubeconfig = dagLib.entryAfter ["writeBoundary"] ''
    set -eu
    set -o pipefail

    kubeconfig_skip=""

    secrets_dir=""
    for candidate in ${secretsDirCandidatesShell}; do
      if [ -d "$candidate" ]; then
        secrets_dir="$candidate"
        break
      fi
    done

    if [ -z "$secrets_dir" ]; then
      echo "kubeconfig: secrets directory not found (looked in: ${secretsDirCandidatesShell}); skipping" >&2
      kubeconfig_skip=1
    elif [ ! -f ${escape ageKeyFile} ]; then
      echo "kubeconfig: sops age key ${escape ageKeyFile} not found; skipping" >&2
      kubeconfig_skip=1
    else
      for secret_file in "$secrets_dir/it2go-main.json" "$secrets_dir/tmobile-prod.json" "$secrets_dir/tmobile-test.json"; do
        if [ ! -f "$secret_file" ]; then
          echo "kubeconfig: secret file not found: $secret_file; skipping" >&2
          kubeconfig_skip=1
        fi
      done
    fi

    if [ -z "$kubeconfig_skip" ]; then
      if ! it2go_main_key=$(
        SOPS_AGE_KEY_FILE=${escape ageKeyFile} ${escape sopsBin} --decrypt "$secrets_dir/it2go-main.json" \
          | ${escape jqBin} -r '.clientKeyData'
      ) || ! tmobile_prod_token=$(
        SOPS_AGE_KEY_FILE=${escape ageKeyFile} ${escape sopsBin} --decrypt "$secrets_dir/tmobile-prod.json" \
          | ${escape jqBin} -r '.token'
      ) || ! tmobile_test_token=$(
        SOPS_AGE_KEY_FILE=${escape ageKeyFile} ${escape sopsBin} --decrypt "$secrets_dir/tmobile-test.json" \
          | ${escape jqBin} -r '.token'
      ); then
        echo "kubeconfig: failed to decrypt secrets; skipping" >&2
        kubeconfig_skip=1
      fi
    fi

    if [ -z "$kubeconfig_skip" ]; then
      for v in "$it2go_main_key" "$tmobile_prod_token" "$tmobile_test_token"; do
        if [ -z "$v" ] || [ "$v" = "null" ]; then
          echo "kubeconfig: a secret decrypted to an empty value; skipping" >&2
          kubeconfig_skip=1
        fi
      done
    fi

    if [ -z "$kubeconfig_skip" ]; then
      tmpConfig=$(${escape mktempBin})
      trap 'rm -f "$tmpConfig"' EXIT

      mkdir -p ${escape kubeConfigDir}
      cat >"$tmpConfig" <<EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: ${caData}
    server: https://157.180.115.27:6443
  name: it2go-main
- cluster:
    insecure-skip-tls-verify: true
    server: https://rancher.acho.loc/k8s/clusters/local
  name: tmobile-prod
- cluster:
    insecure-skip-tls-verify: true
    server: https://test-rancher.acho.loc/k8s/clusters/local
  name: tmobile-test
contexts:
- context:
    cluster: it2go-main
    user: it2go-main
  name: it2go-main
- context:
    cluster: tmobile-prod
    user: tmobile-prod
  name: tmobile-prod
- context:
    cluster: tmobile-test
    user: tmobile-test
  name: tmobile-test
current-context: it2go-main
kind: Config
preferences: {}
users:
- name: it2go-main
  user:
    client-certificate-data: ${clientCertData}
    client-key-data: $it2go_main_key
- name: tmobile-prod
  user:
    token: $tmobile_prod_token
- name: tmobile-test
  user:
    token: $tmobile_test_token
EOF
      ${escape installBin} -m600 "$tmpConfig" ${escape kubeConfigPath}
    fi
  '';
}

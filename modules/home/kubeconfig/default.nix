{ lib, pkgs, config, ... }:
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
  it2goSecretFile = ../../../secrets/kubeconfig/it2go-main.json;
  tmobileProdSecretFile = ../../../secrets/kubeconfig/tmobile-prod.json;
  tmobileTestSecretFile = ../../../secrets/kubeconfig/tmobile-test.json;
  ageKeyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
  sopsBin = lib.getExe pkgs.sops;
  jqBin = lib.getExe pkgs.jq;
  mktempBin = "${pkgs.coreutils}/bin/mktemp";
  installBin = "${pkgs.coreutils}/bin/install";
  escape = lib.escapeShellArg;
  caData = ''
LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUJkekNDQVIyZ0F3SUJBZ0lCQURBS0JnZ3Foa2pPUFFRREFqQWpNU0V3SHdZRFZRUUREQmhyTTNNdGMyVnkKZG1WeUxXTmhRREUzTkRnMU9UWTRPRGN3SGhjTk1qVXdOVE13TURreU1USTNXaGNOTXpVd05USTRNRGt5TVRJMwpXakFqTVNFd0h3WURWUVFEREJock0zTXRjMlZ5ZG1WeUxXTmhRREUzTkRnMU9UWTRPRGN3V1RBVEJnY3Foa2pPClBRSUJCZ2dxaGtqT1BRTUJCd05DQUFSenJCSUs5Q1ZFSkRVd0VtYUJqOUFYczM5YUtVQi9ONm1KWUJzUUp5WDMKZmx6N3lVaXkvclFGaFFaRlVqbko4bkhYSWRFRXBuZTQydUdIcVZVcExGSG9vMEl3UURBT0JnTlZIUThCQWY4RQpCQU1DQXFRd0R3WURWUjBUQVFIL0JBVXdBd0VCL3pBZEJnTlZIUTRFRmdRVTdycjVCZHpyOUl1Q2dLb3dXWmRqCk5UUHFiUFl3Q2dZSUtvWkl6ajBFQXdJRFNBQXdSUUlnYTJVM3VreDhvU3ZqbUM4b05STThWdkZhbFl3RmZVaWsKRlc5c2ttUStVMGdDSVFDcm5MYVRhSGZzM0psQ2M4Q2c4bjU5QnQraktvMVgzTGx2Tk9PeHZKdm9VQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K'';
  clientCertData = ''
LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUJrRENDQVRlZ0F3SUJBZ0lJR2pYNnVzL1VtcHN3Q2dZSUtvWkl6ajBFQXdJd0l6RWhNQjhHQTFVRUF3d1kKYXpOekxXTnNhV1Z1ZEMxallVQXhOelE0TlRrMk9EZzNNQjRYRFRJMU1EVXpNREE1TWpFeU4xb1hEVEkyTURVegpNREE1TWpFeU4xb3dNREVYTUJVR0ExVUVDaE1PYzNsemRHVnRPbTFoYzNSbGNuTXhGVEFUQmdOVkJBTVRESE41CmMzUmxiVHBoWkcxcGJqQlpNQk1HQnlxR1NNNDlBZ0VHQ0NxR1NNNDlBd0VIQTBJQUJLcmhBaHVrZE9odWZsOGwKV2RNT1Fzb1pqS01Ea3RkZFlkRW9FeVc1YVdYNjV4RURPOXZmZGRaS0V3YzRTN2JMMDdwcld4akhOVTBRa1V0VApjdXNYR2tPalNEQkdNQTRHQTFVZER3RUIvd1FFQXdJRm9EQVRCZ05WSFNVRUREQUtCZ2dyQmdFRkJRY0RBakFmCkJnTlZIU01FR0RBV2dCVEZPYVhwZXpUaWo1V2RIUnpIbnZhZzRkRE1LVEFLQmdncWhrak9QUVFEQWdOSEFEQkUKQWlBOU45Qm9tbUE1RHQrS3NETkVZUnJpcGxjbjFFckxlUEU1RUNtdTI1QVhlUUlnUkhaU0pkSmZycWR6RkNveAoyZzNwbmYrY2lnVk5EM21WNkxpZWRvTkxDdTg9Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K'';
in
lib.mkIf (pkgs.stdenv.isLinux || pkgs.stdenv.isDarwin) {
  home.activation.kubeconfig = dagLib.entryAfter ["writeBoundary"] ''
    set -eu
    set -o pipefail

    it2go_main_key=$(
      SOPS_AGE_KEY_FILE=${escape ageKeyFile} ${escape sopsBin} --decrypt ${escape it2goSecretFile} \
        | ${escape jqBin} -r '.clientKeyData'
    )
    tmobile_prod_token=$(
      SOPS_AGE_KEY_FILE=${escape ageKeyFile} ${escape sopsBin} --decrypt ${escape tmobileProdSecretFile} \
        | ${escape jqBin} -r '.token'
    )
    tmobile_test_token=$(
      SOPS_AGE_KEY_FILE=${escape ageKeyFile} ${escape sopsBin} --decrypt ${escape tmobileTestSecretFile} \
        | ${escape jqBin} -r '.token'
    )

    if [ -z "$it2go_main_key" ]; then
      echo "failed to read it2go-main client key from secret" >&2
      exit 1
    fi
    if [ -z "$tmobile_prod_token" ]; then
      echo "failed to read tmobile-prod token from secret" >&2
      exit 1
    fi
    if [ -z "$tmobile_test_token" ]; then
      echo "failed to read tmobile-test token from secret" >&2
      exit 1
    fi

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
  '';
}

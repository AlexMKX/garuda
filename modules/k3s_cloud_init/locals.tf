locals {
  _install_exec_args = concat(
    [
      "server",
      # The k3s API is kept off the public network by host firewall
      # rules (no `tcp/6443` in default_ingress, see
      # modules/gcp_compute_host / yc_compute_host). Inside the node we
      # let kube-apiserver bind to all interfaces so that:
      #
      #   * the default `kubernetes` ClusterIP service (10.43.0.1:443)
      #     resolves to an endpoint on the node primary IP that
      #     kube-proxy iptables-DNATs to 6443 — without that, every
      #     cluster-network consumer (coredns, metrics-server,
      #     whereabouts, helm-install jobs) hits ECONNREFUSED and the
      #     node degrades within minutes.
      #   * kubernetes endpoint validation forbids loopback addresses
      #     in `Endpoints.subsets[].addresses[].ip`, so
      #     `--advertise-address=127.0.0.1` is also out.
      #
      # `--tls-san=127.0.0.1` lets the operator-side kubeconfig keep
      # using `https://127.0.0.1:<local-forward-port>` as the server
      # URL: the certificate's SAN list now matches that hostname.
      "--tls-san=127.0.0.1",
      "--https-listen-port=6443",
      # k3s default mode for /etc/rancher/k3s/k3s.yaml is 0600 root:root,
      # which blocks any non-root user (incl. the `garuda` management
      # user) from reading it over SFTP via garuda-tunnel fetch_files.
      # 0644 lets garuda-tunnel pull the kubeconfig with a plain
      # non-root SSH login; the only other shell user on edge VMs is
      # `garuda` itself, so the wider read does not extend the threat
      # surface meaningfully.
      "--write-kubeconfig-mode=0644",
    ],
    var.extra_flags,
  )

  _install_exec = join(" ", local._install_exec_args)

  _env_prefix = join(" ", concat(
    var.k3s_version == null ? [] : ["INSTALL_K3S_VERSION=${var.k3s_version}"],
    ["INSTALL_K3S_EXEC=\"${local._install_exec}\""],
    [for k, v in var.extra_install_env : "${k}=${v}"],
  ))

  _cloud_config = <<EOT
#cloud-config
write_files:
  - path: /usr/local/sbin/garuda-k3s-cni-reload.sh
    permissions: "0755"
    owner: root:root
    content: |
      #!/bin/bash
      # Wait until the Multus DaemonSet writes 00-multus.conf into
      # the k3s CNI config dir, then restart k3s so kubelet rescans
      # and starts dispatching pod sandbox creates through multus-shim.
      #
      # Self-disabling: drop a marker after the first successful
      # restart so subsequent boots / unit reloads do not bounce
      # kubelet again.
      set -euo pipefail

      marker=/var/lib/garuda-k3s-cni-reload.done
      [[ -e "$marker" ]] && exit 0

      deadline=$(( $(date +%s) + 600 ))
      multus_conf=/var/lib/rancher/k3s/agent/etc/cni/net.d/00-multus.conf

      while [[ ! -e "$multus_conf" ]]; do
        if [[ $(date +%s) -ge $deadline ]]; then
          echo "garuda-k3s-cni-reload: 00-multus.conf did not appear in 10 min" >&2
          exit 1
        fi
        sleep 5
      done

      echo "garuda-k3s-cni-reload: 00-multus.conf detected; restarting k3s"
      systemctl restart k3s
      mkdir -p "$(dirname "$marker")"
      touch "$marker"

  - path: /etc/systemd/system/garuda-k3s-cni-reload.service
    permissions: "0644"
    owner: root:root
    content: |
      [Unit]
      Description=Restart k3s once Multus' 00-multus.conf is in place so kubelet picks it up
      After=k3s.service
      Wants=k3s.service

      [Service]
      Type=oneshot
      ExecStart=/usr/local/sbin/garuda-k3s-cni-reload.sh
      RemainAfterExit=true
      Restart=on-failure
      RestartSec=30

      [Install]
      WantedBy=multi-user.target

runcmd:
  - curl -sfL ${var.install_url} | ${local._env_prefix} sh -
  - systemctl daemon-reload
  - systemctl enable --now garuda-k3s-cni-reload.service
EOT
}

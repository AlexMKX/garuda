output "user_data_parts" {
  description = <<EOT
List with exactly one cloud-config string that installs k3s on first boot.
Feed this verbatim into the compute-host module's user_data_parts.
EOT
  value       = [local._cloud_config]
}

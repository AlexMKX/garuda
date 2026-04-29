output "firezone_dir" {
  description = "Effective Firezone compose project directory returned by the workload."
  value       = try(module.apply.outputs["firezone_dir"], null)
  sensitive   = true
}

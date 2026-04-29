output "applied" {
  description = "Merged payload+ansible outputs from the linux_apply run."
  value       = module.apply.outputs
  sensitive   = true
}

output "outputs" {
  description = "Shallow merged workload outputs: merge(payload, ansible_outputs)."
  value       = local.merged_outputs
  sensitive   = true
}

output "apply_log" {
  description = "Plain-text per-task ansible log: ISO8601 timestamp + host + status + task name, one line per task. Empty string until the first apply finishes; preserved across plan-only re-evaluations until the next apply overwrites the result file."
  value       = try(local.raw_result.apply_log, "")
}

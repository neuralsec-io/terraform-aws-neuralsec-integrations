output "container_definitions" {
  description = "The rewritten container definitions, sidecar appended."
  # Joined as text: the containers are heterogeneous JSON objects, and string
  # assembly keeps Terraform from needing a single object type for all of them.
  value = "[${join(",", concat(local.encoded_containers, local.appended))}]"
}

output "pid_mode" {
  description = "Task pidMode: task when the observer or tracer needs a shared PID namespace, else null."
  value       = (var.enable_observer || var.enable_ptrace) ? "task" : null
}

output "volumes" {
  description = "Task volumes to merge into the task definition; the sidecar and app containers share neuralsec-sensor-lib."
  value = [
    {
      name = "neuralsec-sensor-lib"
    },
  ]
}

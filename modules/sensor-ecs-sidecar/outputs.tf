output "container_definitions" {
  description = "The rewritten container definitions, sidecar appended."
  # Joined as text: the containers are heterogeneous JSON objects, and string
  # assembly keeps Terraform from needing a single object type for all of them.
  value = "[${join(",", concat(local.encoded_containers, local.appended))}]"
}

output "pid_mode" {
  description = "Task pidMode: task when the observer, tracer or hook ring drain needs a shared PID namespace, else null."
  value       = local.sidecar_needed ? "task" : null
}

output "volumes" {
  description = "Task volumes to merge into the task definition: neuralsec-sensor-lib (hook builds) and neuralsec-sensor-ring (per-container hook rings), shared by the sidecar and the app containers."
  value = [
    {
      name = "neuralsec-sensor-lib"
    },
    {
      name = "neuralsec-sensor-ring"
    },
  ]
}

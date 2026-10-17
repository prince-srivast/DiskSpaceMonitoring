locals {
  common_tags = {
    Application    = "disk-space-monitoring"
    Environment    = "test"
    ManagedBy      = "Terraform"
    DiskMonitoring = "enabled"
  }

  agent_config = jsonencode({
    agent = {
      metrics_collection_interval = 300
      run_as_user                 = "root"
    }
    metrics = {
      namespace = "CWAgent"
      append_dimensions = {
        InstanceId   = "$${aws:InstanceId}"
        InstanceType = "$${aws:InstanceType}"
        ImageId      = "$${aws:ImageId}"
      }
      aggregation_dimensions = [["InstanceId", "path"]]
      metrics_collected = {
        disk = {
          measurement                 = ["used_percent"]
          metrics_collection_interval = 300
          resources                   = ["*"]
          drop_device                 = true
          ignore_file_system_types = [
            "sysfs", "devtmpfs", "tmpfs", "overlay", "squashfs",
            "proc", "smbfs", "cgroup", "cgroup2", "tracefs", "nsfs"
          ]
        }
      }
    }
  })
}

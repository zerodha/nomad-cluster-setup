datacenter = "${nomad_dc}"
data_dir   = "/opt/nomad/data"

log_level = "INFO"

bind_addr = "0.0.0.0"

advertise {
  http = "{{ GetInterfaceIP \"ens5\" }}"
  rpc  = "{{ GetInterfaceIP \"ens5\" }}"
  serf = "{{ GetInterfaceIP \"ens5\" }}"
}

consul {
  auto_advertise   = false
  server_auto_join = false
  client_auto_join = false
}

vault {
  enabled = false
}

acl {
  enabled = true
}

telemetry {
  collection_interval        = "15s"
  disable_hostname           = true
  prometheus_metrics         = true
  publish_allocation_metrics = true
  publish_node_metrics       = true
}

server {
  enabled          = true
  bootstrap_expect = "${nomad_bootstrap_expect}"
  encrypt          = "${nomad_gossip_encrypt_key}"
  server_join {
    retry_join = ["provider=aws region=${aws_region} tag_key=${nomad_join_tag_key} tag_value=${nomad_join_tag_value}"]
  }
}

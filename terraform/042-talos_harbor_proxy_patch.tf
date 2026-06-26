resource "local_file" "harbor_proxy" {
  filename = "${path.module}/talos_crds/tmp/harbor_proxy.yaml"
  content = templatefile("${path.module}/talos_crds/templates/harbor_proxy.tftpl", {
    dns_zone = var.dns_zone
    password = var.harbor_talos_robot_password
  })
}
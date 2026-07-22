#!/usr/bin/env -S just --justfile
# ^ A shebang isn't required, but allows a justfile to be executed
#   like a script, with `./justfile test`, for example.

install:
	just update
	sudo apt-get install ansible-core
	curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh -o install-opentofu.sh
	chmod +x install-opentofu.sh
	./install-opentofu.sh --install-method deb
	rm -f install-opentofu.sh

	sudo apt-get install pipx
	sudo pipx install checkov
	pipx ensurepath

	sudo apt-get install curl gpg apt-transport-https --yes
	curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
	echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
	sudo apt-get update
	sudo apt-get install helm

update:
	sudo apt-get update && sudo apt-get upgrade

check:
	checkov -d ./

## terraform/tofu stuff
init:
	cd infrastructure/terraform && tofu init

tformat:
	cd infrastructure/terraform && terraform fmt

plan *args:
	cd infrastructure/terraform && tofu plan -out tfplan {{args}}

apply *args:
	cd infrastructure/terraform && tofu apply {{args}}

destroy:
	cd infrastructure/terraform && tofu destroy -exclude=proxmox_virtual_environment_download_file.ubuntu_cloud_image_1 -exclude=proxmox_virtual_environment_download_file.ubuntu_cloud_image_2 -exclude=proxmox_virtual_environment_download_file.ubuntu_cloud_image_3 -exclude=proxmox_virtual_environment_download_file.pf_sense_iso_2

apply_target TARGET:
	cd infrastructure/terraform && tofu apply -target={{TARGET}}

destroy_target TARGET:
	cd infrastructure/terraform && tofu destroy -target={{TARGET}}

## terraform/tofu targeted commands
dns01 action:
	cd infrastructure/terraform && tofu {{action}} -target=proxmox_virtual_environment_vm.dns01

## ansible stuff
whoami:
	cd ansible && ansible-playbook -b whoami.yaml
atest:
	cd ansible && ansible-playbook -i inventory.yaml all -m ping

run HOST *TAGS:
	cd ansible && ansible-playbook -b run.yaml --limit {{HOST}} {{TAGS}}

run_all:
	cd ansible && ansible-playbook -b run.yaml

update_everything:
	cd infrastructure/ansible && ansible-playbook -b update_everything.yaml

## repo stuff
# optionally use --force to force reinstall all requirements
reqs *FORCE:
	cd ansible && ansible-galaxy install -r requirements.yaml {{FORCE}}

# ansible vault (encrypt/decrypt/edit)
vault ACTION:
	cd ansible && EDITOR='code --wait' ansible-vault {{ACTION}} vars/secrets.yaml

# Kubernetes Stuff
kinstall:
	sudo apt-get update
	sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
	curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
	sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
	echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
	sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list
	sudo apt-get update
	sudo apt-get install -y kubectl

kconfig:
	cp ./kubeconfig ~/.kube/config

tconfig:
	cp ./talosconfig ~/.talos/config
mount:
	sudo mount -v -t nfs -o vers=4.2 nfs.thegraveshouse.com:/ /home/chloe/nfs

umount:
	sudo umount /home/chloe/nfs

yamltotf FILE:
	tfk8s -f {{FILE}} -o {{FILE}}.tf

startupgrade:
	kubectl cordon k8cp1
	kubectl cordon k8cp2
	kubectl cordon k8mc1
	kubectl cordon k8mw1
	kubectl cordon k8mw2
	kubectl cordon k8mw3
	
endupgrade:
	kubectl uncordon k8cp1
	kubectl uncordon k8cp2
	kubectl uncordon k8mc1
	kubectl uncordon k8mw1
	kubectl uncordon k8mw2
	kubectl uncordon k8mw3

update_k8s:
	talosctl --nodes 192.168.0.223 upgrade-k8s --to 1.36.2

stopcluster_checks:
	kubectl get pdb -A

# Scale apps to 0
stopcluster1:
	# Nextcloud
	kubectl scale deployment -n nextcloud nextcloud --replicas=0
	kubectl scale deployment -n nextcloud nextcloud-collabora --replicas=0
	kubectl scale deployment -n nextcloud nextcloud-metrics --replicas=0
	# kubectl scale deployment -n nextcloud nfs-server --replicas=0
	kubectl scale deployment -n kiwix kiwix --replicas=0
	kubectl scale deployment -n jellyfin jellyfin --replicas=0
	kubectl scale deployment -n forgejo forgejo --replicas=0
	# kubectl scale deployment -n dns-server dns-server-0 --replicas=0
	# OAuth2
	kubectl scale deployment -n kiwix oauth2-proxy-kiwix-library --replicas=0
	kubectl scale deployment -n longhorn-system oauth2-proxy-longhorn --replicas=0
	kubectl scale deployment -n metrics oauth2-proxy-alertmanager --replicas=0
	kubectl scale deployment -n metrics prometheus-oauth2-proxy --replicas=0
	kubectl scale deployment -n traefik oauth2-proxy-traefik --replicas=0
	# Metrics
	kubectl scale deployment -n metrics kube-prometheus-stack-grafana --replicas=0
	kubectl scale deployment -n metrics kube-prometheus-stack-kube-state-metrics --replicas=0
	kubectl scale deployment -n metrics kube-prometheus-stack-operator --replicas=0
	kubectl scale statefulset -n metrics alertmanager-kube-prometheus-stack-alertmanager --replicas=0
	kubectl scale statefulset -n metrics prometheus-kube-prometheus-stack-prometheus --replicas=0
	# Mailu
	kubectl scale deployment -n mailu mailu-admin --replicas=0
	kubectl scale deployment -n mailu mailu-dovecot --replicas=0
	kubectl scale deployment -n mailu mailu-front --replicas=0
	kubectl scale deployment -n mailu mailu-oletools --replicas=0
	kubectl scale deployment -n mailu mailu-postfix --replicas=0
	kubectl scale deployment -n mailu mailu-rspamd --replicas=0
	kubectl scale deployment -n mailu mailu-tika --replicas=0
	kubectl scale deployment -n mailu mailu-webmail --replicas=0
	kubectl scale statefulset -n mailu mailu-clamav --replicas=0

stopcluster2:
	# Redis
	kubectl scale statefulset -n redis redis-master --replicas=0
	kubectl scale statefulset -n redis redis-replicas --replicas=0
	# Keycloak
	kubectl scale statefulset -n keycloak keycloak --replicas=0
	# Harbor
	kubectl scale deployment -n harbor harbor-core --replicas=0
	kubectl scale deployment -n harbor harbor-exporter --replicas=0
	kubectl scale deployment -n harbor harbor-jobservice --replicas=0
	kubectl scale deployment -n harbor harbor-portal --replicas=0
	kubectl scale deployment -n harbor harbor-registry --replicas=0
	kubectl scale statefulset -n harbor harbor-trivy --replicas=0

# Scale core software to 0
stopcluster3:
	kubectl scale deployment -n cert-manager cert-manager --replicas=0
	kubectl scale deployment -n cert-manager cert-manager-cainjector --replicas=0
	kubectl scale deployment -n cert-manager cert-manager-webhook --replicas=0
	kubectl scale statefulset -n postgresql-database postgresql --replicas=0
	kubectl scale deployment -n traefik traefik --replicas=0

# Cordon/Drain workers
stopcluster4:
	kubectl cordon k8mw1
	kubectl cordon k8mw2
	kubectl cordon k8mw3
	kubectl drain k8mw1 --ignore-daemonsets --delete-emptydir-data --timeout=300s
	kubectl drain k8mw2 --ignore-daemonsets --delete-emptydir-data --timeout=300s
	kubectl drain k8mw3 --ignore-daemonsets --delete-emptydir-data --timeout=300s

# Shutdown workers
stopcluster5:
	talosctl shutdown --nodes 192.168.0.233
	talosctl shutdown --nodes 192.168.0.234
	talosctl shutdown --nodes 192.168.0.235


# Drain controlplanes
stopcluster6:
	kubectl cordon k8cp1
	kubectl cordon k8cp3
	kubectl cordon k8mc1
	kubectl drain k8cp1 --ignore-daemonsets --delete-emptydir-data
	kubectl drain k8cp3 --ignore-daemonsets --delete-emptydir-data
	kubectl drain k8mc1 --ignore-daemonsets --delete-emptydir-data

# Shutdown controlplanes
stopcluster7:
	talosctl shutdown --nodes 192.168.0.220
	talosctl shutdown --nodes 192.168.0.221
	talosctl shutdown --nodes 192.168.0.223

startcluster1:
	kubectl uncordon k8cp1
	kubectl uncordon k8cp2
	kubectl uncordon k8mc1
	kubectl uncordon k8mw1
	kubectl uncordon k8mw2
	kubectl uncordon k8mw3

startcluster2:
	kubectl scale deployment -n cert-manager cert-manager --replicas=1
	kubectl scale deployment -n cert-manager cert-manager-cainjector --replicas=1
	kubectl scale deployment -n cert-manager cert-manager-webhook --replicas=1
	kubectl scale deployment -n longhorn-system longhorn-ui --replicas=1
	kubectl scale deployment -n traefik traefik --replicas=1
	kubectl scale statefulset -n postgresql-database postgresql --replicas=1
	kubectl scale statefulset -n redis redis-master --replicas=1
	kubectl scale statefulset -n redis redis-replicas --replicas=1

startcluster3:
	kubectl scale statefulset -n keycloak keycloak --replicas=1
	
	kubectl scale deployment -n harbor harbor-core --replicas=1
	kubectl scale deployment -n harbor harbor-exporter --replicas=1
	kubectl scale deployment -n harbor harbor-jobservice --replicas=1
	kubectl scale deployment -n harbor harbor-portal --replicas=1
	kubectl scale deployment -n harbor harbor-registry --replicas=1
	kubectl scale statefulset -n harbor harbor-trivy --replicas=1

startcluster4:
	kubectl scale deployment -n forgejo forgejo --replicas=1
	
	kubectl scale deployment -n nextcloud nextcloud --replicas=1
	kubectl scale deployment -n nextcloud nextcloud-collabora --replicas=1
	kubectl scale deployment -n nextcloud nextcloud-metrics --replicas=1
	# OAuth2
	kubectl scale deployment -n kiwix oauth2-proxy-kiwix-library --replicas=1
	kubectl scale deployment -n longhorn-system oauth2-proxy-longhorn --replicas=1
	kubectl scale deployment -n metrics oauth2-proxy-alertmanager --replicas=1
	kubectl scale deployment -n metrics prometheus-oauth2-proxy --replicas=1
	kubectl scale deployment -n traefik oauth2-proxy-traefik --replicas=1
	# Metrics
	kubectl scale deployment -n metrics kube-prometheus-stack-grafana --replicas=1
	kubectl scale deployment -n metrics kube-prometheus-stack-kube-state-metrics --replicas=1
	kubectl scale deployment -n metrics kube-prometheus-stack-operator --replicas=1
	kubectl scale statefulset -n metrics alertmanager-kube-prometheus-stack-alertmanager --replicas=1
	kubectl scale statefulset -n metrics prometheus-kube-prometheus-stack-prometheus --replicas=1
	# Mailu
	kubectl scale deployment -n mailu mailu-admin --replicas=1
	kubectl scale deployment -n mailu mailu-dovecot --replicas=1
	kubectl scale deployment -n mailu mailu-front --replicas=1
	kubectl scale deployment -n mailu mailu-oletools --replicas=1
	kubectl scale deployment -n mailu mailu-postfix --replicas=1
	kubectl scale deployment -n mailu mailu-rspamd --replicas=1
	kubectl scale deployment -n mailu mailu-tika --replicas=1
	kubectl scale deployment -n mailu mailu-webmail --replicas=1
	kubectl scale statefulset -n mailu mailu-clamav --replicas=1

startcluster5:
	kubectl scale deployment -n kiwix kiwix --replicas=1
	kubectl scale deployment -n jellyfin jellyfin --replicas=1
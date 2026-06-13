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
	cd terraform && tofu init

tformat:
	cd terraform && terraform fmt

plan *args:
	cd terraform && tofu plan -out tfplan {{args}}

apply *args:
	cd terraform && tofu apply {{args}}

destroy:
	cd terraform && tofu destroy -exclude=proxmox_virtual_environment_download_file.ubuntu_cloud_image_1 -exclude=proxmox_virtual_environment_download_file.ubuntu_cloud_image_2 -exclude=proxmox_virtual_environment_download_file.ubuntu_cloud_image_3 -exclude=proxmox_virtual_environment_download_file.pf_sense_iso_2

apply_target TARGET:
	cd terraform && tofu apply -target={{TARGET}}

destroy_target TARGET:
	cd terraform && tofu destroy -target={{TARGET}}

## terraform/tofu targeted commands
dns01 action:
	cd terraform && tofu {{action}} -target=proxmox_virtual_environment_vm.dns01

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
	cd ansible && ansible-playbook -b update_everything.yaml

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
	sudo mount -v -t nfs -o vers=4.2 nfs.chloepetta.net:/ /home/chloe/nfs

umount:
	sudo umount /home/chloe/nfs

yamltotf FILE:
	tfk8s -f {{FILE}} -o {{FILE}}.tf

stopcluster_checks:
	kubectl get pdb -A

# Scale apps to 0
stopcluster1:
	kubectl scale deployment -n nextcloud nextcloud --replicas=0
	kubectl scale deployment -n nextcloud nextcloud-collabora --replicas=0
	kubectl scale deployment -n nextcloud nextcloud-metrics --replicas=0
	kubectl scale deployment -n nextcloud nfs-server --replicas=0
	kubectl scale deployment -n nextcloud nfs-server --replicas=0
	kubectl scale deployment -n metrics kube-prometheus-stack-grafana --replicas=0
	kubectl scale deployment -n metrics kube-prometheus-stack-kube-state-metrics --replicas=0
	kubectl scale deployment -n metrics kube-prometheus-stack-operator --replicas=0
	kubectl scale deployment -n kiwix kiwix --replicas=0
	kubectl scale deployment -n jellyfin jellyfin --replicas=0
	kubectl scale deployment -n forgejo forgejo --replicas=0
	kubectl scale deployment -n dns-server dns-server-0 --replicas=0
	kubectl scale deployment -n traefik oauth2-proxy-kiwix-library --replicas=0
	kubectl scale deployment -n traefik oauth2-proxy-longhorn --replicas=0
	kubectl scale deployment -n traefik oauth2-proxy-metrics-alertmanager --replicas=0
	kubectl scale deployment -n traefik oauth2-proxy-metrics-prometheus --replicas=0
	kubectl scale deployment -n traefik oauth2-proxy-traefik --replicas=0
	kubectl scale statefulset -n metrics alertmanager-kube-prometheus-stack-alertmanager --replicas=0
	kubectl scale statefulset -n metrics prometheus-kube-prometheus-stack-prometheus --replicas=0
	kubectl scale statefulset -n keycloak keycloak --replicas=0

# Scale core software to 0
stopcluster2:
	kubectl scale deployment -n cert-manager cert-manager --replicas=0
	kubectl scale deployment -n cert-manager cert-manager-cainjector --replicas=0
	kubectl scale deployment -n cert-manager cert-manager-webhook --replicas=0
	kubectl scale deployment -n longhorn-system longhorn-ui --replicas=0
	kubectl scale statefulset -n postgresql-database postgresql --replicas=0
	kubectl scale deployment -n traefik traefik --replicas=0

# Cordon/Drain workers
stopcluster3:
	kubectl cordon k8mw1
	kubectl cordon k8mw2
	kubectl cordon k8s1
	kubectl drain k8mw1 --ignore-daemonsets --delete-emptydir-data --timeout=300s
	kubectl drain k8mw2 --ignore-daemonsets --delete-emptydir-data --timeout=300s
	kubectl drain k8s1 --ignore-daemonsets --delete-emptydir-data --timeout=300s

# Shutdown workers
stopcluster4:
	# talosctl shutdown --nodes 192.168.0.204 # migrated
	talosctl shutdown --nodes 192.168.0.230
	# talosctl shutdown --nodes 192.168.0.231 # migrated
	# talosctl shutdown --nodes 192.168.0.232 # migrated
	talosctl shutdown --nodes 192.168.0.233
	talosctl shutdown --nodes 192.168.0.234


# Drain controlplanes
stopcluster5:
	kubectl cordon k8cp1
	# kubectl cordon k8cp2 # migrated
	kubectl cordon k8cp3
	kubectl cordon k8mc1
	kubectl drain k8cp1 --ignore-daemonsets --delete-emptydir-data
	# kubectl drain k8cp2 --ignore-daemonsets --delete-emptydir-data # migrated
	kubectl drain k8cp3 --ignore-daemonsets --delete-emptydir-data
	kubectl drain k8mc1 --ignore-daemonsets --delete-emptydir-data

# Shutdown controlplanes
stopcluster6:
	talosctl shutdown --nodes 192.168.0.220
	talosctl shutdown --nodes 192.168.0.221
	# talosctl shutdown --nodes 192.168.0.222 # migrated
	talosctl shutdown --nodes 192.168.0.223

startcluster1:
	kubectl uncordon k8cp1
	kubectl uncordon k8cp3
	kubectl uncordon k8mc1
	kubectl uncordon k8mw1
	kubectl uncordon k8mw2
	kubectl uncordon k8s1

startcluster2:
	kubectl scale deployment -n cert-manager cert-manager --replicas=1
	kubectl scale deployment -n cert-manager cert-manager-cainjector --replicas=1
	kubectl scale deployment -n cert-manager cert-manager-webhook --replicas=1
	kubectl scale deployment -n longhorn-system longhorn-ui --replicas=1
	kubectl scale deployment -n traefik traefik --replicas=1
	kubectl scale statefulset -n postgresql-database postgresql --replicas=1

startcluster3:
	kubectl scale statefulset -n keycloak keycloak --replicas=1

startcluster4:
	kubectl scale deployment -n forgejo forgejo --replicas=1
	kubectl scale deployment -n metrics kube-prometheus-stack-grafana --replicas=1
	kubectl scale deployment -n metrics kube-prometheus-stack-kube-state-metrics --replicas=1
	kubectl scale deployment -n metrics kube-prometheus-stack-operator --replicas=1
	kubectl scale deployment -n nextcloud nextcloud --replicas=1
	kubectl scale deployment -n nextcloud nextcloud-collabora --replicas=1
	kubectl scale deployment -n nextcloud nextcloud-metrics --replicas=1
	kubectl scale deployment -n traefik oauth2-proxy-kiwix-library --replicas=1
	kubectl scale deployment -n traefik oauth2-proxy-longhorn --replicas=1
	kubectl scale deployment -n traefik oauth2-proxy-metrics-alertmanager --replicas=1
	kubectl scale deployment -n traefik oauth2-proxy-metrics-prometheus --replicas=1
	kubectl scale deployment -n traefik oauth2-proxy-traefik --replicas=1
	kubectl scale statefulset -n metrics alertmanager-kube-prometheus-stack-alertmanager --replicas=1
	kubectl scale statefulset -n metrics prometheus-kube-prometheus-stack-prometheus --replicas=1

startcluster5:
	kubectl scale deployment -n kiwix kiwix --replicas=1
	kubectl scale deployment -n jellyfin jellyfin --replicas=1
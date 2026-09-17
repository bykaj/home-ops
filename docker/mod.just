set default-list
set default-script
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[doc('Reconcile Doco-CD on TrueNAS')]
reconcile-nas:
    ansible-playbook -i "{{ source_directory() }}/../ansible/inventory.yaml" "{{ source_directory() }}/.ansible/nas/restart-doco-cd.yaml" --become-password-file <(op read 'op://Homelab/truenas/TRUENAS_ADMIN_PASSWORD')

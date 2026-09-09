#!/bin/bash
ansible-playbook -i inventory.yaml nas/playbook.yaml --ask-become-pass

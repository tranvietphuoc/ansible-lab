#!/usr/bin/env bash
set -euo pipefail

MASTER="teleport-master"
AUTH_SERVER="localhost:3025"
PROXY="localhost:3080"
USER="admin"
NODES="node-01 node-02 teleport-master"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

check_container() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${MASTER}$"; then
        log_error "Container '${MASTER}' is not running."
        log_info "Run: docker compose up -d"
        exit 1
    fi
}

# --- Step 3: Create admin user ---
step3_create_user() {
    log_info "Step 3: Checking if user '${USER}' exists..."

    if docker exec -i "${MASTER}" tctl --auth-server="${AUTH_SERVER}" users ls 2>/dev/null | grep -q "^${USER}"; then
        log_info "User '${USER}' already exists, skipping."
        return 0
    fi

    log_info "Creating user '${USER}'..."
    docker exec -i "${MASTER}" tctl --auth-server="${AUTH_SERVER}" users add "${USER}" --roles=editor,access

    log_warn "Open the link above in your browser to set password for '${USER}'."
    log_warn "After setting password, press Enter to continue..."
    read -r
}

# --- Step 4: Create role node-access and assign to admin ---
step4_create_role() {
    log_info "Step 4: Creating role 'node-access' and assigning to user '${USER}'..."

    docker exec -i "${MASTER}" bash -c 'cat <<EOF | tctl --auth-server='"${AUTH_SERVER}"' create -f
kind: role
version: v5
metadata:
  name: node-access
spec:
  allow:
    logins: [root, admin]
    node_labels:
      "*": "*"
  options:
    max_session_ttl: 30h0m0s
EOF'

    docker exec -i "${MASTER}" tctl --auth-server="${AUTH_SERVER}" users update "${USER}" --set-roles=editor,access,node-access

    log_info "Role 'node-access' created and assigned to '${USER}'."
}

# --- Step 5: Login to Teleport ---
step5_tsh_login() {
    log_info "Step 5: Logging in to Teleport as '${USER}'..."
    log_warn "Enter your Teleport password when prompted."

    docker exec -it "${MASTER}" tsh login --proxy="${PROXY}" --user="${USER}"

    log_info "Verifying login..."
    docker exec -i "${MASTER}" tsh status
}

# --- Step 6: Create SSH config for Ansible ---
step6_ssh_config() {
    log_info "Step 6: Creating SSH config for Ansible..."

    # Wait for tsh keys to be available
    local retries=0
    local max_retries=10
    while [ ${retries} -lt ${max_retries} ]; do
        if docker exec -i "${MASTER}" test -d /root/.tsh/keys/localhost; then
            break
        fi
        retries=$((retries + 1))
        log_warn "Waiting for tsh keys... (${retries}/${max_retries})"
        sleep 2
    done

    if [ ${retries} -eq ${max_retries} ]; then
        log_error "tsh keys not found. Did 'tsh login' succeed?"
        exit 1
    fi

    docker exec -i "${MASTER}" bash -c 'mkdir -p ~/.ssh && cat > ~/.ssh/config <<EOF
Host '"${NODES}"'
    UserKnownHostsFile /root/.tsh/known_hosts
    IdentityFile /root/.tsh/keys/localhost/admin
    CertificateFile /root/.tsh/keys/localhost/admin-ssh/teleport-master-cert.pub
    Port 3022
    StrictHostKeyChecking no
    ProxyCommand /usr/local/bin/tsh proxy ssh --cluster=teleport-master --proxy='"${PROXY}"' %r@%h:%p
EOF
chmod 600 ~/.ssh/config'

    log_info "SSH config created at /root/.ssh/config."
}

# --- Step 7: Verify SSH and Ansible ---
step7_verify() {
    log_info "Step 7: Verifying SSH and Ansible..."

    log_info "Testing SSH to node-01..."
    docker exec -i "${MASTER}" tsh ssh root@node-01 hostname

    log_info "Running Ansible ping..."
    docker exec -i "${MASTER}" bash -c 'cd /home/teleport/ansible && ansible all -m ping'

    log_info "All checks passed! Lab is ready."
}

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --all       Run all steps (3-7)"
    echo "  --user      Step 3: Create admin user"
    echo "  --role      Step 4: Create role & assign to user"
    echo "  --login     Step 5: tsh login (interactive)"
    echo "  --ssh       Step 6: Create SSH config"
    echo "  --verify    Step 7: Verify SSH + Ansible"
    echo "  -h, --help  Show this help"
    echo ""
    echo "Default: --all"
}

main() {
    local action="${1:---all}"

    check_container

    case "${action}" in
        --all)
            step3_create_user
            step4_create_role
            step5_tsh_login
            step6_ssh_config
            step7_verify
            ;;
        --user)
            step3_create_user
            ;;
        --role)
            step4_create_role
            ;;
        --login)
            step5_tsh_login
            ;;
        --ssh)
            step6_ssh_config
            ;;
        --verify)
            step7_verify
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: ${action}"
            usage
            exit 1
            ;;
    esac
}

main "$@"

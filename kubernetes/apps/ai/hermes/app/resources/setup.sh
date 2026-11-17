#!/bin/sh
# Runs in the `setup` init container before the gateway starts:
#
# 1. The image's config migration, which its own boot hook runs through
#    `s6-setuidgid hermes`; that needs CAP_SETGID and fails as non-root.
#    Skipped on first boot, when no config exists yet.
# 2. Creates the named profiles in HERMES_PROFILES that don't exist yet, then
#    points the default profile and those at LiteLLM. Hermes seeds a new
#    profile with Opus through OpenRouter, and providers and MCP servers have
#    to live in the profile itself, not in the managed overlay. The provider
#    and the MCP server are set on every start (Git wins); the model only
#    while the profile doesn't use LiteLLM yet, so a model picked in the
#    dashboard survives restarts.
# 3. Named profiles never read credentials from the pod's environment
#    (multiplexing keeps profiles apart), so they get the key from the
#    mounted Secret through a secrets.command.
# 4. Signal for HERMES_SIGNAL_PROFILE: the daemon URL and the numbers from the
#    hermes-signal Secret go into that profile's .env, never the pod's
#    environment, where the default profile would read them too.
#
# ${LITELLM_API_KEY} and $(cat ...) are written into the profiles literally,
# for Hermes to expand; this file isn't substituted by Flux.
set -eu
# Space-separated, set in the HelmRelease; empty means only the default profile
: "${HERMES_PROFILES:=}"
# Signal (step 4): the owning profile from the HelmRelease, the numbers from
# the optional hermes-signal Secret
: "${HERMES_SIGNAL_PROFILE:=}" "${SIGNAL_ACCOUNT:=}" "${SIGNAL_ALLOWED_USERS:=}" "${SIGNAL_HOME_CHANNEL:=}"

if [ -f /opt/data/config.yaml ]; then
  /opt/hermes/.venv/bin/python /opt/hermes/scripts/docker_config_migrate.py
fi

for profile in $HERMES_PROFILES; do
  if [ ! -d "/opt/data/profiles/$profile" ]; then
    hermes profile create "$profile" --no-alias >/dev/null 2>&1 || {
      echo "failed to create profile $profile"
      exit 1
    }
    echo "created profile $profile"
  fi
done

# hermes [-p <profile>] config set <key> <value>
set_key() {
  if [ "$profile" = default ]; then
    hermes config set "$1" "$2" >/dev/null 2>&1 || {
      echo "$profile: failed to set $1"
      exit 1
    }
  else
    hermes -p "$profile" config set "$1" "$2" >/dev/null 2>&1 || {
      echo "$profile: failed to set $1"
      exit 1
    }
  fi
  echo "$profile: set $1"
}

get_key() {
  if [ "$profile" = default ]; then
    hermes config get "$1" 2>/dev/null | tail -n 1
  else
    hermes -p "$profile" config get "$1" 2>/dev/null | tail -n 1
  fi
}

for profile in default $HERMES_PROFILES; do
  set_key providers.litellm.name LiteLLM
  set_key providers.litellm.api http://litellm.ai.svc.cluster.local:4000/v1
  set_key providers.litellm.key_env LITELLM_API_KEY
  set_key providers.litellm.discover_models true
  set_key mcp_servers.litellm.url http://litellm.ai.svc.cluster.local:4000/mcp/
  # LiteLLM lists the tools of every MCP server behind it; a cold list (after
  # a restart, with the hosted servers slow to answer) took 31 s, and at
  # Hermes' default of 30 s the gateway then started without any MCP tools
  set_key mcp_servers.litellm.connect_timeout 120
  # shellcheck disable=SC2016 # literal on purpose, Hermes expands it
  set_key mcp_servers.litellm.headers '{"x-litellm-api-key": "Bearer ${LITELLM_API_KEY}"}'
  if [ "$profile" != default ]; then
    set_key secrets.command.enabled true
    # shellcheck disable=SC2016 # literal on purpose, the helper runs it
    set_key secrets.command.command 'echo LITELLM_API_KEY=$(cat /mnt/secrets/litellm/api-key)'
  fi
  if [ "$(get_key model.provider)" != "custom:litellm" ]; then
    set_key model.provider custom:litellm
    set_key model.default chatgpt/gpt-6.1-sol
    set_key model.base_url http://litellm.ai.svc.cluster.local:4000/v1
    # maxInputTokens of the LiteLLM model; Hermes can't read it
    set_key model.context_length 272000
  fi
done

# Signal, for one profile only: a number can belong to one profile, and that
# profile's cron jobs deliver to its home channel. UPPER_SNAKE keys go to the
# profile's .env. Skipped until the hermes-signal Secret has the numbers
if [ -n "$HERMES_SIGNAL_PROFILE" ] && [ -n "$SIGNAL_ACCOUNT" ]; then
  profile=$HERMES_SIGNAL_PROFILE
  set_key SIGNAL_HTTP_URL http://signal-cli.ai.svc.cluster.local:8080
  set_key SIGNAL_ACCOUNT "$SIGNAL_ACCOUNT"
  set_key SIGNAL_ALLOWED_USERS "$SIGNAL_ALLOWED_USERS"
  set_key SIGNAL_HOME_CHANNEL "$SIGNAL_HOME_CHANNEL"
else
  echo "signal: skipped (no HERMES_SIGNAL_PROFILE or SIGNAL_ACCOUNT)"
fi

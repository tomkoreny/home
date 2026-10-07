# shellcheck shell=bash
# IPv4 failover onto the `home` WireGuard tunnel (see default.nix).
#
# default.nix wraps this file in a script that defines, ahead of it:
#   WG_INTERFACE    wg-quick interface name
#   PEER_V4         Yggdrasil peers given as IPv4 literals
#   PEER_HOSTS      Yggdrasil peers given as hostnames
#   RESTART_LABELS  launchd labels to `kickstart -k` after each route switch
#   TIMEOUT         coreutils timeout(1), to bound DNS lookups
#
# Every round it probes IPv4 bound to the physical uplink (IP_BOUND_IF via
# `nc -b`): a bound socket only sees routes of that interface, so the
# override routes below can never answer the probe. Two failed rounds in a
# row move IPv4 into the tunnel, three good rounds move it back. The override
# is 0/1 + 128/1 via the tunnel: they beat the physical default route without
# replacing it, so the uplink stays visible for probing and moving back.
#
# Only state changes are logged. /var/run/home-tunnel-failover.state lists
# the routes this daemon installed, so a restart removes exactly those.

set -u -o pipefail

ROUTE=/sbin/route
NETSTAT=/usr/sbin/netstat
NC=/usr/bin/nc
LAUNCHCTL=/bin/launchctl
DSCACHEUTIL=/usr/bin/dscacheutil
SLEEP=/bin/sleep
RM=/bin/rm

INTERVAL=5
FAILS_TO_ACTIVATE=2
OKS_TO_DEACTIVATE=3
PROBE_TARGETS=(1.1.1.1 8.8.8.8)
PROBE_PORT=443
PROBE_TIMEOUT=3
STATE_FILE=/var/run/home-tunnel-failover.state

ACTIVE=0 FAILS=0 OKS=0 STOP=0
UPLINK=unset
PHYS_IF= PHYS_GW= TUN_IF= PEER_SPEC=
# Installed by us: the utun carrying 0/1 + 128/1, the uplink's scoped default
# ("<ifname> <gateway>"), and peer IP -> pin spec ("gw <addr>", "if <ifname>"
# or "reject").
SPLIT_IF= SCOPED=
declare -A HOST_ROUTE=()
# Other programs' host pins we moved into the tunnel: IP -> original gateway.
declare -A MOVED=()
# Wanted while active: IPv4 addresses Yggdrasil may dial.
declare -A WANT_PEER=()
# Route table snapshot: interface of the 0/1 and 128/1 routes,
# "<gateway> <flags> <netif>" of host routes, and gateway of each
# interface-scoped default.
declare -A SPLIT_ON=() HOST_ON=() SCOPED_ON=()
# Problems already reported since the last state change.
declare -A WARNED=()

stamp() {
  printf '%(%Y-%m-%d %H:%M:%S)T %s\n' -1 "$*"
}

# State changes; they re-arm warnings.
log() {
  WARNED=()
  stamp "$*"
}

# Problems that persist across rounds are reported once, not every round.
warn() {
  [[ -n ${WARNED[$*]-} ]] && return
  WARNED[$*]=1
  stamp "$*"
}

# Snapshot of the IPv4 table. The physical uplink is the first default route
# that is not interface-scoped (I flag: per-interface duplicates, VPN
# scopes) and not a tunnel: pppd makes ppp0 the primary default whenever the
# Wi-Fi/hotspot default disappears, and probing through openfortivpn's own
# link would decide nothing. Columns are located from the header because
# their number differs between macOS releases. Protocol-cloned routes are not
# listed without -a, so host entries are static ones.
read_routes() {
  local -a f
  local i fi_flags= fi_netif= dest gw flags netif
  PHYS_IF= PHYS_GW=
  SPLIT_ON=() HOST_ON=() SCOPED_ON=()
  while read -r -a f; do
    ((${#f[@]} >= 3)) || continue
    if [[ ${f[0]} == Destination ]]; then
      for i in "${!f[@]}"; do
        case ${f[i]} in
        Flags) fi_flags=$i ;;
        Netif) fi_netif=$i ;;
        esac
      done
      continue
    fi
    [[ -n $fi_flags && -n $fi_netif ]] || continue
    dest=${f[0]} gw=${f[1]} flags=${f[fi_flags]-} netif=${f[fi_netif]-}
    if [[ $dest == default ]]; then
      if [[ $flags == *I* ]]; then
        SCOPED_ON[$netif]=$gw
      elif [[ -z $PHYS_IF && $netif != @(utun|ppp|ipsec|gif|stf)* ]]; then
        PHYS_IF=$netif PHYS_GW=$gw
      fi
    elif [[ $dest =~ ^(0|128)(\.0)*/1$ ]]; then
      SPLIT_ON[${BASH_REMATCH[1]}]=$netif
    elif [[ $flags == *H* ]]; then
      HOST_ON[${dest%/32}]="$gw $flags $netif"
    fi
  done < <("$NETSTAT" -rn -f inet 2>/dev/null)
}

# The utun behind wg-quick's interface, checked the way wg-quick does.
find_tunnel() {
  local name_file=/var/run/wireguard/$WG_INTERFACE.name name=
  TUN_IF=
  [[ -r $name_file ]] || return 0
  read -r name <"$name_file" || [[ -n $name ]] || return 0
  [[ $name == utun* && -S /var/run/wireguard/$name.sock ]] && TUN_IF=$name
  return 0
}

probe() {
  local target
  [[ -n $PHYS_IF ]] || return 1
  for target in "${PROBE_TARGETS[@]}"; do
    "$NC" -z -n -G "$PROBE_TIMEOUT" -b "$PHYS_IF" "$target" "$PROBE_PORT" \
      >/dev/null 2>&1 && return 0
  done
  return 1
}

# IPv4 literal peers plus the current A records of hostname peers, from the
# system resolver Yggdrasil uses too.
resolve_peers() {
  local ip host line
  WANT_PEER=()
  for ip in "${PEER_V4[@]}"; do
    WANT_PEER[$ip]=1
  done
  for host in "${PEER_HOSTS[@]}"; do
    while read -r line; do
      [[ $line =~ ^ip_address:[[:space:]]*([0-9.]+) ]] && WANT_PEER[${BASH_REMATCH[1]}]=1
    done < <("$TIMEOUT" 5 "$DSCACHEUTIL" -q host -a name "$host" 2>/dev/null)
  done
}

# Where peer links must go: via the physical gateway (or straight out of a
# gateway-less uplink), or, with no physical IPv4 at all, into a reject route
# so the dial fails at once instead of entering the tunnel (wg-quick
# blackholes its endpoint for the same reason).
set_peer_spec() {
  if [[ -z $PHYS_IF ]]; then
    PEER_SPEC=reject
  elif [[ $PHYS_GW == link#* ]]; then
    PEER_SPEC="if $PHYS_IF"
  else
    PEER_SPEC="gw $PHYS_GW"
  fi
}

host_present() {
  local entry=${HOST_ON[$1]-} gw flags netif
  [[ -n $entry ]] || return 1
  read -r gw flags netif <<<"$entry"
  case $2 in
  reject) [[ $flags == *R* ]] ;;
  "if "*) [[ $netif == "${2#if }" ]] ;;
  *) [[ $gw == "${2#gw }" ]] ;;
  esac
}

add_host() {
  local ip=$1 spec=$2 out
  local -a target
  case $spec in
  reject) target=(127.0.0.1 -reject) ;;
  "if "*) target=(-interface "${spec#if }") ;;
  *) target=("${spec#gw }") ;;
  esac
  if out=$("$ROUTE" -n add -inet -host "$ip" "${target[@]}" 2>&1); then
    HOST_ROUTE[$ip]=$spec
  else
    warn "pinning Yggdrasil peer $ip ($spec) failed: $out"
    return 1
  fi
}

# Deletes the pin only if the table still holds the route we added.
del_host() {
  local ip=$1
  if host_present "$ip" "${HOST_ROUTE[$ip]-}"; then
    "$ROUTE" -n delete -inet -host "$ip" >/dev/null 2>&1
  fi
  unset 'HOST_ROUTE[$ip]'
}

split_present() {
  [[ ${SPLIT_ON[0]-} == "$1" && ${SPLIT_ON[128]-} == "$1" ]]
}

add_split() {
  local half out
  local -a added=()
  for half in 0 128; do
    if out=$("$ROUTE" -n add -inet -net "$half.0.0.0/1" -interface "$1" 2>&1); then
      added+=("$half")
    else
      warn "routing $half.0.0.0/1 into $1 failed: $out"
      for half in "${added[@]}"; do
        "$ROUTE" -n delete -inet -net "$half.0.0.0/1" >/dev/null 2>&1
      done
      return 1
    fi
  done
}

# Deletes the halves that still point at the utun we installed them on.
del_split() {
  local half
  for half in 0 128; do
    if [[ ${SPLIT_ON[$half]-} == "$SPLIT_IF" ]]; then
      "$ROUTE" -n delete -inet -net "$half.0.0.0/1" >/dev/null 2>&1
    fi
  done
  SPLIT_IF=
}

# A socket bound to the primary interface resolves through the unscoped
# table, where 0/1 and 128/1 now point at the utun, so a bound probe fails
# with "Network is unreachable" and the tunnel could never be left again.
# macOS gives only non-primary interfaces a scoped default; while the
# tunnel holds IPv4, the uplink gets one from us so the probe keeps testing
# the real local path.
add_scoped() {
  local out
  [[ -n $PHYS_IF && -z ${SCOPED_ON[$PHYS_IF]-} ]] || return 1
  if [[ $PHYS_GW == link#* ]]; then
    out=$("$ROUTE" -n add -inet default -interface "$PHYS_IF" -ifscope "$PHYS_IF" 2>&1)
  else
    out=$("$ROUTE" -n add -inet default "$PHYS_GW" -ifscope "$PHYS_IF" 2>&1)
  fi || {
    warn "scoped default via $PHYS_IF failed: $out"
    return 1
  }
  SCOPED="$PHYS_IF $PHYS_GW"
}

# Deletes our scoped default only while the table still holds that route.
del_scoped() {
  local netif=${SCOPED%% *} gw=${SCOPED#* }
  if [[ -n $SCOPED && ${SCOPED_ON[$netif]-} == "$gw" ]]; then
    "$ROUTE" -n delete -inet default -ifscope "$netif" >/dev/null 2>&1
  fi
  SCOPED=
}

# VPN clients pin their server with a static /32 via the physical gateway.
# openfortivpn always takes the primary default for it (its route lookup
# locks onto the first matching interface, so the more specific 0/1 and
# 128/1 never win), and that pin leads into the dead local path. While IPv4
# goes home, such foreign pins move into the tunnel; switching back returns
# them to the uplink. A client that deletes and re-adds its pin (every
# openfortivpn session) is caught again on the next round.
move_pins() {
  local ip gw flags netif tun_addr moved=1
  local -a target
  [[ -n $SPLIT_IF && -n $PHYS_IF ]] || return 1
  # Gateway form via the tunnel's own address: the Forti gateway is also
  # ppp0's point-to-point peer, so an `-interface` route to it attaches to
  # ppp0 instead of the utun.
  tun_addr=$(/sbin/ifconfig "$SPLIT_IF" 2>/dev/null | /usr/bin/awk '$1 == "inet" {print $2; exit}')
  if [[ -n $tun_addr ]]; then
    target=("$tun_addr")
  else
    target=(-interface "$SPLIT_IF")
  fi
  for ip in "${!HOST_ON[@]}"; do
    [[ -n ${HOST_ROUTE[$ip]-} || -n ${WANT_PEER[$ip]-} ]] && continue
    read -r gw flags netif <<<"${HOST_ON[$ip]}"
    [[ $netif == "$PHYS_IF" && $flags == *G* && $flags == *S* ]] || continue
    # Delete and re-add: `route change` keeps the old interface on the
    # entry. In between, the /1 halves already carry the address home.
    "$ROUTE" -n delete -inet -host "$ip" >/dev/null 2>&1
    if "$ROUTE" -n add -inet -host "$ip" "${target[@]}" >/dev/null 2>&1; then
      MOVED[$ip]=$gw
      log "moved the $ip pin (via $gw) into $WG_INTERFACE"
      moved=0
    else
      warn "moving the $ip pin into $WG_INTERFACE failed"
    fi
  done
  return $moved
}

# Returns moved pins that are still in the tunnel to the uplink (or to their
# old gateway when there is no uplink); pins their owner removed are just
# forgotten.
restore_pins() {
  local ip gw flags netif
  for ip in "${!MOVED[@]}"; do
    read -r gw flags netif <<<"${HOST_ON[$ip]-}"
    if [[ $netif == utun* ]]; then
      "$ROUTE" -n delete -inet -host "$ip" >/dev/null 2>&1
      "$ROUTE" -n add -inet -host "$ip" "${PHYS_GW:-${MOVED[$ip]}}" >/dev/null 2>&1 ||
        warn "returning the $ip pin to ${PHYS_GW:-${MOVED[$ip]}} failed"
    fi
    unset 'MOVED[$ip]'
  done
}

save_state() {
  local ip
  if [[ -z $SPLIT_IF && -z $SCOPED && ${#HOST_ROUTE[@]} -eq 0 && ${#MOVED[@]} -eq 0 ]]; then
    "$RM" -f "$STATE_FILE"
    return
  fi
  {
    if [[ -n $SPLIT_IF ]]; then
      printf 'split %s\n' "$SPLIT_IF"
    fi
    if [[ -n $SCOPED ]]; then
      printf 'scoped %s\n' "$SCOPED"
    fi
    for ip in "${!HOST_ROUTE[@]}"; do
      printf 'host %s %s\n' "$ip" "${HOST_ROUTE[$ip]}"
    done
    for ip in "${!MOVED[@]}"; do
      printf 'moved %s %s\n' "$ip" "${MOVED[$ip]}"
    done
  } >"$STATE_FILE"
}

load_state() {
  local kind key spec
  [[ -r $STATE_FILE ]] || return 0
  while read -r kind key spec; do
    case $kind in
    split) SPLIT_IF=$key ;;
    scoped) SCOPED="$key $spec" ;;
    host) HOST_ROUTE[$key]=$spec ;;
    moved) MOVED[$key]=$spec ;;
    esac
  done <"$STATE_FILE"
}

# Services that pinned a route to the previous IPv4 path re-resolve it. Stop
# them with SIGTERM and wait, so they remove their own routes: `kickstart -k`
# killed openfortivpn before its cleanup, and its next session then reused the
# stale /32 pin to its gateway on the dead path. KeepAlive only restarts
# failed exits, so start the service again once it is gone.
kickstart() {
  local label out pid i
  for label in "${RESTART_LABELS[@]}"; do
    pid=$("$LAUNCHCTL" print "system/$label" 2>/dev/null | /usr/bin/awk '$1 == "pid" {print $3; exit}')
    if [[ -n $pid ]]; then
      "$LAUNCHCTL" kill TERM "system/$label" >/dev/null 2>&1
      for ((i = 0; i < 20; i++)); do
        /bin/kill -0 "$pid" 2>/dev/null || break
        "$SLEEP" 1
      done
      if /bin/kill -0 "$pid" 2>/dev/null; then
        log "$label ignored SIGTERM for 20s; killing it"
        out=$("$LAUNCHCTL" kickstart -k "system/$label" 2>&1) ||
          log "restarting $label failed: $out"
        continue
      fi
    fi
    out=$("$LAUNCHCTL" kickstart "system/$label" 2>&1) ||
      log "starting $label failed: $out"
  done
}

# Makes the installed routes match ACTIVE. Peer pins go in before the tunnel
# takes IPv4 and come out after it lets go.
reconcile() {
  local ip spec pinned changed=0 switched=0

  if ((ACTIVE)); then
    set_peer_spec
    for ip in "${!HOST_ROUTE[@]}"; do
      [[ -n ${WANT_PEER[$ip]-} ]] && continue
      del_host "$ip"
      changed=1
    done
    for ip in "${!WANT_PEER[@]}"; do
      spec=${HOST_ROUTE[$ip]-}
      if [[ $spec == "$PEER_SPEC" ]] && host_present "$ip" "$spec"; then
        continue
      fi
      if [[ -n $spec ]]; then
        del_host "$ip"
        changed=1
      fi
      add_host "$ip" "$PEER_SPEC" && changed=1
    done

    # The routes vanish with their utun when wg-quick restarts; reinstall
    # them on whichever utun it has now.
    if [[ -n $SPLIT_IF ]] && ! { [[ $SPLIT_IF == "$TUN_IF" ]] && split_present "$SPLIT_IF"; }; then
      del_split
      changed=1
    fi
    if [[ -z $SPLIT_IF ]]; then
      if [[ -z $TUN_IF ]]; then
        warn "IPv4 should use the tunnel, but wg-quick $WG_INTERFACE has no interface"
      elif add_split "$TUN_IF"; then
        SPLIT_IF=$TUN_IF
        changed=1 switched=1
        pinned="${!HOST_ROUTE[*]}"
        log "IPv4 now goes through $WG_INTERFACE ($TUN_IF); Yggdrasil peers kept outside: ${pinned:-none}"
      fi
    fi

    # Keep the bound probe answerable on the current uplink (see add_scoped);
    # reinstall it after an uplink change or if something removed it.
    if [[ -n $SCOPED ]] && [[ $SCOPED != "$PHYS_IF $PHYS_GW" || ${SCOPED_ON[$PHYS_IF]-} != "$PHYS_GW" ]]; then
      del_scoped
      changed=1
    fi
    [[ -z $SCOPED ]] && add_scoped && changed=1
    move_pins && changed=1
  else
    if ((${#MOVED[@]})); then
      restore_pins
      changed=1
    fi
    if [[ -n $SPLIT_IF ]]; then
      del_split
      changed=1 switched=1
      log "IPv4 is back on ${PHYS_IF:-the local network}"
    fi
    if [[ -n $SCOPED ]]; then
      del_scoped
      changed=1
    fi
    for ip in "${!HOST_ROUTE[@]}"; do
      del_host "$ip"
      changed=1
    done
  fi

  ((changed)) && save_state
  ((switched)) && kickstart
  return 0
}

# Removes everything recorded as installed, on start (leftovers of a killed
# run) and on stop (nothing should keep steering IPv4 once nobody watches).
teardown() {
  read_routes
  ACTIVE=0
  reconcile
  "$RM" -f "$STATE_FILE"
}

# Signals only raise a flag: a handler running teardown in the middle of
# reconcile could miss a route installed but not yet recorded.
trap 'STOP=1' TERM INT HUP

load_state
if [[ -n $SPLIT_IF || -n $SCOPED || ${#HOST_ROUTE[@]} -gt 0 || ${#MOVED[@]} -gt 0 ]]; then
  log "removing routes left by a previous run"
  teardown
fi
log "started; probing ${PROBE_TARGETS[*]} port $PROBE_PORT every ${INTERVAL}s"

while ((!STOP)); do
  read_routes
  find_tunnel

  if [[ "$PHYS_IF $PHYS_GW" != "$UPLINK" ]]; then
    UPLINK="$PHYS_IF $PHYS_GW"
    if [[ -n $PHYS_IF ]]; then
      log "uplink is $PHYS_IF via $PHYS_GW"
    else
      log "no physical IPv4 default route"
    fi
    # A new network can resolve the hostname peers differently.
    ((ACTIVE)) && resolve_peers
  fi

  if probe; then
    FAILS=0 OKS=$((OKS + 1))
  else
    OKS=0 FAILS=$((FAILS + 1))
  fi
  ((STOP)) && break

  if ((!ACTIVE && FAILS >= FAILS_TO_ACTIVATE)); then
    ACTIVE=1
    log "IPv4 probes via ${PHYS_IF:-no uplink} failed $FAILS times in a row; switching to the tunnel"
    resolve_peers
  elif ((ACTIVE && OKS >= OKS_TO_DEACTIVATE)); then
    ACTIVE=0
    log "IPv4 probes via $PHYS_IF succeeded $OKS times in a row; switching back"
  fi

  reconcile

  # Backgrounded so a signal ends the wait at once instead of after it.
  ((STOP)) || {
    "$SLEEP" "$INTERVAL" &
    wait $!
  }
done

log "stopping"
teardown
exit 0

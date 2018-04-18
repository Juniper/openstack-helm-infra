# Generated by confd
include "bird6_aggr.cfg";
include "custom_filters6.cfg";
include "bird6_ipam.cfg";
{{`{{$node_ip_key := printf "/host/%s/ip_addr_v4" (getenv "NODENAME")}}`}}{{`{{$node_ip := getv $node_ip_key}}`}}
{{`{{$node_ip6_key := printf "/host/%s/ip_addr_v6" (getenv "NODENAME")}}`}}{{`{{$node_ip6 := getv $node_ip6_key}}`}}

router id {{`{{$node_ip}}`}};  # Use IPv4 address since router id is 4 octets, even in MP-BGP

{{`{{define "LOGGING"}}`}}
{{`{{$node_logging_key := printf "/host/%s/loglevel" (getenv "NODENAME")}}`}}{{`{{if exists $node_logging_key}}`}}{{`{{$logging := getv $node_logging_key}}`}}
{{`{{if eq $logging "debug"}}`}}  debug all;{{`{{else if ne $logging "none"}}`}}  debug { states };{{`{{end}}`}}
{{`{{else if exists "/global/loglevel"}}`}}{{`{{$logging := getv "/global/loglevel"}}`}}
{{`{{if eq $logging "debug"}}`}}  debug all;{{`{{else if ne $logging "none"}}`}}  debug { states };{{`{{end}}`}}
{{`{{else}}`}}  debug { states };{{`{{end}}`}}
{{`{{end}}`}}

# Configure synchronization between routing tables and kernel.
protocol kernel {
  learn;             # Learn all alien routes from the kernel
  persist;           # Don't remove routes on bird shutdown
  scan time 2;       # Scan kernel routing table every 2 seconds
  import all;
  export all;        # Default is export none
  graceful restart;  # Turn on graceful restart to reduce potential flaps in
                     # routes when reloading BIRD configuration.  With a full
                     # automatic mesh, there is no way to prevent BGP from
                     # flapping since multiple nodes update their BGP
                     # configuration at the same time, GR is not guaranteed to
                     # work correctly in this scenario.
}

# Watch interface up/down events.
protocol device {
  {{`{{template "LOGGING"}}`}}
  scan time 2;    # Scan interfaces every 2 seconds
}

protocol direct {
  {{`{{template "LOGGING"}}`}}
  interface -"cali*", "*"; # Exclude cali* but include everything else.
}

{{`{{if eq "" ($node_ip6)}}`}}# IPv6 disabled on this node.
{{`{{else}}`}}{{`{{$node_as_key := printf "/host/%s/as_num" (getenv "NODENAME")}}`}}

# ensure we only listen to a specific ip and address
listen bgp address {{`{{$node_ip6}}`}} port {{.Values.networking.bgp.ipv6.mesh.port.listen}};

# Template for all BGP clients
template bgp bgp_template {
  {{`{{template "LOGGING"}}`}}
  description "Connection to BGP peer";
  local as {{`{{if exists $node_as_key}}`}}{{`{{getv $node_as_key}}`}}{{`{{else}}`}}{{`{{getv "/global/as_num"}}`}}{{`{{end}}`}};
  multihop;
  gateway recursive; # This should be the default, but just in case.
  import all;        # Import all routes, since we don't know what the upstream
                     # topology is and therefore have to trust the ToR/RR.
  export filter calico_pools;  # Only want to export routes for workloads.
  next hop self;     # Disable next hop processing and always advertise our
                     # local address as nexthop
  source address {{`{{$node_ip6}}`}};  # The local address we use for the TCP connection
  add paths on;
  graceful restart;  # See comment in kernel section about graceful restart.
}

# ------------- Node-to-node mesh -------------
{{`{{if (json (getv "/global/node_mesh")).enabled}}`}}
{{`{{range $host := lsdir "/host"}}`}}
{{`{{$onode_as_key := printf "/host/%s/as_num" .}}`}}
{{`{{$onode_ip_key := printf "/host/%s/ip_addr_v6" .}}`}}{{`{{if exists $onode_ip_key}}`}}{{`{{$onode_ip := getv $onode_ip_key}}`}}
{{`{{$nums := split $onode_ip ":"}}`}}{{`{{$id := join $nums "_"}}`}}
# For peer {{`{{$onode_ip_key}}`}}
{{`{{if eq $onode_ip ($node_ip6) }}`}}# Skipping ourselves ({{`{{$node_ip6}}`}})
{{`{{else if eq "" $onode_ip}}`}}# No IPv6 address configured for this node
{{`{{else}}`}}protocol bgp Mesh_{{`{{$id}}`}} from bgp_template {
  neighbor {{`{{$onode_ip}}`}} as {{`{{if exists $onode_as_key}}`}}{{`{{getv $onode_as_key}}`}}{{`{{else}}`}}{{`{{getv "/global/as_num"}}`}}{{`{{end}}`}};
  neighbor port {{.Values.networking.bgp.ipv6.mesh.port.neighbor}};
}{{`{{end}}`}}{{`{{end}}`}}{{`{{end}}`}}
{{`{{else}}`}}
# Node-to-node mesh disabled
{{`{{end}}`}}


# ------------- Global peers -------------
{{`{{if ls "/global/peer_v6"}}`}}
{{`{{range gets "/global/peer_v6/*"}}`}}{{`{{$data := json .Value}}`}}
{{`{{$nums := split $data.ip ":"}}`}}{{`{{$id := join $nums "_"}}`}}
# For peer {{`{{.Key}}`}}
protocol bgp Global_{{`{{$id}}`}} from bgp_template {
  neighbor {{`{{$data.ip}}`}} as {{`{{$data.as_num}}`}};
  neighbor port {{.Values.networking.bgp.ipv6.mesh.port.neighbor}};
}
{{`{{end}}`}}
{{`{{else}}`}}# No global peers configured.{{`{{end}}`}}


# ------------- Node-specific peers -------------
{{`{{$node_peers_key := printf "/host/%s/peer_v6" (getenv "NODENAME")}}`}}
{{`{{if ls $node_peers_key}}`}}
{{`{{range gets (printf "%s/*" $node_peers_key)}}`}}{{`{{$data := json .Value}}`}}
{{`{{$nums := split $data.ip ":"}}`}}{{`{{$id := join $nums "_"}}`}}
# For peer {{`{{.Key}}`}}
protocol bgp Node_{{`{{$id}}`}} from bgp_template {
  neighbor {{`{{$data.ip}}`}} as {{`{{$data.as_num}}`}};
  neighbor port {{.Values.networking.bgp.ipv6.mesh.port.neighbor}};
}
{{`{{end}}`}}
{{`{{else}}`}}# No node-specific peers configured.{{`{{end}}`}}
{{`{{end}}`}}

#![allow(dead_code)]
mod account;
mod config;
mod consts;
mod dns;
mod error;
mod masque;
mod masque_h2;
mod netstack;
mod noize;
mod prober;
mod quic;
mod socks;
mod tls;
mod aethernoize;
mod wireguard;
mod wg_prober;

use std::net::{IpAddr, SocketAddr};

use error::{AetherError, Result};

const TUNNEL_MTU: usize = 1280;
const INNER_MTU: usize = 1200;
const DEFAULT_CONFIG: &str = "aether.toml";

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .format_timestamp_millis()
        .init();

    install_netstack_panic_guard();

    let listen: SocketAddr = std::env::var("AETHER_SOCKS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or_else(|| "127.0.0.1:1819".parse().unwrap());

    let base_config = std::env::var("AETHER_CONFIG").unwrap_or_else(|_| DEFAULT_CONFIG.to_string());

    let protocol = if std::env::var("AETHER_PEER").is_ok() || std::env::var("AETHER_WG_PEER").is_ok() {
        match std::env::var("AETHER_PROTOCOL") {
            Ok(v) => Protocol::parse(&v),
            Err(_) => Protocol::Masque,
        }
    } else {
        select_protocol().await
    };

    match protocol {
        Protocol::Masque => {
            let config_path = masque_config_path(&base_config);
            let identity = load_or_provision_masque(&config_path).await?;
            log::info!(
                "[+] identity ready: device={} ipv4={} ipv6={}",
                identity.device_id,
                identity.ipv4,
                identity.ipv6
            );
            let peer = select_peer(&identity, protocol).await?;
            log::info!("[+] using cloudflare edge {peer}");
            let ech = resolve_ech().await;
            run_masque_tunnel(identity, peer, ech, listen).await
        }
        Protocol::WireGuard => {
            let config_path = warp_config_path(&base_config);
            let identity = load_or_provision_warp(&config_path).await?;
            log::info!(
                "[+] identity ready: device={} ipv4={} ipv6={}",
                identity.device_id,
                identity.ipv4,
                identity.ipv6
            );
            run_wireguard(identity, listen).await
        }
        Protocol::WarpInWarp => {
            let primary_path = warp_config_path(&base_config);
            let secondary_path = derive_sibling_path(&primary_path, "secondary");
            let primary = load_or_provision_warp(&primary_path).await?;
            let secondary = load_or_provision_warp(&secondary_path).await?;
            log::info!(
                "[+] outer device={} ipv4={} | inner device={} ipv4={}",
                primary.device_id, primary.ipv4, secondary.device_id, secondary.ipv4
            );
            let peer = select_peer(&primary, Protocol::WireGuard).await?;
            log::info!("[+] using cloudflare edge {peer} (outer)");
            run_warp_in_warp(primary, secondary, peer, listen).await
        }
    }
}

fn install_netstack_panic_guard() {
    let default_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let from_netstack = info
            .location()
            .map(|l| l.file().contains("smoltcp"))
            .unwrap_or(false);
        if from_netstack {
            log::debug!("[netstack] recovered from a malformed segment: {info}");
        } else {
            default_hook(info);
        }
    }));
}

fn noize_config() -> noize::NoizeConfig {
    let profile = std::env::var("AETHER_NOIZE").unwrap_or_else(|_| "firewall".to_string());
    log::info!("[+] obfuscation profile: {profile}");
    noize::from_profile(&profile)
}

fn aethernoize_config() -> aethernoize::AetherNoizeConfig {
    let profile = std::env::var("AETHER_NOIZE").unwrap_or_else(|_| "balanced".to_string());
    log::info!("[+] aethernoize profile: {profile}");
    aethernoize::from_profile(&profile)
}

fn warp_config_path(base: &str) -> String {
    if let Ok(p) = std::env::var("AETHER_WG_CONFIG") {
        return p;
    }
    base.to_string()
}

fn masque_config_path(base: &str) -> String {
    if let Ok(p) = std::env::var("AETHER_MASQUE_CONFIG") {
        return p;
    }
    derive_sibling_path(base, "masque")
}

fn derive_sibling_path(base: &str, suffix: &str) -> String {
    let dir_end = base.rfind(|c| c == '/' || c == '\\').map(|i| i + 1).unwrap_or(0);
    match base[dir_end..].rfind('.') {
        Some(rel) => {
            let dot = dir_end + rel;
            format!("{}-{}{}", &base[..dot], suffix, &base[dot..])
        }
        None => format!("{base}-{suffix}"),
    }
}

async fn load_or_provision_warp(config_path: &str) -> Result<account::Identity> {
    if let Some(identity) = config::load(config_path)? {
        log::info!("[+] loaded existing warp identity from {config_path}");
        return Ok(identity);
    }

    log::info!("[+] no warp identity found; provisioning dedicated wireguard account");
    let identity = account::provision_wg(consts::DEFAULT_MODEL, consts::DEFAULT_LOCALE, None).await?;
    config::save(config_path, &identity)?;
    log::info!("[+] provisioned and saved new warp identity to {config_path}");
    Ok(identity)
}

async fn load_or_provision_masque(config_path: &str) -> Result<account::Identity> {
    if let Some(identity) = config::load(config_path)? {
        log::info!("[+] loaded existing masque identity from {config_path}");
        if identity.has_masque_credentials() {
            return Ok(identity);
        }
        log::info!("[+] masque identity missing credentials; enrolling masque key");
        let (cert_pem, key_pem) = account::ensure_masque_enrolled(&identity).await?;
        let identity = account::Identity { cert_pem, key_pem, ..identity };
        config::save(config_path, &identity)?;
        return Ok(identity);
    }

    log::info!("[+] no masque identity found; provisioning dedicated masque account");
    let identity = account::provision_wg(consts::DEFAULT_MODEL, consts::DEFAULT_LOCALE, None).await?;
    let (cert_pem, key_pem) = account::ensure_masque_enrolled(&identity).await?;
    let identity = account::Identity { cert_pem, key_pem, ..identity };
    config::save(config_path, &identity)?;
    log::info!("[+] provisioned and saved new masque identity to {config_path}");
    Ok(identity)
}

async fn select_peer(identity: &account::Identity, protocol: Protocol) -> Result<SocketAddr> {
    let force_peer = match protocol {
        Protocol::Masque => std::env::var("AETHER_PEER").ok(),
        Protocol::WireGuard | Protocol::WarpInWarp => std::env::var("AETHER_WG_PEER")
            .ok()
            .or_else(|| std::env::var("AETHER_PEER").ok()),
    };
    
    if let Some(p) = force_peer {
        let peer: SocketAddr = p
            .parse()
            .map_err(|_| AetherError::Other(format!("bad peer address {p}")))?;
        log::info!("[+] using forced peer {peer} (probe skipped)");
        return Ok(peer);
    }

    log::info!("[+] selected protocol: {}", protocol.label());
    
    let mode_str = select_scan_mode_str().await;
    let ip = select_ip_version().await;

    match protocol {
        Protocol::Masque => {
            log::info!("[*] hunting for a working MASQUE gateway (deep connect-ip verification)");
            let mode = prober::ScanMode::parse(&mode_str);
            let probe = prober::MasqueProbe {
                sni: consts::CONNECT_SNI.to_string(),
                authority: quic::default_authority().to_string(),
                path: quic::default_path().to_string(),
                cert_pem: std::sync::Arc::from(identity.cert_pem.clone()),
                key_pem: std::sync::Arc::from(identity.key_pem.clone()),
                ech_config_list: None,
                noize: noize_config(),
                ports: prober::MASQUE_PORTS.to_vec(),
                ip,
            };

            let best = prober::hunt_best_gateway(&probe, mode).await?;
            log::info!("[+] selected MASQUE gateway {}:{} (rtt {:?})", best.ip, best.port, best.rtt);
            Ok(SocketAddr::new(best.ip, best.port))
        }
        Protocol::WireGuard | Protocol::WarpInWarp => {
            log::info!("[*] hunting for a working WireGuard endpoint (handshake + data-plane verification)");
            let mode = wg_prober::WgScanMode::parse(&mode_str);
            
            let private_key = identity.private_key_bytes()?;
            let peer_public = identity.peer_public_key_bytes()?;
            
            let probe = wg_prober::WgProbe {
                private_key: std::sync::Arc::new(private_key),
                peer_public_key: std::sync::Arc::new(peer_public),
                client_id: identity.client_id.clone(),
                local_ipv4: identity.ipv4.parse().map_err(|_| AetherError::Other("invalid ipv4".into()))?,
                aethernoize: aethernoize_config(),
                ports: wireguard::WG_PORTS.to_vec(),
                ip,
            };

            let best = wg_prober::hunt_best_wg_endpoint(&probe, mode).await?;
            log::info!("[+] selected WireGuard endpoint {}:{} (rtt {:?})", best.ip, best.port, best.rtt);
            Ok(SocketAddr::new(best.ip, best.port))
        }
    }
}

async fn resolve_ech() -> Option<Vec<u8>> {
    match std::env::var("AETHER_ECH") {
        Ok(v) if v.eq_ignore_ascii_case("auto") => match dns::fetch_ech_config().await {
            Ok(raw) => {
                log::info!("[+] fetched ECHConfigList automatically ({} bytes)", raw.len());
                Some(raw)
            }
            Err(e) => {
                log::warn!("[-] ECH auto-fetch failed ({e}); continuing without ECH");
                None
            }
        },
        Ok(b64) if !b64.is_empty() => match tls::decode_ech_config_list(&b64) {
            Ok(v) => {
                log::info!("[+] using ECHConfigList from AETHER_ECH");
                Some(v)
            }
            Err(e) => {
                log::warn!("[-] bad AETHER_ECH: {e}; continuing without ECH");
                None
            }
        },
        _ => {
            log::info!("[+] ECH disabled (warp masque endpoint does not accept ECH); SNI sent in cleartext");
            None
        }
    }
}

async fn run_masque_tunnel(
    identity: account::Identity,
    peer: SocketAddr,
    ech: Option<Vec<u8>>,
    listen: SocketAddr,
) -> Result<()> {
    let (chans, internals) = quic::channels();

    let cfg = quic::TunnelConfig {
        peer,
        sni: consts::CONNECT_SNI.to_string(),
        authority: quic::default_authority().to_string(),
        path: quic::default_path().to_string(),
        cert_pem: identity.cert_pem.clone(),
        key_pem: identity.key_pem.clone(),
        ech_config_list: ech,
        noize: noize_config(),
    };

    let quic::Channels {
        outbound_tx,
        inbound_rx,
        ctrl_tx,
    } = chans;

    let stack =
        netstack::spawn(&identity.ipv4, &identity.ipv6, TUNNEL_MTU, inbound_rx, outbound_tx)?;
    let _ctrl = ctrl_tx;

    let (addr_tx, mut addr_rx) = tokio::sync::mpsc::channel::<quic::AssignedAddr>(8);
    let bridge_stack = stack.clone();
    tokio::spawn(async move {
        while let Some(a) = addr_rx.recv().await {
            let res = match a.ip {
                IpAddr::V4(v4) => bridge_stack.set_addrs(Some((v4, a.prefix)), None).await,
                IpAddr::V6(v6) => bridge_stack.set_addrs(None, Some((v6, a.prefix))).await,
            };
            if let Err(e) = res {
                log::warn!("[-] failed to sync edge address into netstack: {e}");
            }
        }
    });

    let socks_stack = stack.clone();
    let socks_task = tokio::spawn(async move {
        log::info!("[+] socks5 server listening on {listen}");
        socks::serve(listen, socks_stack).await
    });

    let tunnel_result = if masque_h2::enabled() {
        let h2cfg = masque_h2::H2TunnelConfig {
            peer: masque_h2::h2_peer(peer),
            sni: consts::CONNECT_SNI.to_string(),
            authority: quic::default_authority().to_string(),
            path: quic::default_path().to_string(),
            cert_pem: identity.cert_pem.clone(),
            key_pem: identity.key_pem.clone(),
        };
        log::info!("[+] MASQUE transport: HTTP/2 (TCP) to {}", h2cfg.peer);
        let _ = &cfg;
        masque_h2::run(h2cfg, internals, Some(addr_tx)).await
    } else {
        log::info!("[+] MASQUE transport: HTTP/3 (QUIC) to {}", peer);
        quic::run(cfg, internals, Some(addr_tx)).await
    };
    socks_task.abort();

    match tunnel_result {
        Ok(()) => Ok(()),
        Err(e) => Err(AetherError::Other(format!("tunnel exited: {e}"))),
    }
}

fn wg_keepalive_secs() -> u16 {
    std::env::var("AETHER_WG_KEEPALIVE")
        .ok()
        .and_then(|v| v.parse().ok())
        .filter(|&v| v > 0)
        .unwrap_or(5)
}

fn wg_profile_candidates() -> Vec<(String, aethernoize::AetherNoizeConfig)> {
    let primary = std::env::var("AETHER_NOIZE").unwrap_or_else(|_| "balanced".to_string());
    log::info!("[+] aethernoize primary profile: {primary}");

    let mut names = vec![primary.clone()];
    if std::env::var("AETHER_WG_NO_PROFILE_RETRY").is_err() {
        for fallback in ["balanced", "aggressive", "light", "off"] {
            if !names.iter().any(|n| n.eq_ignore_ascii_case(fallback)) {
                names.push(fallback.to_string());
            }
        }
    }

    names
        .into_iter()
        .map(|n| {
            let cfg = aethernoize::from_profile(&n);
            (n, cfg)
        })
        .collect()
}

async fn hunt_wg_peer_with_profile(
    identity: &account::Identity,
    mode_str: &str,
    ip: prober::IpScan,
    profile: aethernoize::AetherNoizeConfig,
) -> Result<SocketAddr> {
    let mode = wg_prober::WgScanMode::parse(mode_str);
    let private_key = identity.private_key_bytes()?;
    let peer_public = identity.peer_public_key_bytes()?;

    let probe = wg_prober::WgProbe {
        private_key: std::sync::Arc::new(private_key),
        peer_public_key: std::sync::Arc::new(peer_public),
        client_id: identity.client_id,
        local_ipv4: identity
            .ipv4
            .parse()
            .map_err(|_| AetherError::Other("invalid ipv4".into()))?,
        aethernoize: profile,
        ports: wireguard::WG_PORTS.to_vec(),
        ip,
    };

    let best = wg_prober::hunt_best_wg_endpoint(&probe, mode).await?;
    Ok(SocketAddr::new(best.ip, best.port))
}

async fn run_wireguard(identity: account::Identity, listen: SocketAddr) -> Result<()> {
    let candidates = wg_profile_candidates();
    let multi = candidates.len() > 1;

    let forced = std::env::var("AETHER_WG_PEER")
        .ok()
        .or_else(|| std::env::var("AETHER_PEER").ok());

    let private_key = identity.private_key_bytes()?;
    let peer_public = identity.peer_public_key_bytes()?;
    let ipv4: std::net::Ipv4Addr = identity
        .ipv4
        .parse()
        .map_err(|_| AetherError::Other("invalid ipv4".into()))?;

    let selected: Option<(SocketAddr, aethernoize::AetherNoizeConfig)> = if let Some(p) = forced {
        let peer: SocketAddr = p
            .parse()
            .map_err(|_| AetherError::Other(format!("bad peer address {p}")))?;
        log::info!("[+] using forced peer {peer} (probe skipped)");

        let mut chosen = None;
        for (name, profile) in &candidates {
            log::info!("[*] testing forced peer {peer} with aethernoize profile '{name}'");
            match wireguard::verify_endpoint(
                peer,
                private_key,
                peer_public,
                identity.client_id,
                ipv4,
                profile,
                std::time::Duration::from_secs(10),
            )
            .await
            {
                Ok(rtt) => {
                    log::info!("[+] profile '{}' passed handshake + data-plane (rtt {:?})", name, rtt);
                    chosen = Some((peer, profile.clone()));
                    break;
                }
                Err(e) => {
                    log::warn!("[-] profile '{name}' failed on forced peer: {e}");
                }
            }
        }
        chosen
    } else {
        let mode_str = select_scan_mode_str().await;
        let ip = select_ip_version().await;

        let mut chosen = None;
        for (name, profile) in &candidates {
            log::info!(
                "[*] hunting for a working WireGuard endpoint (handshake + data-plane verification, aethernoize='{name}')"
            );
            match hunt_wg_peer_with_profile(&identity, &mode_str, ip, profile.clone()).await {
                Ok(peer) => {
                    log::info!("[+] selected WireGuard endpoint {peer} using aethernoize profile '{name}'");
                    chosen = Some((peer, profile.clone()));
                    break;
                }
                Err(e) => {
                    if multi {
                        log::warn!("[-] profile '{name}' found no data-plane endpoint: {e}; trying next profile");
                    } else {
                        log::warn!("[-] profile '{name}' found no data-plane endpoint: {e}");
                    }
                }
            }
        }
        chosen
    };

    let (peer, profile) = selected.ok_or(AetherError::NoCleanEndpoint)?;
    log::info!("[+] using cloudflare edge {peer}");
    run_wireguard_tunnel(identity, peer, profile, listen).await
}

async fn run_wireguard_tunnel(
    identity: account::Identity,
    peer: SocketAddr,
    aethernoize: aethernoize::AetherNoizeConfig,
    listen: SocketAddr,
) -> Result<()> {
    log::info!("[*] confirming WireGuard handshake + data flow with {peer}...");
    
    let private_key = identity.private_key_bytes()?;
    let peer_public = identity.peer_public_key_bytes()?;
    let ipv4: std::net::Ipv4Addr = identity.ipv4.parse()
        .map_err(|_| AetherError::Other("invalid ipv4".into()))?;
    
    let test_result = wireguard::verify_endpoint(
        peer,
        private_key,
        peer_public,
        identity.client_id,
        ipv4,
        &aethernoize,
        std::time::Duration::from_secs(10),
    )
    .await;
    
    match test_result {
        Ok(rtt) => {
            log::info!("[+] handshake successful (rtt {:?})", rtt);
        }
        Err(e) => {
            log::error!("[-] handshake failed: {}", e);
            return Err(AetherError::Other(format!("WireGuard handshake failed: {e}")));
        }
    }
    
    let ipv6: std::net::Ipv6Addr = identity.ipv6.parse()
        .map_err(|_| AetherError::Other("invalid ipv6".into()))?;

    let cfg = wireguard::WgConfig {
        local_private_key: private_key,
        peer_public_key: peer_public,
        peer_endpoint: peer,
        local_ipv4: ipv4,
        local_ipv6: ipv6,
        client_id: identity.client_id,
        preshared_key: None,
        persistent_keepalive: Some(wg_keepalive_secs()),
        aethernoize: std::sync::Arc::new(aethernoize),
    };

    let (outbound_tx, outbound_rx) = tokio::sync::mpsc::channel(1024);
    let (inbound_tx, inbound_rx) = tokio::sync::mpsc::channel(1024);

    let tunnel = wireguard::WgTunnel::new(cfg, inbound_tx).await?;

    let stack = netstack::spawn(&identity.ipv4, &identity.ipv6, TUNNEL_MTU, inbound_rx, outbound_tx)?;

    let socks_stack = stack.clone();
    let socks_task = tokio::spawn(async move {
        log::info!("[+] socks5 server listening on {listen}");
        socks::serve(listen, socks_stack).await
    });

    let tunnel_result = tunnel.run(outbound_rx).await;
    socks_task.abort();

    match tunnel_result {
        Ok(()) => Ok(()),
        Err(e) => Err(AetherError::Other(format!("wireguard tunnel exited: {e}"))),
    }
}

async fn establish_wg(
    identity: &account::Identity,
    peer: SocketAddr,
    mtu: usize,
    obfuscate: bool,
    keepalive: u16,
    label: &'static str,
) -> Result<netstack::StackHandle> {
    let private_key = identity.private_key_bytes()?;
    let peer_public = identity.peer_public_key_bytes()?;

    let ipv4: std::net::Ipv4Addr = identity
        .ipv4
        .parse()
        .map_err(|_| AetherError::Other("invalid ipv4".into()))?;
    let ipv6: std::net::Ipv6Addr = identity
        .ipv6
        .parse()
        .map_err(|_| AetherError::Other("invalid ipv6".into()))?;

    let profile = if obfuscate {
        aethernoize_config()
    } else {
        aethernoize::from_profile("off")
    };

    let cfg = wireguard::WgConfig {
        local_private_key: private_key,
        peer_public_key: peer_public,
        peer_endpoint: peer,
        local_ipv4: ipv4,
        local_ipv6: ipv6,
        client_id: identity.client_id,
        preshared_key: None,
        persistent_keepalive: Some(keepalive),
        aethernoize: std::sync::Arc::new(profile),
    };

    let (outbound_tx, outbound_rx) = tokio::sync::mpsc::channel(1024);
    let (inbound_tx, inbound_rx) = tokio::sync::mpsc::channel(1024);

    let tunnel = wireguard::WgTunnel::new(cfg, inbound_tx).await?;
    let stack = netstack::spawn(&identity.ipv4, &identity.ipv6, mtu, inbound_rx, outbound_tx)?;

    tokio::spawn(async move {
        if let Err(e) = tunnel.run(outbound_rx).await {
            log::error!("[{label}] wireguard tunnel exited: {e}");
        }
    });

    Ok(stack)
}

async fn spawn_udp_forwarder(
    outer: &netstack::StackHandle,
    remote: SocketAddr,
) -> Result<SocketAddr> {
    let sock = std::sync::Arc::new(tokio::net::UdpSocket::bind("127.0.0.1:0").await?);
    let local = sock.local_addr()?;

    let udp = outer.open_udp().await?;
    let (udp_tx, mut udp_rx) = udp.into_split();

    let inner_peer: std::sync::Arc<tokio::sync::Mutex<Option<SocketAddr>>> =
        std::sync::Arc::new(tokio::sync::Mutex::new(None));

    let up_sock = sock.clone();
    let up_peer = inner_peer.clone();
    tokio::spawn(async move {
        let mut buf = vec![0u8; 65536];
        loop {
            match up_sock.recv_from(&mut buf).await {
                Ok((n, from)) => {
                    *up_peer.lock().await = Some(from);
                    if udp_tx.send_to(remote, buf[..n].to_vec()).await.is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
    });

    let down_sock = sock.clone();
    let down_peer = inner_peer.clone();
    tokio::spawn(async move {
        while let Some((_src, data)) = udp_rx.recv().await {
            let dst = *down_peer.lock().await;
            if let Some(dst) = dst {
                let _ = down_sock.send_to(&data, dst).await;
            }
        }
    });

    Ok(local)
}

async fn run_warp_in_warp(
    primary: account::Identity,
    secondary: account::Identity,
    peer: SocketAddr,
    listen: SocketAddr,
) -> Result<()> {
    log::info!("[*] establishing outer WARP tunnel to {peer}...");
    let outer_stack = establish_wg(&primary, peer, TUNNEL_MTU, true, 5, "outer").await?;

    tokio::time::sleep(std::time::Duration::from_millis(1500)).await;

    let forwarder = spawn_udp_forwarder(&outer_stack, peer).await?;
    log::info!("[+] inner endpoint tunneled through outer warp via {forwarder}");

    log::info!("[*] establishing inner WARP tunnel (warp-in-warp)...");
    let inner_stack = establish_wg(&secondary, forwarder, INNER_MTU, false, 20, "inner").await?;

    log::info!("[+] socks5 server listening on {listen}");
    socks::serve(listen, inner_stack).await
}

async fn prompt_line(prompt: &str) -> Option<String> {
    use std::io::IsTerminal;
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

    if !std::io::stdin().is_terminal() {
        return None;
    }

    let mut stdout = tokio::io::stdout();
    let _ = stdout.write_all(prompt.as_bytes()).await;
    let _ = stdout.flush().await;

    let mut line = String::new();
    let mut reader = BufReader::new(tokio::io::stdin());
    match reader.read_line(&mut line).await {
        Ok(0) | Err(_) => None,
        Ok(_) => Some(line.trim().to_string()),
    }
}

async fn select_scan_mode() -> prober::ScanMode {
    if let Ok(v) = std::env::var("AETHER_SCAN") {
        return prober::ScanMode::parse(&v);
    }

    let answer = prompt_line(
        "\nScan mode:\n  [1] turbo     (fast, first hit)\n  [2] balanced  (default)\n  [3] thorough  (deep, best ping)\n  [4] stealth   (quiet, patient)\nChoose [1-4] (default 2): ",
    )
    .await;

    match answer.as_deref() {
        Some("1") => prober::ScanMode::Turbo,
        Some("3") => prober::ScanMode::Thorough,
        Some("4") => prober::ScanMode::Stealth,
        _ => prober::ScanMode::Balanced,
    }
}

async fn select_scan_mode_str() -> String {
    if let Ok(v) = std::env::var("AETHER_SCAN") {
        return v;
    }

    let answer = prompt_line(
        "\nScan mode:\n  [1] turbo     (fast, first hit)\n  [2] balanced  (default)\n  [3] thorough  (deep, best ping)\n  [4] stealth   (quiet, patient)\nChoose [1-4] (default 2): ",
    )
    .await;

    match answer.as_deref() {
        Some("1") => "turbo".to_string(),
        Some("3") => "thorough".to_string(),
        Some("4") => "stealth".to_string(),
        _ => "balanced".to_string(),
    }
}

async fn select_protocol() -> Protocol {
    if let Ok(v) = std::env::var("AETHER_PROTOCOL") {
        return Protocol::parse(&v);
    }

    let answer = prompt_line(
        "\nProtocol:\n  [1] MASQUE (modern, QUIC/H3, default)\n  [2] WireGuard (classic, faster)\n  [3] WARP-in-WARP / gool\nChoose [1-3] (default 1): ",
    )
    .await;

    match answer.as_deref() {
        Some("2") => Protocol::WireGuard,
        Some("3") => Protocol::WarpInWarp,
        _ => Protocol::Masque,
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Protocol {
    Masque,
    WireGuard,
    WarpInWarp,
}

impl Protocol {
    fn parse(s: &str) -> Protocol {
        match s.trim().to_lowercase().as_str() {
            "wg" | "wireguard" => Protocol::WireGuard,
            "gool" | "wiw" | "warp-in-warp" | "warpinwarp" => Protocol::WarpInWarp,
            _ => Protocol::Masque,
        }
    }

    fn label(&self) -> &'static str {
        match self {
            Protocol::Masque => "MASQUE",
            Protocol::WireGuard => "WireGuard",
            Protocol::WarpInWarp => "WARP-in-WARP (gool)",
        }
    }
}

async fn select_ip_version() -> prober::IpScan {
    if let Ok(v) = std::env::var("AETHER_IP") {
        return prober::IpScan::parse(&v);
    }

    let answer = prompt_line(
        "\nIP version to scan:\n  [1] IPv4 (default)\n  [2] IPv6\n  [3] Both\nChoose [1-3] (default 1): ",
    )
    .await;

    match answer.as_deref() {
        Some("2") => prober::IpScan::V6,
        Some("3") => prober::IpScan::Both,
        _ => prober::IpScan::V4,
    }
}

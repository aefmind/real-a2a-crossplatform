use anyhow::{Context, Result};
use chrono::Local;
use clap::{Parser, Subcommand};
use colored::*;
use iroh::{
    discovery::static_provider::StaticProvider,
    protocol::Router,
    Endpoint, EndpointAddr, PublicKey, RelayMode, SecretKey,
};
use iroh_gossip::{
    net::{Gossip, GOSSIP_ALPN},
    proto::TopicId,
};
use n0_future::StreamExt;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};

const DEFAULT_ROOM: &str = "claude-a2a-global";

// Adjectives and animals for memorable names
const ADJECTIVES: &[&str] = &[
    "brave", "calm", "swift", "wise", "bold", "keen", "fair", "glad",
    "warm", "cool", "bright", "quick", "sharp", "fresh", "clear", "pure",
];

const ANIMALS: &[&str] = &[
    "falcon", "otter", "tiger", "wolf", "eagle", "fox", "bear", "hawk",
    "lion", "lynx", "raven", "owl", "deer", "crane", "heron", "swan",
];

#[derive(Parser)]
#[command(name = "real-a2a")]
#[command(about = "Real Agent-to-Agent P2P Chat")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Start the P2P chat daemon
    Daemon {
        /// Your identity name (e.g., "brave-falcon"). Auto-generated if not specified.
        #[arg(short, long)]
        identity: Option<String>,

        /// Room name to join
        #[arg(short, long, default_value = DEFAULT_ROOM)]
        room: String,

        /// Join via ticket (contains room + peer addresses)
        #[arg(short, long)]
        join: Option<String>,
    },
    /// Send a message to the chat
    Send {
        /// Identity to send from
        #[arg(short, long)]
        identity: Option<String>,

        /// Message to send
        message: String,
    },
    /// Show or create an identity
    Id {
        /// Identity name to show/create
        #[arg(short, long)]
        identity: Option<String>,
    },
    /// List all identities
    List,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
struct Identity {
    name: String,
    secret_key: String, // base64 encoded
    created: i64,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
struct Ticket {
    topic: [u8; 32],
    peers: Vec<EndpointAddr>,
}

impl Ticket {
    fn to_string(&self) -> String {
        let bytes = postcard::to_stdvec(self).expect("serialize ticket");
        data_encoding::BASE32_NOPAD.encode(&bytes).to_lowercase()
    }

    fn from_string(s: &str) -> Result<Self> {
        let bytes = data_encoding::BASE32_NOPAD
            .decode(s.to_uppercase().as_bytes())
            .context("invalid ticket encoding")?;
        postcard::from_bytes(&bytes).context("invalid ticket format")
    }
}

#[derive(Serialize, Deserialize, Debug, Clone)]
struct ChatMessage {
    from_name: String,
    from_id: String,
    content: String,
    timestamp: i64,
}

fn get_data_dir() -> Result<PathBuf> {
    let proj_dirs = directories::ProjectDirs::from("com", "a2a", "real-a2a")
        .context("Could not determine data directory")?;
    let data_dir = proj_dirs.data_dir().to_path_buf();
    std::fs::create_dir_all(&data_dir)?;
    Ok(data_dir)
}

fn get_identities_dir() -> Result<PathBuf> {
    let dir = get_data_dir()?.join("identities");
    std::fs::create_dir_all(&dir)?;
    Ok(dir)
}

fn get_socket_path(identity: &str) -> Result<PathBuf> {
    Ok(get_data_dir()?.join(format!("daemon-{}.sock", identity)))
}

fn generate_memorable_name() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .subsec_nanos() as usize;

    let adj = ADJECTIVES[nanos % ADJECTIVES.len()];
    let animal = ANIMALS[(nanos / 16) % ANIMALS.len()];
    format!("{}-{}", adj, animal)
}

fn load_or_create_identity(name: Option<String>) -> Result<Identity> {
    let identities_dir = get_identities_dir()?;

    // If name provided, try to load existing
    if let Some(ref name) = name {
        let path = identities_dir.join(format!("{}.json", name));
        if path.exists() {
            let content = std::fs::read_to_string(&path)?;
            return Ok(serde_json::from_str(&content)?);
        }
    }

    // Generate new identity
    let name = name.unwrap_or_else(generate_memorable_name);
    let secret_key = SecretKey::generate(&mut rand::rng());
    let identity = Identity {
        name: name.clone(),
        secret_key: data_encoding::BASE64.encode(&secret_key.to_bytes()),
        created: chrono::Utc::now().timestamp(),
    };

    // Save it
    let path = identities_dir.join(format!("{}.json", name));
    let json = serde_json::to_string_pretty(&identity)?;
    std::fs::write(&path, json)?;

    Ok(identity)
}

fn load_identity(name: &str) -> Result<Identity> {
    let path = get_identities_dir()?.join(format!("{}.json", name));
    if !path.exists() {
        anyhow::bail!("Identity '{}' not found. Create it first with: real-a2a daemon --identity {}", name, name);
    }
    let content = std::fs::read_to_string(&path)?;
    Ok(serde_json::from_str(&content)?)
}

fn get_secret_key(identity: &Identity) -> Result<SecretKey> {
    let bytes = data_encoding::BASE64
        .decode(identity.secret_key.as_bytes())
        .context("invalid secret key encoding")?;
    let bytes: [u8; 32] = bytes.try_into().map_err(|_| anyhow::anyhow!("invalid key length"))?;
    Ok(SecretKey::from_bytes(&bytes))
}

fn topic_from_room(room: &str) -> TopicId {
    let hash = blake3::hash(format!("real-a2a:{}", room).as_bytes());
    TopicId::from_bytes(*hash.as_bytes())
}

fn get_timestamp() -> String {
    Local::now().format("%H:%M:%S").to_string()
}

fn print_system(msg: &str) {
    println!("{}", format!("[{}] ** {} **", get_timestamp(), msg).dimmed());
}

fn print_message(from_name: &str, from_id: &str, content: &str, is_self: bool) {
    let timestamp = get_timestamp();
    let short_id = &from_id[..8.min(from_id.len())];

    if is_self {
        println!(
            "{} {} {}",
            format!("[{}]", timestamp).dimmed(),
            format!("<{}@{}>", from_name, short_id).green().bold(),
            content
        );
    } else {
        println!(
            "{} {} {}",
            format!("[{}]", timestamp).dimmed(),
            format!("<{}@{}>", from_name, short_id).cyan(),
            content
        );
    }
}

async fn run_daemon(identity_name: Option<String>, room: String, join_ticket: Option<String>) -> Result<()> {
    // Load or create identity
    let identity = load_or_create_identity(identity_name)?;
    let secret_key = get_secret_key(&identity)?;

    println!("{}", "══════════════════════════════════════════════════════════".bold());
    println!("{}", "  RealA2A - Agent-to-Agent P2P Chat".bold());
    println!("  Identity: {}", identity.name.yellow().bold());
    println!("  Room: {}", room.cyan());
    println!("{}", "══════════════════════════════════════════════════════════".bold());
    println!();

    print_system("initializing iroh endpoint...");

    // Create static provider for peer discovery
    let static_provider = StaticProvider::new();

    // Create iroh endpoint with relay and discovery
    let endpoint = Endpoint::builder()
        .secret_key(secret_key)
        .relay_mode(RelayMode::Default)
        .discovery(static_provider.clone())
        .bind()
        .await
        .context("Failed to create iroh endpoint")?;

    let my_id = endpoint.id();
    println!("  Node ID: {}", my_id.to_string()[..16].to_string().dimmed());

    // Parse ticket if provided
    let (topic, bootstrap_peers) = if let Some(ticket_str) = join_ticket {
        let ticket = Ticket::from_string(&ticket_str)?;
        let topic = TopicId::from_bytes(ticket.topic);

        // Add peers to static provider
        for peer in &ticket.peers {
            static_provider.add_endpoint_info(peer.clone());
        }

        let peer_ids: Vec<PublicKey> = ticket.peers.iter().map(|p| p.id).collect();
        print_system(&format!("joining via ticket with {} peers", peer_ids.len()));
        (topic, peer_ids)
    } else {
        let topic = topic_from_room(&room);
        (topic, vec![])
    };

    // Build gossip protocol
    let gossip = Gossip::builder().spawn(endpoint.clone());

    // Setup router
    let router = Router::builder(endpoint.clone())
        .accept(GOSSIP_ALPN, gossip.clone())
        .spawn();

    // Wait for relay connection before generating ticket
    print_system("connecting to relay...");
    endpoint.online().await;

    // Generate and print ticket
    let my_addr = endpoint.addr();
    let ticket = Ticket {
        topic: *topic.as_bytes(),
        peers: vec![my_addr],
    };
    println!();
    println!("  {}: {}", "Ticket".green().bold(), ticket.to_string());
    println!("  {}", "(Share this to let others join)".dimmed());
    println!();

    print_system("joining gossip swarm...");

    let (sender, mut receiver) = gossip
        .subscribe(topic, bootstrap_peers)
        .await
        .context("Failed to subscribe to topic")?
        .split();

    let sender = Arc::new(sender);

    // Setup Unix socket
    let socket_path = get_socket_path(&identity.name)?;
    if socket_path.exists() {
        tokio::fs::remove_file(&socket_path).await?;
    }

    let listener = UnixListener::bind(&socket_path)?;
    print_system(&format!("listening on socket for '{}'", identity.name));

    // Spawn socket handler
    let sender_for_socket = sender.clone();
    let identity_name = identity.name.clone();
    let my_id_for_socket = my_id;
    tokio::spawn(async move {
        loop {
            if let Ok((stream, _)) = listener.accept().await {
                let sender = sender_for_socket.clone();
                let name = identity_name.clone();
                let id = my_id_for_socket;

                tokio::spawn(async move {
                    if let Err(e) = handle_socket_connection(stream, sender, &name, &id).await {
                        eprintln!("Socket error: {}", e);
                    }
                });
            }
        }
    });

    print_system("ready! waiting for messages...");
    println!();

    // Main loop
    loop {
        tokio::select! {
            event = receiver.try_next() => {
                match event {
                    Ok(Some(event)) => {
                        use iroh_gossip::api::Event;
                        match event {
                            Event::Received(msg) => {
                                if let Ok(chat_msg) = serde_json::from_slice::<ChatMessage>(&msg.content) {
                                    let is_self = chat_msg.from_id == my_id.to_string();
                                    print_message(&chat_msg.from_name, &chat_msg.from_id, &chat_msg.content, is_self);
                                }
                            }
                            Event::NeighborUp(node_id) => {
                                print_system(&format!("peer connected: {}...", &node_id.to_string()[..8]));
                            }
                            Event::NeighborDown(node_id) => {
                                print_system(&format!("peer disconnected: {}...", &node_id.to_string()[..8]));
                            }
                            _ => {}
                        }
                    }
                    Ok(None) => {
                        print_system("gossip stream ended");
                        break;
                    }
                    Err(e) => {
                        print_system(&format!("gossip error: {}", e));
                    }
                }
            }
            _ = tokio::signal::ctrl_c() => {
                println!();
                print_system("shutting down...");
                break;
            }
        }
    }

    // Cleanup
    if let Err(e) = router.shutdown().await {
        eprintln!("Error during shutdown: {:?}", e);
    }
    let _ = tokio::fs::remove_file(&socket_path).await;

    print_system("disconnected");
    Ok(())
}

async fn handle_socket_connection(
    stream: UnixStream,
    sender: Arc<iroh_gossip::api::GossipSender>,
    identity_name: &str,
    node_id: &PublicKey,
) -> Result<()> {
    let mut reader = BufReader::new(stream);
    let mut line = String::new();

    while reader.read_line(&mut line).await? > 0 {
        let message = line.trim().to_string();
        if !message.is_empty() {
            let chat_msg = ChatMessage {
                from_name: identity_name.to_string(),
                from_id: node_id.to_string(),
                content: message.clone(),
                timestamp: chrono::Utc::now().timestamp(),
            };

            let json = serde_json::to_vec(&chat_msg)?;
            sender.broadcast(json.into()).await?;

            print_message(identity_name, &node_id.to_string(), &message, true);
        }
        line.clear();
    }

    Ok(())
}

async fn send_message(identity_name: Option<String>, message: String) -> Result<()> {
    // Find socket - either specified identity or find any running daemon
    let socket_path = if let Some(name) = identity_name {
        get_socket_path(&name)?
    } else {
        // Try to find any daemon socket
        let data_dir = get_data_dir()?;
        let mut found = None;
        if let Ok(entries) = std::fs::read_dir(&data_dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().map(|e| e == "sock").unwrap_or(false) {
                    found = Some(path);
                    break;
                }
            }
        }
        found.context("No daemon running. Start one with: real-a2a daemon")?
    };

    if !socket_path.exists() {
        anyhow::bail!("Daemon not running for this identity. Start it with: real-a2a daemon --identity <name>");
    }

    let mut stream = UnixStream::connect(&socket_path)
        .await
        .context("Failed to connect to daemon")?;

    stream.write_all(message.as_bytes()).await?;
    stream.write_all(b"\n").await?;
    stream.flush().await?;

    Ok(())
}

async fn show_identity(name: Option<String>) -> Result<()> {
    let identity = load_or_create_identity(name)?;
    let secret_key = get_secret_key(&identity)?;

    println!("{}", "Identity:".bold());
    println!("  Name: {}", identity.name.yellow());
    println!("  Public Key: {}", secret_key.public().to_string());
    println!("  Created: {}", chrono::DateTime::from_timestamp(identity.created, 0)
        .map(|dt| dt.format("%Y-%m-%d %H:%M:%S").to_string())
        .unwrap_or_else(|| "unknown".to_string()));

    Ok(())
}

async fn list_identities() -> Result<()> {
    let dir = get_identities_dir()?;
    let mut identities = Vec::new();

    if let Ok(entries) = std::fs::read_dir(&dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().map(|e| e == "json").unwrap_or(false) {
                if let Ok(content) = std::fs::read_to_string(&path) {
                    if let Ok(identity) = serde_json::from_str::<Identity>(&content) {
                        identities.push(identity);
                    }
                }
            }
        }
    }

    if identities.is_empty() {
        println!("No identities found. Create one with: real-a2a daemon");
    } else {
        println!("{}", "Identities:".bold());
        for id in identities {
            let socket_path = get_socket_path(&id.name)?;
            let status = if socket_path.exists() { "running".green() } else { "stopped".dimmed() };
            println!("  {} [{}]", id.name.yellow(), status);
        }
    }

    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Daemon { identity, room, join } => {
            run_daemon(identity, room, join).await?;
        }
        Commands::Send { identity, message } => {
            send_message(identity, message).await?;
        }
        Commands::Id { identity } => {
            show_identity(identity).await?;
        }
        Commands::List => {
            list_identities().await?;
        }
    }

    Ok(())
}

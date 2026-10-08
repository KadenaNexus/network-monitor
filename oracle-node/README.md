# Saudi Arabia Oracle Chainweb node

Server: `ubuntu@193.122.85.1`, Oracle Cloud region `me-jeddah-1` (Jeddah).
Ubuntu 22.04, x86_64, 2 CPUs, 12 GB RAM and a 200 GB boot volume.

The node uses the maintained [Chainweb Community 3.2.1 release](https://github.com/kda-community/chainweb-node/releases/tag/3.2.1), network `mainnet01`. The original kadena-io distribution is archived; use the Community release to join the network shown on nodes.kadena.ws.

## Storage and initial database

The [snapshot distributor](https://snapshots.chainweb-community.org/) published an approximately 60 GB compacted snapshot on 2026-10-07. The full snapshot is approximately 452 GB and does not fit this server. This setup uses the compacted snapshot and sets `fullHistoricPactState: false`, as required by the distributor. It validates new blocks and maintains current Pact state, with limited historical payload/state coverage; historical `/spv` or `/pool` requests may not work. Allocate more storage for archival use and monitor disk growth.

`chainweb-bootstrap.service` downloads the frozen snapshot over HTTPS and verifies both RocksDB and SQLite databases against the distributor's BLAKE2 manifests. `chainweb-node.service` starts only when verification succeeds. The verification marker prevents a later restart from downloading over an operating database. Both services run as the unprivileged `chainweb` user. The node is enabled at boot and restarts on failure.

Installed locations:

- Binary: `/usr/local/bin/chainweb-node`
- Configuration: `/etc/chainweb/config.yaml`
- Snapshot URL list: `/etc/chainweb/snapshot-downloads.txt`
- Initial download script: `/usr/local/lib/chainweb/bootstrap.sh`
- Database and verification marker: `/var/lib/chainweb`
- Units: `/etc/systemd/system/chainweb-{bootstrap,node}.service`

The files in this directory record the installed configuration. Do not rerun the snapshot download over a running node or remove the verification marker.

## Access and firewall

Mustafa's existing Ed25519 public key is added to Ubuntu's `authorized_keys`. The supplied private key and personal private key stay on the local machine and are not stored in this repository.

Public P2P API: `https://193.122.85.1:1789`. The self-signed node certificate requires `curl -k` when accessing the IP directly. The node advertises the public IP and listens on IPv4. It uses five community bootstrap peers verified from Jeddah; the packaged `us-e1.bootstrap.kadinic.com` repeatedly timed out, so the built-in list is replaced with the working community peers. Cut fetching allows 30 seconds instead of the default 3 seconds to avoid repeated timeouts during initial catch-up. Normal-operation logging is set to `warn`.

Service API: `http://127.0.0.1:1848`, accessible on the server or through an SSH tunnel. Mining is disabled.

Oracle's host firewall initially rejected incoming connections after the SSH rule. TCP 1789 is accepted before that REJECT rule, and the rules are saved with `netfilter-persistent`. Oracle's console ingress rule also allows TCP 1789, confirmed by an external probe and an HTTP 200 response from the node's public HTTPS cut endpoint.

## Three operational checks

The linked dashboard README contains no node setup or three node checks. Use these checks to report the actual deployment status; do not report an initial snapshot download as a healthy synchronized node.

1. **Service and local health**:

   ```sh
   ssh ubuntu@193.122.85.1 'systemctl is-enabled chainweb-node; systemctl is-active chainweb-node; curl -fsS http://127.0.0.1:1848/health-check; curl -fsS http://127.0.0.1:1848/info'
   ```

2. **Public P2P reachability**, from another machine:

   ```sh
   curl -fk --connect-timeout 10 --max-time 30 https://193.122.85.1:1789/chainweb/0.0/mainnet01/cut
   ```

   Require HTTP 200 and JSON containing all 20 chains with `instance: mainnet01`.

3. **Synchronization**: compare the node's cut with a healthy bootstrap, and repeat to see that both advance:

   ```sh
   curl -fksS https://193.122.85.1:1789/chainweb/0.0/mainnet01/cut | jq '{height, chains: [.hashes[].height]}'
   curl -fsS https://fr-1.chainweb-community.org/chainweb/0.0/mainnet01/cut | jq '{height, chains: [.hashes[].height]}'
   ```

   Inspect logs for failures and progress:

   ```sh
   ssh ubuntu@193.122.85.1 'sudo journalctl -u chainweb-node -n 100 --no-pager'
   ```

During initial download, inspect `sudo journalctl -u chainweb-bootstrap` and `sudo du -sh /var/lib/chainweb`. Retry a failed initial download with `sudo systemctl restart chainweb-bootstrap`, then `sudo systemctl start chainweb-node` after it succeeds.

The recorded deployment checks are in [`verification.json`](verification.json). The service and public endpoint pass. On 2026-10-08 at 10:30:57 UTC, all 20 chain heights matched the community reference at cut height 145943296, with zero blocks behind. The public P2P endpoint was also verified from another machine.

## Oracle Cloud on the dashboard

`client/index.html` maps crawler organization/ISP strings containing `oracle` to `Oracle Cloud`. Hosting counts use reachable nodes from `nodes.denascan.com`, with a same-origin proxy to `kdascan.dnns.es` when the primary crawler is unavailable; the provider appears when a reachable Oracle node is included in the selected crawler data. The Oracle label was installed live on 2026-10-08 at 10:07:07 UTC. No node or count is fabricated.

## Public service endpoint for the homepage

nginx is installed and exposes GET/HEAD only for `/info`, `/health-check` and `/chainweb/0.0/mainnet01/cut`, with CORS `*` and a request limit. The local gateway passed HTTP 200 and CORS checks; POST returns 403 and transaction submission paths return 404. Host firewall accepts TCP 80 and 443 and persists the rules.

`node.kadena.ws.conf`, `setup-node-gateway.sh` and `activate-node-https.sh` record the deployed HTTP gateway and the final HTTPS activation step. Oracle web ingress is now configured, and the gateway responds with HTTP 200 externally. The GoDaddy A record was created as `node.kadena.ws.kadena.ws`; its Name/Host needs to be changed to `node` before `node.kadena.ws` can resolve and HTTPS can be activated. Once completed, run:

```sh
ssh ubuntu@193.122.85.1 'sudo bash /home/ubuntu/kadena-homepage-update/activate-node-https.sh'
```

Verify `https://node.kadena.ws/info`, the CORS header, and the HTTPS cut from another machine. Certbot's renewal timer is enabled. The homepage and website installer are preserved on branch `codex/kadena-homepage-node`, under `deploy/kadena-ws-update`.

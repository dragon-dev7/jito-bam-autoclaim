# jito-bam-autoclaim

Automatically claims your **Jito BAM Boost (JIP-31)** rewards, so none of them expire.

Every epoch, Jito pays a JitoSOL subsidy to validators running the BAM client. Each epoch's boost has to be **claimed within 10 epochs**. After that it is forfeited and redistributed to other validators. Across all closed epochs so far, **about 17% of the boost (≈8,200 JitoSOL) was never claimed**, and only one validator in three has never missed a claim. ([analytics](https://dragontrust.pro/analytics/bam-boost))

This tool runs from cron every 4 hours. It asks the public Jito API which epochs still hold an unclaimed boost for your identity and claims only those, using the official [`jito-bam-boost-cli`](https://github.com/jito-foundation/jito-bam-boost-cli).

- **No guesswork:** it claims only what the Jito API reports as unclaimed, and checks the claim-status account on chain, so you won't see the usual `-32002 Transaction simulation failed` noise from re-claiming.
- **Finds your identity keypair** from the `--identity` argument of the running `agave-validator` / `solana-validator` process. No paths to configure, wherever you built Agave.
- **Dry run**, a single-epoch mode, retries, a lock against overlapping runs, and optional **Telegram** notifications.
- **Plain bash**, about 150 lines. Read it before you run it.

## Install

On the validator, as root:

```bash
curl -fsSL https://raw.githubusercontent.com/dragon-dev7/jito-bam-autoclaim/main/install.sh -o install.sh
less install.sh
sudo bash install.sh
```

The installer:

1. clones and builds `jito-foundation/jito-bam-boost-cli` in release mode (needs Rust; first build takes a few minutes);
2. installs `/usr/local/bin/jito-bam-autoclaim`;
3. writes `/etc/jito-bam-autoclaim.conf` with the keypair path it detected;
4. adds `/etc/cron.d/jito-bam-autoclaim` (every 4 h) and log rotation;
5. runs a dry run so you can see what is open.

Already have a checkout of the CLI? `sudo CLI_DIR=/root/jito-bam-boost-cli bash install.sh`

## Usage

```bash
jito-bam-autoclaim --dry-run     # what would be claimed
jito-bam-autoclaim               # claim everything open
jito-bam-autoclaim --epoch 1093  # one epoch
tail -f /var/log/jito-bam-autoclaim.log
```

Example log:

```
[2026-11-23T09:23:04Z] epoch 1094: claiming 0.1912 JitoSOL
[2026-11-23T09:23:06Z] epoch 1094: CLAIMED tx=3nYjN66G…
[2026-11-23T09:23:06Z] identity 3Behar… · epochs 1085-1094 · with boost: 10 · claimed now: 1
```

## Settings

`/etc/jito-bam-autoclaim.conf` (mode 600):

| Variable | Default | |
|---|---|---|
| `RPC_URL` | `https://api.mainnet-beta.solana.com` | Your own RPC is more reliable. |
| `CLI_BIN` | `/opt/jito-bam-boost-cli/target/release/jito-bam-boost-cli` | Path to the built CLI. |
| `SIGNER` | auto-detected | Identity keypair that receives the boost. |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | empty | Notifications on claims and repeated failures. |

## Notes

- **Hot-swap / failover setups:** if your validator starts with a junk identity and switches with `set-identity`, the `--identity` argument is not your staked key. Set `SIGNER` to the real identity keypair. The log prints the pubkey it uses, so check it.
- The identity key signs and pays the transaction fee for each claim, exactly as with the manual CLI command.
- Rewards for epoch N usually become claimable about 25% into epoch N+1, so a 4-hour schedule is plenty.
- Requirements: `bash`, `curl`, `python3`, `flock`, and Rust to build the CLI. Tested on Ubuntu 24.04 with Jito-Agave 4.4.

## Programme timeline

BAM Boost is temporary. Under the current JIP-39 proposal it would run at the full rate through Q4 2026, then halve every 10 epochs from Q1 2027 and end at the last epoch of Q2 2027. Check the [Jito forum](https://forum.jito.network) for the outcome of the vote.

---

MIT licence. Made by the [Dragon Trust](https://dragontrust.pro) validator. Issues and PRs welcome.

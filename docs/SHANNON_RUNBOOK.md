# Shannon Verification Runbook

This runbook deploys the first ImpactOS brick to Somnia Shannon and asks the
Somnia JSON API Agent whether a public GitHub pull request is merged.

This contract does not hold donor funds or release milestone payments. It is the
production-shaped evidence-verification foundation that the escrow layer will
use later.

## What You Need

1. A dedicated EVM wallet for ImpactOS deployment and administration.
2. Enough Shannon STT for deployment gas and the agent request deposit.
3. A public GitHub repository and pull request number.
4. Foundry installed locally.

Do not send or commit the wallet private key. Store it only in the local `.env`
file, which Git ignores.

## Official Shannon Details

- Chain ID: `50312`
- Currency: `STT`
- RPC: `https://dream-rpc.somnia.network/`
- Explorer: <https://shannon-explorer.somnia.network/>
- Faucet: <https://testnet.somnia.network/>
- Network reference: <https://docs.somnia.network/developer/network-info>

## 1. Configure the Local Environment

```bash
cp .env.example .env
```

Populate these values in `.env`:

```dotenv
PRIVATE_KEY=0xYOUR_DEDICATED_SHANNON_PRIVATE_KEY
GITHUB_OWNER=your-github-owner
GITHUB_REPO=your-public-repository
GITHUB_PR_NUMBER=1
```

Load the values into the current shell:

```bash
set -a
source .env
set +a
```

Confirm the wallet address and STT balance:

```bash
cast wallet address --private-key "$PRIVATE_KEY"
cast balance "$(cast wallet address --private-key "$PRIVATE_KEY")" \
  --rpc-url "$SHANNON_RPC_URL" \
  --ether
```

## 2. Verify Locally

```bash
forge fmt --check
forge build
forge test
```

All checks must pass before broadcasting.

## 3. Deploy the Verifier

```bash
forge script script/DeployGitHubPullRequestVerifier.s.sol \
  --rpc-url shannon \
  --broadcast
```

Copy the deployed contract address from the broadcast output into `.env`:

```dotenv
VERIFIER_ADDRESS=0xYOUR_DEPLOYED_VERIFIER
```

Reload `.env`, then confirm the immutable configuration:

```bash
set -a
source .env
set +a

cast call "$VERIFIER_ADDRESS" "administrator()(address)" \
  --rpc-url "$SHANNON_RPC_URL"

cast call "$VERIFIER_ADDRESS" "platform()(address)" \
  --rpc-url "$SHANNON_RPC_URL"
```

The Shannon platform address must be:

```text
0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776
```

## 4. Submit a Live Verification

The request script reads the public GitHub evidence from `.env`. It checks the
current agent deposit and funds only the missing verifier balance before
submitting the request.

```bash
forge script script/RequestGitHubVerification.s.sol \
  --rpc-url shannon \
  --broadcast
```

Open the transaction in the Shannon explorer and record the
`VerificationRequested` request ID.

## 5. Confirm the Agent Callback

Wait for the Somnia Agents platform to call `handleResponse`. The verifier must
emit `VerificationResolved` with one of these terminal states:

- `Merged`
- `NotMerged`
- `Failed`
- `TimedOut`

Read the stored result with the request ID:

```bash
cast call "$VERIFIER_ADDRESS" \
  "getVerification(uint256)((string,string,uint256,uint8,uint64,uint64))" \
  YOUR_REQUEST_ID \
  --rpc-url "$SHANNON_RPC_URL"
```

## Acceptance Checklist

- Local formatting, build, and tests pass.
- Deployment transaction succeeds on chain `50312`.
- `administrator()` matches the deployment wallet.
- `platform()` matches the official Shannon Agents address.
- A public merged PR resolves to `Merged`.
- A public open PR resolves to `NotMerged`.
- A spoofed non-platform callback is rejected by the local security suite.
- A malformed agent result produces `Failed` rather than reverting finalization.
- Transaction links, request IDs, and contract address are recorded for the demo.

Only after this checklist passes should ImpactOS connect verification results to
milestone escrow and payment release.

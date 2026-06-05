# ImpactOS

ImpactOS is a milestone escrow for public-good funding. Somnia Agents verify
public evidence before milestone payments become eligible for release.

The project is being built brick by brick. Each meaningful layer is committed
separately so the history remains easy to review and audit.

## Current Build

Brick 1 implements a complete asynchronous verification path:

1. The administrator submits a public GitHub repository and pull request.
2. The verifier calls Somnia's JSON API Agent with the GitHub API URL.
3. Somnia validators fetch the `merged` field and reach consensus.
4. Only the official Somnia Agents contract may deliver the callback.
5. ImpactOS stores a terminal `Merged`, `NotMerged`, `Failed`, or `TimedOut`
   result onchain.

The implementation includes exact request funding, callback authentication,
threshold handling, malformed-response protection, Shannon deployment tooling,
and 12 focused tests.

No escrow or donor funds are involved in this brick. Verification must pass live
on Shannon before it is allowed to control milestone payments.

## Requirements

- Foundry
- Node.js 20 or newer
- A funded Somnia Shannon testnet wallet for live deployment
- A public GitHub repository with one merged and one open test pull request

No GitHub token is needed for public repositories.

## Development

```bash
forge install foundry-rs/forge-std --no-git --shallow
forge install OpenZeppelin/openzeppelin-contracts@v5.6.1 --no-git --shallow
forge build
forge test
forge fmt --check
```

## Repository Map

- `src/GitHubPullRequestVerifier.sol`: asynchronous GitHub evidence verifier
- `src/interfaces/`: typed Somnia Agents and JSON API interfaces
- `src/libraries/SomniaConfig.sol`: official network and agent configuration
- `script/`: deployment and live verification operators
- `test/`: request, consensus, and callback security coverage

## First Live Proof

The only owner-provided inputs needed now are:

1. A dedicated deployment wallet, with its private key stored only in local
   `.env`.
2. Shannon STT in that wallet.
3. Public merged and open pull request numbers.

Follow the [Shannon verification runbook](./docs/SHANNON_RUNBOOK.md) to deploy
and complete the acceptance checklist.

## Shannon Deployment

The first verifier is deployed on Somnia Shannon:

- Contract:
  [`0xa163...c824`](https://shannon-explorer.somnia.network/address/0xa163743e196D2328Ce619F6B911ED24B7F42c824)
- Transaction:
  [`0x1065...a51`](https://shannon-explorer.somnia.network/tx/0x106552557f01d4038a747da73c183b1cae9cce433ee992cd09eb415ae6b09a51)
- Deployment record: [`deployments/shannon.json`](./deployments/shannon.json)
- Live proof:
  [`deployments/shannon-live-verification.json`](./deployments/shannon-live-verification.json)

The live proof checks the same GitHub pull request twice. Somnia resolved it as
`NotMerged` while open and `Merged` after merge, with two successful validator
responses for each callback.

## Documentation

- [Production build plan](./IMPACTOS_BUILD_PLAN.md)
- [Shannon verification runbook](./docs/SHANNON_RUNBOOK.md)

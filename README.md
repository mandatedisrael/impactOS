# ImpactOS

ImpactOS is a milestone escrow for public-good funding. Somnia Agents verify
public evidence before milestone payments become eligible for release.

The project is being built brick by brick. Each meaningful layer is committed
separately so the history remains easy to review and audit.

## Current Brick

Brick 1 proves that a Solidity contract on Somnia can ask the JSON API Request
Agent whether a public GitHub pull request has been merged.

No escrow or production funds are involved in this brick.

## Requirements

- Foundry
- Node.js 20 or newer
- A funded Somnia Shannon testnet wallet for live deployment
- A public GitHub repository with test pull requests

## Development

```bash
forge install foundry-rs/forge-std --no-git --shallow
forge build
forge test
forge fmt --check
```

## Documentation

- [Production build plan](./IMPACTOS_BUILD_PLAN.md)

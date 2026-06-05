# ImpactOS Build Plan

## 1. Product Definition

ImpactOS is a milestone escrow for public-good funding.

Funders lock USDC against explicit milestones. A grantee submits public evidence.
Somnia Agents inspect the evidence and propose a verdict. Successful verdicts enter
a challenge period before funds become claimable.

The first production market is digitally verifiable open-source work.

Examples:

- A pull request was merged into an approved repository and branch.
- A release containing agreed functionality was published.
- A public deployment exposes an agreed health or version response.

ImpactOS V1 does not claim to verify physical-world impact. It does not evaluate
private documents, medical data, beneficiary identities, photographs, or sensor
claims. Those require stronger identity, privacy, and source-authenticity systems.

## 2. Product Promise

> Fund public-good work upfront, release it only after independently executed
> Somnia Agents verify the agreed public evidence.

The core loop is:

1. Define milestones.
2. Fund escrow.
3. Submit public evidence.
4. Run Somnia Agent checks.
5. Open a challenge period.
6. Release or resolve.

## 3. Why This Product Is Distinct

Existing systems cover parts of the workflow:

- Gitcoin helps programs allocate grant funding.
- Optimism Retro Funding rewards work after humans evaluate impact.
- Hypercerts creates structured records and evaluations of impact.
- Kleros provides human arbitration for disputed escrow.
- Attestation protocols record signed claims.

ImpactOS combines forward-funded escrow, machine-verifiable evidence, deterministic
agent decisions, challenge periods, and automatic settlement.

It should complement these systems rather than recreate them. Later versions can
publish ImpactOS verdicts as portable attestations or Hypercert evaluations.

## 4. V1 Scope

### Included

- One payment asset: official Somnia USDC.
- One verification template: GitHub pull-request milestone.
- Multiple milestones per grant.
- Public GitHub repositories only.
- Two independent Somnia Agent checks per submission.
- Fixed protocol-owned prompts and decision rules.
- Challenge period before payment.
- Manual resolution for challenged or inconclusive results.
- Permissionless finalization after deadlines.
- Public audit page for every grant and verification request.

### Excluded

- Arbitrary user-created agent prompts.
- Arbitrary websites or API domains.
- Private GitHub repositories.
- Physical-world impact verification.
- DAO voting.
- Tradable impact tokens or NFTs.
- Yield generation on escrowed funds.
- Cross-chain escrow.
- Public juror markets.
- Automatic payment directly inside an agent callback.
- Upgradeable proxy contracts.

## 5. Actors

- Funder: creates and funds a grant.
- Grantee: performs work and submits evidence.
- Somnia Agents: retrieve and evaluate public evidence.
- Challenger: initially the funder; challenges a proposed approval.
- Resolver: independent multisig that decides disputed milestones.
- Guardian: multisig that can pause unsafe operations.
- Keeper: any account that finalizes expired challenge periods or timeouts.

The ImpactOS operator must never be able to withdraw grant principal.

## 6. Verification Policy

Each V1 milestone freezes the following when funded:

- GitHub repository owner and name.
- Expected base branch.
- Acceptance criteria hash and public URI.
- Payout amount.
- Submission deadline.
- Challenge period.

The grantee submits:

- Pull-request number.
- Evidence manifest hash and URI.

The acceptance-criteria text is canonicalized and size-limited. It can be supplied
again when verification starts, but the contract must reject it unless its hash
matches the value frozen when the milestone was funded.

The verifier runs two checks.

### Check A: Objective GitHub API Check

Use the Somnia JSON API Request agent to read the public GitHub REST response.

The contract constructs the GitHub API URL from the repository frozen at funding
time and the submitted numeric pull-request ID. It does not accept an arbitrary URL.

The objective result is the API's `merged` boolean. Repository identity is guaranteed
by URL construction. Branch and acceptance-criteria checks are handled by the
semantic check.

The objective check must pass before semantic approval is possible.

### Check B: Semantic Acceptance Check

Use the Somnia LLM Parse Website agent against the public pull-request page.

The extraction is constrained to:

- `PASS`
- `FAIL`
- `REVIEW`

The protocol supplies the prompt template. User content is clearly delimited and
treated as untrusted evidence, not as instructions. The confidence threshold should
start at 80.

The agent evaluates whether the visible change description and linked public
artifacts address the frozen acceptance criteria and target the expected base branch.

### Combined Decision

| Objective check | Semantic check | Result |
| --- | --- | --- |
| Pass | PASS | Proposed approval |
| Pass | REVIEW | Manual review |
| Pass | FAIL | Manual review |
| Fail | Any | Manual review |
| Timeout/failure | Any | Retry or manual review |

An agent result never causes an immediate transfer.

## 7. Somnia Integration

Current agent IDs:

- JSON API Request: `13174292974160097713`
- LLM Inference: `12847293847561029384`
- LLM Parse Website: `12875401142070969085`

Current SomniaAgents platform addresses:

- Mainnet: `0x5E5205CF39E766118C01636bED000A54D93163E6`
- Testnet: `0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776`

Current practical default request costs for a three-validator subcommittee:

- JSON API Request: about `0.12 SOMI/STT`.
- LLM Inference: about `0.24 SOMI/STT`.
- LLM Parse Website: about `0.33 SOMI/STT`.

These prices are not permanent. Deployment configuration must hold agent IDs,
platform addresses, subcommittee settings, and price buffers. The application must
read the platform reserve helpers instead of hardcoding the full request deposit.

### Consensus

Use majority consensus for V1 because both selected agents are intended to produce
deterministic, byte-identical outputs.

Default configuration:

- Subcommittee size: 3
- Threshold: 2
- Consensus: Majority
- Timeout: platform default initially

Move to 3-of-5 only after measuring mainnet reliability and cost.

### Callback Rules

Every callback must:

- Require `msg.sender` to be the configured SomniaAgents platform.
- Map the request ID to exactly one milestone and verification attempt.
- Reject unknown, stale, duplicate, or already-consumed requests.
- Handle `Success`, `Failed`, and `TimedOut`.
- Check response length before decoding.
- Validate decoded values against allowed outputs.
- Store the result before making any external call.
- Never transfer grant funds.

The adapter must implement `receive()` because Somnia pushes request rebates.

## 8. Contract Architecture

Keep the protocol to two production contracts.

### ImpactEscrow

Responsibilities:

- Hold official Somnia USDC.
- Create grants and milestones.
- Freeze milestone configuration when funded.
- Track evidence and verdict states.
- Open and close challenge periods.
- Record claimable balances.
- Allow grantees and funders to withdraw their own claimable balances.
- Route verification requests through the authorized verifier adapter.
- Pause new grants, submissions, and verifications during emergencies.

It must not:

- Parse agent responses.
- Store full evidence documents.
- Call arbitrary external targets.
- Allow administrators to seize escrowed principal.

### SomniaVerificationAdapter

Responsibilities:

- Encode Somnia Agent requests.
- Fund requests from a milestone's SOMI verification reserve.
- Track request IDs and attempts.
- Decode callbacks.
- Combine objective and semantic results.
- Submit a bounded verdict to ImpactEscrow.
- Accept and account for Somnia rebates.

The adapter isolates ImpactEscrow from the prototype agent interface. A replacement
adapter can be authorized through a delayed multisig operation if Somnia changes the
API. Existing pending requests must be completed or cancelled before replacement.

### No Proxy in V1

ImpactEscrow should be immutable. This reduces governance and upgrade risk.

If V2 is required:

- Pause new V1 grants.
- Complete or mutually unwind active V1 grants.
- Deploy V2.
- Let users migrate voluntarily.

## 9. State Machine

### Grant

- `Active`
- `Completed`
- `Cancelled`

### Milestone

- `Pending`
- `Verifying`
- `ProposedApproval`
- `ManualReview`
- `Disputed`
- `Claimable`
- `Paid`
- `Refundable`
- `Refunded`

Important transitions:

```text
Pending -> Verifying
Verifying -> ProposedApproval
Verifying -> ManualReview
ProposedApproval -> Claimable
ProposedApproval -> Disputed
Disputed -> Claimable
Disputed -> Refundable
Claimable -> Paid
Refundable -> Refunded
```

Transitions must be explicit and tested. There must be no generic administrative
function that writes an arbitrary state.

## 10. Funds

### Grant Principal

Use official Somnia USDC:

`0x28bec7e30e6faee657a03e19bf1128aad7632a00`

Use OpenZeppelin `SafeERC20` and pull-based withdrawals.

### Verification Reserve

The funder deposits native SOMI separately from grant principal.

For each milestone, quote:

- Objective request reserve and reward.
- Semantic request reserve and reward.
- Retry buffer.

Unused request funds and Somnia rebates return to the milestone verification reserve.
Unused verification reserve becomes refundable to the funder after grant completion.

USDC principal and SOMI verification funds must have separate accounting.

## 11. Challenge and Resolution

Default challenge period: 48 hours.

During the challenge period, the funder may challenge a proposed approval by posting
a small USDC dispute bond.

The resolver can choose:

- Approve: milestone becomes claimable by the grantee.
- Reject: milestone becomes refundable to the funder.

V1 should not support percentage splits. Binary decisions keep the contract and
policy easier to audit.

The resolver is a 2-of-3 Safe with published identities and a written resolution
policy. It cannot touch undisputed funds.

Later, the resolver interface can be adapted to Kleros or another ERC-792 arbitrator.

## 12. Evidence and Auditability

Only minimal authoritative data belongs onchain:

- Acceptance criteria hash.
- Evidence manifest hash.
- Evidence URI.
- Agent request IDs.
- Agent result codes.
- Verification attempt number.
- Challenge and resolution events.

The evidence manifest should use canonical JSON and include:

- Schema version.
- Grant and milestone IDs.
- Repository and pull-request URL.
- Reported commit SHA, when available.
- Submitter address.
- Submission timestamp.

The full manifest should be pinned to at least two independent storage providers.

Somnia receipts are useful for debugging but are currently stored in public Google
Cloud Storage and receipt steps are not consensus outputs. Therefore:

- Payment decisions rely on onchain consensus results, not receipt contents.
- A worker mirrors receipt files to content-addressed storage.
- The mirrored receipt hash is added to the public audit index.
- Missing receipts must never block settlement.

## 13. Application Architecture

### Web Application

- Next.js with TypeScript.
- viem and wagmi for chain interaction.
- Wallet-based authentication.
- Four primary screens:
  - Explore grants.
  - Create and fund grant.
  - Grant workspace.
  - Public verification audit page.

No chat interface is required.

### Indexer and Worker

A small TypeScript service:

- Indexes contract events into PostgreSQL.
- Tracks pending agent requests.
- Fetches and mirrors receipts.
- Sends notifications.
- Reports stale requests and low verification reserves.

It has no signing authority over grant funds. Permissionless contract methods remain
available if the worker is offline.

### Source of Truth

- Contracts: balances, state, deadlines, and verdicts.
- Content-addressed storage: evidence manifests and mirrored receipts.
- PostgreSQL: disposable query cache and notification state.

## 14. Security Model

### Primary Risks

- Forged or mutable evidence.
- Prompt injection from pull-request content.
- Duplicate or spoofed callbacks.
- Agent timeout or inconsistent responses.
- GitHub API rate limits or schema changes.
- Reentrancy or double payment.
- Compromised administrator or resolver.
- Incorrect USDC/Somnia contract configuration.
- Agent platform API changes.

### Controls

- Allow only approved domains in V1.
- Freeze repository and acceptance criteria before funding.
- Require immutable commit SHAs.
- Use fixed protocol prompts and constrained outputs.
- Cross-check semantic output with objective API facts.
- Never pay in a callback.
- Require challenge delay before settlement.
- Use pull payments and `ReentrancyGuard`.
- Use `Pausable` for unsafe entry points.
- Use a Safe multisig for guardian and resolver roles.
- Delay verifier-adapter replacement.
- Pin compiler and dependency versions.
- Verify deployment bytecode on the explorer.
- Monitor all privileged-role and configuration events.

Deterministic AI means validators can agree on a result. It does not prove that the
source data is honest or that the model's interpretation is correct.

## 15. Testing Strategy

### Unit Tests

- Every valid and invalid state transition.
- Access-control boundaries.
- Agent callback validation.
- Retry and timeout behavior.
- Challenge and dispute behavior.
- USDC and SOMI accounting.
- Pause behavior.

### Fuzz Tests

- Milestone amounts and deadlines.
- Callback ordering.
- Repeated submissions and retries.
- Challenge timing boundaries.
- Withdrawal sequences.

### Invariant Tests

- No milestone is paid twice.
- Total principal equals escrowed plus claimable plus paid/refunded amounts.
- Admins cannot withdraw grant principal.
- A failed, timed-out, unknown, or stale agent request cannot approve a milestone.
- A challenged milestone cannot become claimable without resolution.
- Pausing does not trap already claimable withdrawals.

### Integration Tests

- Mock SomniaAgents contract for deterministic CI.
- Shannon testnet tests with all three response statuses.
- Real JSON API and Parse Website requests.
- Receipt fetch and mirror workflow.
- Mainnet fork tests for official USDC behavior.

### Release Gates

- 100% branch coverage on fund-moving contract paths.
- Static analysis with Slither.
- Independent external smart-contract audit.
- Public testnet period.
- Incident-response rehearsal.
- Bug bounty before increasing escrow limits.

## 16. Deployment and Operations

### Administration

- Guardian: 2-of-3 Safe.
- Resolver: separate 2-of-3 Safe.
- Deployment keys: hardware-backed and not retained as privileged EOAs.
- Privileged changes: delayed and publicly announced.

### Monitoring

Alert on:

- Agent timeouts and failure rates.
- Verification requests pending beyond deadline.
- Low SOMI verification reserves.
- Unexpected callback senders.
- Pauses and role changes.
- USDC accounting mismatches.
- Receipt-service unavailability.

### Rollout Limits

Production-ready does not mean unlimited on day one.

Suggested mainnet stages:

1. Capped pilot: maximum 1,000 USDC per grant and allowlisted funders.
2. Public beta: maximum 10,000 USDC per grant after audit fixes.
3. General availability: limits raised only after operational history and a bug bounty.

## 17. Legal and Policy Gate

Before taking fees or operating a resolver, obtain jurisdiction-specific legal advice.
Whether an operator is treated as a money transmitter or virtual-asset service
provider depends on facts such as custody, control, and acting on behalf of users.

The technical design reduces operator control:

- Funds move according to user-created escrow terms.
- The operator cannot withdraw principal.
- The frontend is not required to settle grants.
- No new speculative token is issued.

These design choices reduce risk but do not replace legal analysis.

## 18. Delivery Phases

### Phase 0: Technical Spike

- Invoke JSON API and Parse Website agents on Shannon.
- Confirm callbacks, failure modes, deposits, rebates, and receipts.
- Verify GitHub endpoints remain stable across validators.
- Measure end-to-end latency and cost.

Exit criterion: repeated end-to-end agent runs succeed with recorded failure rates.

### Phase 1: Contract Core

- Implement ImpactEscrow.
- Implement SomniaVerificationAdapter.
- Add complete unit, fuzz, invariant, and mock integration tests.

Exit criterion: all accounting and state invariants hold in CI.

### Phase 2: Product

- Build grant creation and funding flow.
- Build evidence submission.
- Build verification timeline and public audit page.
- Build indexer, receipt mirror, and notifications.

Exit criterion: a non-developer can create, fund, verify, challenge, and settle a grant.

### Phase 3: Hardening

- Shannon public pilot.
- External audit.
- Fix audit findings.
- Run incident and pause drills.
- Publish resolver policy, threat model, and contract documentation.

Exit criterion: no unresolved high or critical findings.

### Phase 4: Mainnet Pilot

- Deploy verified contracts.
- Start with allowlisted funders and escrow caps.
- Monitor agent reliability and dispute frequency.
- Publish a transparent status page and postmortems.

Exit criterion: stable operation through a meaningful number of completed milestones.

### Phase 5: Expansion

Add verification templates one at a time:

- Package release.
- Deployment health and version.
- Onchain usage metrics.
- Education credentials.
- Environmental or humanitarian evidence only after source-authenticity and privacy
  designs are independently reviewed.

## 19. Production Definition

ImpactOS V1 is production ready when:

- Real USDC can be escrowed without operator custody.
- Every fund-moving path is audited and invariant-tested.
- Agent failures lead to retry or review, never accidental payment.
- Evidence, verdicts, and disputes are publicly traceable.
- Users can settle grants without the ImpactOS backend.
- Admin keys are multisig-controlled and cannot seize principal.
- Monitoring and incident procedures are active.
- Legal review covers the initial launch model and jurisdictions.

This is the smallest version that can responsibly handle real funds while using
Somnia Agents as a core verification mechanism.

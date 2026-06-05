# Live Agent Verification Fixture

This pull request is a public evidence fixture for the first ImpactOS Shannon
test.

While the pull request is open, Somnia's JSON API Agent should read GitHub's
`merged` field as `false`. After merge, a second request against the same pull
request should resolve it as `true`.

The two results prove that ImpactOS can:

1. Submit public evidence to the Somnia Agents platform.
2. Receive an authenticated asynchronous consensus callback.
3. Persist an auditable verification result on Shannon.

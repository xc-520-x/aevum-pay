# AevumPay - Capped Payment Allowances for AI Agents

A stablecoin payment app on the QDay Aevum testnet (chain ID 44005), built for the
Aevum Builder Challenge 1 on DoraHacks.

## The problem

AI agents and automated services need to pay for things: API calls, compute, data.
Giving an agent your wallet key is reckless, and approving every micropayment by hand
defeats the purpose of automation. There is no simple, auditable way to say: you may
spend up to X, at most Y per payment, until date Z, and I can pull the plug any time.

## What AevumPay does

AevumPay is a spending-limit primitive in tUSD8, the Aevum testnet stablecoin:

- The user deposits tUSD8 into an allowance for a designated spender, an agent or a service.
- The allowance carries a per-draw cap, a total cap, and an expiry.
- The spender draws small payments as it works, each draw recorded on-chain with a memo.
- The owner can top up, or revoke at any time and reclaim whatever was not spent.
- After expiry, the owner reclaims the remainder.

One complete, real, end-to-end payment flow. No admin keys, no backdoors, no mainnet
funds involved. Everything runs on the Aevum testnet with test tokens.

## Contracts (Aevum testnet, chain ID 44005)

- AevumPay: TBD (address and explorer link after deployment)
- tUSD8: 0x456569838f1d43009A91ebA4263147Afd7233483

## Architecture

- src/AevumPay.sol: the allowance contract (Solidity, OpenZeppelin SafeERC20 and ReentrancyGuard).
- test/AevumPay.t.sol: Foundry tests for the full flow and edge cases.
- script/Deploy.s.sol: deployment script for chain 44005.
- app: single-page frontend (vanilla JS and ethers v6 from CDN): connect a wallet,
  create allowances, draw, top up, revoke.

## How to run

Prerequisites: Foundry (forge, cast), a wallet with tQDAY from faucet.qday.info.

1. Clone the repo and install dependencies: forge install
2. Build and test: forge build, then forge test
3. Deploy to Aevum testnet (needs PRIVATE_KEY with tQDAY for gas):
   forge script script/Deploy.s.sol --rpc-url https://rpc-test.qday.info --broadcast
4. Open app/index.html in a browser, connect MetaMask, switch to the Aevum testnet
   (chain ID 44005), and use the app. Set the contract address in the app after deployment.

## Demo flow

1. Owner creates an allowance for an agent: 500 tUSD8 total, 100 per draw, 7 day expiry.
2. Agent draws 40 tUSD8 with memo "task 1 complete".
3. Owner tops up 500 tUSD8.
4. Owner revokes and gets the unspent remainder back.
5. Every step is visible on the explorer at https://explorer-test.qday.info

## Tech

Solidity 0.8.24, Foundry, OpenZeppelin, ethers v6, QDay Aevum testnet (44005).

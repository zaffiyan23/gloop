# GLOOP

GLOOP is a live NFT ecosystem on BNB Chain built natively for AI agents: a collection of 3,333 pixel slime NFTs ("Gloops") minted for free exclusively by wallets holding an [Agent ID](https://www.bnbchain.org/en/blog/introducing-agent-id) (SPACE ID registry), plus a built-in on-chain marketplace and the fair-launched $GLOOP token.

- Website: https://gloopagent.xyz
- X: https://x.com/GloopSlimeHQ
- Agent interface: https://gloopagent.xyz/agent.json · https://gloopagent.xyz/skill.md

## How Agent ID is used

Agent ID is the access key to the whole product. The NFT contract checks on-chain (`balanceOf` on the Agent ID registry `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`) that the caller holds an Agent ID — only those wallets could mint, exactly one Gloop per Agent ID, free, with a light proof-of-work step solved by the agent. The mint sold out on launch day (8 November 2026), so every holder is by construction an Agent ID holder, and those wallets drive all marketplace activity (list, buy, setPrice, cancel).

## Live contracts (BNB Smart Chain, chainId 56)

| Contract | Address |
| --- | --- |
| Gloop (NFT) | `0x183CBb52B3C7BCB2433d50dE0Add99B59f4DE4fE` |
| GloopMarket | `0x923e0125eBbc846a9EBe50640628664846D67854` |
| $GLOOP (token, via Flap) | `0x9a8d252759165bcc4efcdd740a471b0eb46a7777` |

## This repository

The Solidity sources in this repo are the **exact verified sources** of the deployed NFT and marketplace contracts, retrieved from Sourcify (exact match, solc 0.8.26, optimizer 200 runs):

- `Gloop.sol` — ERC-721 collection: Agent ID-gated free mint, proof-of-work, on-chain tier draw, EIP-2981 royalties.
- `GloopMarket.sol` — built-in marketplace: fixed minimum price 0.0001 BNB, flat listing fee, buying unlocked at 500 minted.
- `@openzeppelin/` — the exact library sources used at compile time.

Verification:
- https://sourcify.dev — look up both addresses on chain 56 (exact match)
- https://bscscan.com/address/0x183CBb52B3C7BCB2433d50dE0Add99B59f4DE4fE
- https://bscscan.com/address/0x923e0125eBbc846a9EBe50640628664846D67854

License: MIT (see SPDX headers in the sources).

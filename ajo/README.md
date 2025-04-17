# Stacks Vesting Protocol 

A secure, flexible token vesting system built on the Stacks blockchain using Clarity smart contracts.

## Overview

Stacks Vesting Protocol (SVP) is a blockchain-based token vesting system that enables secure, transparent, and verifiable token distribution with sequential release schedules. Built on the Stacks blockchain, SVP leverages Clarity's predictable and secure programming model to ensure reliable token vesting operations.

## Features

- **Sequential Vesting Schedules**: Create and manage multiple vesting schedules with different unlock epochs
- **Identity Verification**: Secure token claims through cryptographic identity proofs
- **KYC Integration**: Built-in KYC verification process for beneficiaries
- **Epoch-Based Releases**: Time-locked token distribution based on blockchain epochs
- **Comprehensive Tracking**: Complete history of claims and distribution events
- **Treasury Management**: Secure control of token distribution by authorized managers

## Smart Contract Functions

### Management Functions

- `initialize-vesting`: Activate the vesting system
- `update-epoch`: Update the current epoch for vesting calculations
- `create-schedule`: Create a new vesting schedule with parameters

### Beneficiary Functions

- `complete-kyc`: Register as a beneficiary after KYC verification
- `claim-tokens`: Claim tokens from an active schedule with identity verification

### Read-Only Functions

- `get-schedule-description`: View details of a specific schedule
- `get-beneficiary-status`: Check a beneficiary's current status
- `get-claim-events`: View claim history for a schedule
- `get-current-epoch`: Get the current vesting epoch
- `get-vesting-stats`: View overall vesting statistics

## Implementation Example

```clarity
;; Create a new vesting schedule
(contract-call? .token-vesting create-schedule 
    u1                                  ;; schedule-id
    "Seed Round Investors - Month 1"    ;; description
    0x8a9d...                           ;; identity-proof hash
    u100                                ;; unlock-epoch
    u1000000000)                        ;; token-amount
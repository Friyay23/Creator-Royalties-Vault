# 🎵 Creator Royalties Vault

A smart contract that locks in royalty streams for actors, musicians, and creators with transparent splits on the Stacks blockchain.

## 🌟 Features

- 🔒 **Secure Royalty Locking**: Lock royalty payments until a specified block height
- 💰 **Transparent Splits**: Define percentage-based royalty distributions 
- 🎭 **Multi-Creator Support**: Support up to 20 recipients per vault
- 📊 **Real-time Tracking**: Monitor deposits, withdrawals, and earnings
- 🛡️ **Emergency Controls**: Creator can withdraw funds in emergencies
- ⚡ **Gas Efficient**: Optimized for minimal transaction costs

## 🚀 Quick Start

### Prerequisites
- Clarinet CLI installed
- Stacks wallet with STX tokens

### Installation

```bash
git clone https://github.com/yourusername/Creator-Royalties-Vault
cd Creator-Royalties-Vault
clarinet check
```

## 📋 Usage

### Creating a Vault

```clarity
;; Create a new royalty vault locked for 1000 blocks
(contract-call? .Creator-Royalties-Vault create-vault "My Album Royalties" u1000)
```

### Adding Recipients

```clarity
;; Add a recipient with 25% royalty share (2500 basis points)
(contract-call? .Creator-Royalties-Vault add-royalty-recipient u1 'SP1RECIPIENT u2500)

;; Add multiple recipients
(contract-call? .Creator-Royalties-Vault add-royalty-recipient u1 'SP2RECIPIENT u5000)
(contract-call? .Creator-Royalties-Vault add-royalty-recipient u1 'SP3RECIPIENT u2500)
```

### Depositing Royalties

```clarity
;; Deposit STX tokens to the vault
(contract-call? .Creator-Royalties-Vault deposit-royalty u1)
```

### Withdrawing Royalties

```clarity
;; Withdraw your earned royalties (after lock period expires)
(contract-call? .Creator-Royalties-Vault withdraw-royalty u1)
```

## 🔧 Functions

### Public Functions

| Function | Description | Parameters |
|----------|-------------|------------|
| `create-vault` | Create a new royalty vault | `title`, `locked-blocks` |
| `add-royalty-recipient` | Add recipient to vault | `vault-id`, `recipient`, `percentage` |
| `deposit-royalty` | Deposit STX to vault | `vault-id` |
| `withdraw-royalty` | Withdraw earned royalties | `vault-id` |
| `emergency-withdraw` | Creator emergency withdrawal | `vault-id` |
| `update-vault-status` | Enable/disable vault | `vault-id`, `is-active` |

### Read-Only Functions

| Function | Description | Parameters |
|----------|-------------|------------|
| `get-vault-info` | Get vault details | `vault-id` |
| `get-royalty-split` | Get recipient split info | `vault-id`, `recipient` |
| `get-vault-recipients` | List all vault recipients | `vault-id` |
| `get-user-vaults` | Get user's vault IDs | `creator` |
| `calculate-royalty-amount` | Calculate recipient's share | `vault-id`, `recipient` |

## 💡 Example Workflow

### 🎤 Musician Creates Album Vault

```clarity
;; 1. Create vault for album royalties
(contract-call? .Creator-Royalties-Vault create-vault "Album: Midnight Dreams" u14400) ;; ~100 days

;; 2. Add band members and producer
(contract-call? .Creator-Royalties-Vault add-royalty-recipient u1 'SP1GUITARIST u3000)   ;; 30%
(contract-call? .Creator-Royalties-Vault add-royalty-recipient u1 'SP1DRUMMER u2000)     ;; 20% 
(contract-call? .Creator-Royalties-Vault add-royalty-recipient u1 'SP1BASSIST u2000)     ;; 20%
(contract-call? .Creator-Royalties-Vault add-royalty-recipient u1 'SP1PRODUCER u1500)    ;; 15%
;; Creator keeps 15%
```

### 🎬 Actor Creates Movie Vault

```clarity
;; 1. Create vault for movie royalties
(contract-call? .Creator-Royalties-Vault create-vault "Movie: Space Odyssey" u28800) ;; ~200 days

;; 2. Add co-stars and director
(contract-call? .Creator-Royalties-Vault add-royalty-recipient u2 'SP1COSTAR u4000)    ;; 40%
(contract-call? .Creator-Royalties-Vault add-royalty-recipient u2 'SP1DIRECTOR u3000)  ;; 30%
;; Lead actor keeps 30%
```

## 🔒 Security Features

- ✅ **Access Control**: Only vault creators can add recipients
- ✅ **Time Locks**: Prevent early withdrawals with block-height locks
- ✅ **Percentage Validation**: Ensures splits don't exceed 100%
- ✅ **Emergency Controls**: Creator can recover funds if needed
- ✅ **Duplicate Prevention**: Prevents duplicate recipient entries

## 📊 Data Structures

### Vault Structure
```clarity
{
  creator: principal,
  title: (string-ascii 64),
  total-balance: uint,
  locked-until: uint,
  is-active: bool
}
```

### Royalty Split Structure
```clarity
{
  percentage: uint,        ;; Basis points (10000 = 100%)
  total-earned: uint      ;; Cumulative earnings
}
```

## 🛠️ Development

### Testing

```bash
clarinet test
```

### Local Development

```bash
clarinet console
```

### Deployment

```bash
clarinet deploy --network testnet
```

## 📈 Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| u400 | `ERR-INVALID-AMOUNT` | Invalid amount provided |
| u401 | `ERR-UNAUTHORIZED` | Unauthorized access |
| u402 | `ERR-INSUFFICIENT-BALANCE` | Insufficient balance |
| u403 | `ERR-INVALID-PERCENTAGE` | Invalid percentage value |
| u404 | `ERR-VAULT-NOT-FOUND` | Vault doesn't exist |
| u409 | `ERR-ALREADY-EXISTS` | Recipient already exists |
| u422 | `ERR-INVALID-RECIPIENT` | Invalid recipient |
| u423 | `ERR-VAULT-LOCKED` | Vault is locked |

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details

## 🔗 Links

- [Stacks Documentation](https://docs.stacks.co/)
- [Clarity Language Reference](https://docs.stacks.co/clarity/)
- [Clarinet Documentation](https://github.com/hirosystems/clarinet/)

---

Made with ❤️ for creators everywhere 🎨

# node7-banking

Full-screen personal, society, gang, business, and shared banking for the NODE7 RedM Framework.

## Version 2.2.1 — Custom Amount Fix

This release keeps the migration-fixed banking backend and repairs personal/shared amount submission while upgrading the full-screen newspaper cashier experience.

### Reliability fix

- Amount values are captured before UI controls are disabled
- Fixes deposits and withdrawals incorrectly returning “Enter a valid amount”
- Server accepts clean numeric values and safely normalizes commas, spaces, and currency symbols
- Client validates available cash, personal bank funds, and shared-account funds before submission

### Interface

- Full-screen paper/newspaper banking UI
- No dropdown menus
- Visible account cards for society, gang, and shared accounts
- Button-based banking sections
- Card-based member authority selection
- Newspaper masthead, account headlines, classified transaction forms, and printed ledgers
- Personal cash, bank, and gold displayed across the top
- Escape key and visible close control
- Responsive support for narrower resolutions
- Quick amount buttons and full-balance actions
- Live available-balance labels on deposit, withdrawal, transfer, and shared-account forms
- Clear inline validation instead of generic transaction failures

### Banking

- Core-owned personal cash, bank, and gold balances
- Personal deposits, withdrawals, and offline/online transfers
- Personal transaction history
- Society and gang accounts
- Player-created shared accounts
- Unique shared account numbers
- Owner, manager, member, and viewer permissions
- Shared deposits, withdrawals, and personal/shared transfers
- Member management and account renaming
- Shared transaction ledgers
- Account freezing and ACE-protected administration
- Automatic migration for older NODE7 banking tables

## Dependencies

- `ox_lib`
- `oxmysql`
- `node7-core`

## Startup order

```cfg
ensure ox_lib
ensure oxmysql
ensure node7-core
ensure node7-banking
ensure node7-inventory
```

## Installation

1. Replace the existing `node7-banking` folder with this release.
2. Keep the resource folder name exactly `node7-banking`.
3. Merge `recipe/permissions.cfg` into the server permissions configuration once.
4. Start or restart the resource:

```text
restart node7-banking
```

## Important

Personal currency remains authoritative in `node7-core`. This resource does not move cash, bank, or gold ownership into the inventory or banking database. Banking tables store shared balances, memberships, and transaction records only.

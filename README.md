[README.md](https://github.com/user-attachments/files/30387428/README.md)
# node7-banking

Full-screen personal, society, gang, business, and shared banking for the NODE7 RedM Framework.




<img width="1508" height="1053" alt="drawtextbanking" src="https://github.com/user-attachments/assets/dc5520ad-2b88-49c0-9157-7feab8bfa4f9" />


<img width="1915" height="1076" alt="bankingbitch" src="https://github.com/user-attachments/assets/dd4c0963-0d3b-4176-9fca-4ac9104bf7db" />


## Version 2.1.0 — Frontier Banking Gazette UI

This release retains the migration-fixed 2.0.1 banking backend and replaces the interface with a full-screen Red Dead newspaper presentation.

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

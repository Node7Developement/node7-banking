[README.md](https://github.com/user-attachments/files/30681104/README.md)

# node7-banking







[README.md](https://github.com/user-attachments/files/30814211/README.md)
<img width="1916" height="1076" alt="bankingupdate" src="https://github.com/user-attachments/assets/c6d1354a-d8f8-48f3-a9e4-09e2f2efda3f" />


<img width="1920" height="1080" alt="bankinggggggg" src="https://github.com/user-attachments/assets/43051d10-1fce-4c4d-a5e0-d40480b45233" />






<img width="1920" height="1080" alt="BANKINGGGGGGGGG" src="https://github.com/user-attachments/assets/58d69356-ceb6-41fd-9706-b18fcf06d69b" />



NODE7 personal, society, gang, and shared banking using the central `node7-ui` resource.

## UI integration

This resource contains no standalone HTML, CSS, JavaScript, `ui_page`, NUI focus, or banking NUI callbacks. Every banking screen, modal, notification, action, and form is routed through `node7-ui` exports and events.

Included interface flows:

- Personal cash, bank, gold, and account-number overview# node7-banking

NODE7 personal, society, gang, and shared banking using the central `node7-ui` resource.

## UI integration

This resource contains no standalone HTML, CSS, JavaScript, `ui_page`, NUI focus, or banking NUI callbacks. Every banking screen, modal, notification, action, and form is routed through `node7-ui` exports and events.

Included interface flows:

- Personal cash, bank, gold, and account-number overview
- Deposit, withdrawal, and personal account transfer modals
- Personal transaction ledger
- Accessible society, gang, and private shared accounts
- Shared balance, permissions, deposits, withdrawals, and transfers
- Shared transaction ledger
- Private shared-account creation
- Shared member add/update/remove controls
- Shared account rename controls
- RedM-safe choice cards with no native dropdown menus

## Dependencies

```cfg
ensure ox_lib
ensure oxmysql
ensure node7-core
ensure node7-cashitem
ensure node7-ui
ensure node7-banking
```

## Database

Run `recipe/node7-banking.sql` before starting the resource. Existing tables and server banking logic are preserved.

## Interaction

Use the configured prompt at a bank or `/bank` while close enough to a configured bank location. Bankers, blips, prompts, server distance validation, transaction limits, fees, rate limiting, society exports, and admin commands remain supported.


## Multi-currency vault (v2.4.0)

Personal banking now supports the complete NODE7 currency set without changing `node7-core` money structure:

- Physical Canadian cash from `node7-cashitem`, including $1, $5, $10, $20, $50, and $100 bills plus quarters, dimes, nickels, and pennies.
- Gold Bars.
- Blood Money.
- Casino Chips.
- Bounty Vouchers.
- Prison Tokens.
- Saloon Tokens.
- Outlaw Marks.
- Company Scrip.

Cash deposits go into the existing personal `bank` balance. Every non-dollar currency is removed from the carried/core/item balance and stored server-side in `node7_bank_currency_balances`. Withdrawals reverse that operation. Failed operations refund/roll back the source side to prevent duplication or loss.

`node7-cashitem` is now a required dependency so physical bills, coins, Gold Bars, Outlaw Marks, and Company Scrip are read and changed through its server exports.


## 2.4.1
- Changed banking currency naming from U.S. Dollars to Canadian Dollars throughout the banking UI and transaction ledger.

- Deposit, withdrawal, and personal account transfer modals
- Personal transaction ledger
- Accessible society, gang, and private shared accounts
- Shared balance, permissions, deposits, withdrawals, and transfers
- Shared transaction ledger
- Private shared-account creation
- Shared member add/update/remove controls
- Shared account rename controls
- RedM-safe choice cards with no native dropdown menus

## Dependencies

```cfg
ensure ox_lib
ensure oxmysql
ensure node7-core
ensure node7-ui
ensure node7-banking
```

## Database

Run `recipe/node7-banking.sql` before starting the resource. Existing tables and server banking logic are preserved.

## Interaction

Use the configured prompt at a bank or `/bank` while close enough to a configured bank location. Bankers, blips, prompts, server distance validation, transaction limits, fees, rate limiting, society exports, and admin commands remain supported.

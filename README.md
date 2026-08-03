[README.md](https://github.com/user-attachments/files/30681104/README.md)

# node7-banking





<img width="1920" height="1080" alt="bankinggggggg" src="https://github.com/user-attachments/assets/43051d10-1fce-4c4d-a5e0-d40480b45233" />






<img width="1920" height="1080" alt="BANKINGGGGGGGGG" src="https://github.com/user-attachments/assets/58d69356-ceb6-41fd-9706-b18fcf06d69b" />



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
ensure node7-ui
ensure node7-banking
```

## Database

Run `recipe/node7-banking.sql` before starting the resource. Existing tables and server banking logic are preserved.

## Interaction

Use the configured prompt at a bank or `/bank` while close enough to a configured bank location. Bankers, blips, prompts, server distance validation, transaction limits, fees, rate limiting, society exports, and admin commands remain supported.

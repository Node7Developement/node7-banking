# NODE7 Banking Recipe

Install the SQL file, then start the shared NODE7 UI before banking:

```cfg
ensure node7-core
ensure node7-ui
ensure node7-banking
```

The banking resource does not ship or open its own NUI. All banking screens use `node7-ui` exports.


## v2.4.0 currency dependency

Ensure `node7-cashitem` starts before `node7-banking`. Banking uses its server exports for physical bills, coins, Gold Bars, Outlaw Marks, and Company Scrip. The SQL migration creates the personal multi-currency vault table automatically.

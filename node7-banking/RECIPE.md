# NODE7 Banking Recipe

Install the SQL file, then start the shared NODE7 UI before banking:

```cfg
ensure node7-core
ensure node7-ui
ensure node7-banking
```

The banking resource does not ship or open its own NUI. All banking screens use `node7-ui` exports.

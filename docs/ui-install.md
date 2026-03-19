# EurekaClaw UI Install

For a local app-like install experience, use:

```bash
./scripts/install-ui.sh
```

This script will:

- create a dedicated virtual environment at `.eurekaclaw-ui`
- install EurekaClaw with `openai` and `oauth` extras
- install bundled seed skills

Then launch the UI with:

```bash
.eurekaclaw-ui/bin/eurekaclaw ui --open-browser
```

You can also install directly with pip:

```bash
pip install "eurekaclaw[openai,oauth]"
eurekaclaw ui --open-browser
```

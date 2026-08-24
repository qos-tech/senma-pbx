# MAG PBX development harness

Copy these files into the MAG PBX repository root.

If `.gitignore` already exists, merge `.gitignore.harness-snippet` into it.

Then:

```bash
cp .env.example .env
make doctor
claude
```

Start with:

```text
/audit-legacy
/bootstrap-docker
```

The provided Docker files are an initial scaffold, not a claim that the legacy application
already runs on PHP 8.4. The first task is to audit the repository and adjust the compatibility
layer from evidence.

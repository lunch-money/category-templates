# Lunch Money category templates

Community-contributed category setups for [Lunch Money](https://lunchmoney.app).

Browse them at **[lunchmoney.app/category-templates](https://lunchmoney.app/category-templates)**.

This repository is the source of truth for that library. It contains data only — no
application code. When a change lands on `main`, an automated pull request updates the
marketing site, which renders the library as a static page.

## Contributing your setup

Read [CONTRIBUTING.md](CONTRIBUTING.md). The short version: append your setup to the end
of [`data/templates.yml`](data/templates.yml) and open a pull request. If you would rather
not use GitHub, email your setup to [team@lunchmoney.app](mailto:team@lunchmoney.app) and
we will add it for you.

## Using the data

The dataset is published as YAML and is free to use:

```
https://raw.githubusercontent.com/lunch-money/category-templates/main/data/templates.yml
```

The schema below is stable. We may add optional fields, but existing fields will not be
renamed or removed without a notice in the release notes.

## Schema

[`data/templates.yml`](data/templates.yml) is a list of templates, ordered oldest first.

| Field | Required | Description |
| --- | --- | --- |
| `id` | yes | Stable, unique slug. Lowercase words separated by single hyphens. Never change an existing id — it is used in links. |
| `title` | yes | Short, distinct name for the setup. |
| `author` | yes | How the contributor wants to be credited. |
| `description` | yes | What the setup is for and who it suits. Up to 600 characters. |
| `tags` | yes | One or more tags from [`data/tags.yml`](data/tags.yml). |
| `categories` | yes | The category list, in Lunch Money's import format. |
| `notes` | no | Extra context that does not belong in the description. |

### The `categories` block

This is the same format Lunch Money uses for importing categories, so it can be copied
straight out of the library and pasted into the app:

- One category per line.
- A leading `-` makes the line a subcategory of the closest line above it without a dash.
- A line with no dashes beneath it is a standalone category.
- Properties go in square brackets at the end of a line.

Valid properties are `income`, `exclude_from_budget`, and `exclude_from_totals`.

```yaml
categories: |
  Income [income]
  - Paycheck [income]
  - Interest [income]
  Housing
  - Rent
  - Utilities
  Groceries
  Transfers [exclude_from_budget, exclude_from_totals]
```

That example defines two groups (`Income`, `Housing`), one standalone category
(`Groceries`), and one standalone category excluded from budgets and totals
(`Transfers`).

### Tags

Tags come from the controlled vocabulary in [`data/tags.yml`](data/tags.yml), which groups
them into "Who it's for" and "Setup size". Reuse an existing tag when one fits; filters
are only useful when tags are shared across setups.

## Validating locally

Validation requires Ruby and uses only the standard library:

```sh
ruby scripts/validate.rb
```

The same check runs on every pull request. It verifies the schema, unique ids, known tags,
and the structure of each `categories` block.

## How changes reach the site

`main` is the only branch that publishes. On merge, the
[sync workflow](.github/workflows/sync-marketing-site.yml) revalidates the dataset,
regenerates the marketing site's Jekyll data files, and opens (or updates) a pull request
on `lunch-money/marketing-site`. Netlify builds a deploy preview of `/category-templates`
for that pull request; merging it ships the change.

To regenerate those files locally against a marketing-site checkout:

```sh
ruby scripts/render-marketing-data.rb ../marketing-site
```

The workflow needs a `MARKETING_SITE_TOKEN` repository secret — a token with `contents:write`
and `pull-requests:write` on `lunch-money/marketing-site`. Without it the sync job fails at
the checkout step; everything else in this repository still works.

## Licence

The dataset in `data/` is released under [CC0 1.0](LICENSE) — use it for anything, no
attribution required.

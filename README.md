# Lunch Money category templates

Community-contributed category setups for [Lunch Money](https://lunchmoney.app).

Browse them at **[lunchmoney.app/category-templates](https://lunchmoney.app/category-templates)**.

This repository is the source of truth for that library. It contains data only — no
application code. Maintainers sync published data to the marketing site via CI.

## Contributing your setup

Read [CONTRIBUTING.md](CONTRIBUTING.md). The short version: append your setup to the end
of [`data/templates.yml`](data/templates.yml) and open a pull request. If you would rather
not use GitHub, email your setup to [team@lunchmoney.app](mailto:team@lunchmoney.app) and
we will add it for you.

## Using the data

The dataset is published as YAML and is free to use under CC BY 4.0:

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
| `author` | yes | How the contributor wants to be credited. Keep and respect this value when reusing a template. |
| `description` | yes | What the setup is for and who it suits. Up to 240 characters. |
| `categories` | yes | The category list, in Lunch Money's import format. |
| `tags` | no | Optional template-library filters from [`data/tags.yml`](data/tags.yml). These are separate from Lunch Money transaction tags; setup size is derived automatically. |
| `in_their_words` | no | Longer contributor-written context shown when someone opens the setup. Up to 2,000 characters. |
| `notes` | no | Extra context that does not belong in the description. |
| `official` | no | Reserved for starter sets that ship with Lunch Money itself. Community templates omit it. |

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

Tags come from the controlled vocabulary in [`data/tags.yml`](data/tags.yml). They are
template-library filters, not Lunch Money transaction tags, and only audience tags are
stored on templates.

Reuse an existing audience tag when one fits; filters are only useful when tags are shared
across setups. Leave `tags` out rather than adding a one-off detail. Setup size ("Simple",
"Detailed" or "Comprehensive") is derived from the category count and should never be
listed in a template.

## Validating locally

Local validation is optional. If you have Ruby installed, this command gives you the same
checks as CI with a faster feedback loop:

```sh
ruby scripts/validate.rb
```

CI runs validation on every pull request and comments with any errors it finds. The check
verifies the schema, unique ids, known template tags, and the structure of each
`categories` block.

## How changes reach the site

`main` is the only branch that publishes. Maintainers sync published data to the
marketing site via CI after changes merge.

## Licence

This repository and its published dataset are licensed under the
[Creative Commons Attribution 4.0 International License](LICENSE).

When reusing the data, keep and respect each template's `author` field. That per-template
field is the attribution record for CC BY reuse.

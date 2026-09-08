# Contributing a category setup

Thanks for sharing how you organise your money. Real setups from real budgets are far more
useful than anything we could invent.

## What makes a good submission

- **A setup you actually use.** Aspirational category lists tend not to survive contact
  with a real month of transactions.
- **A description that helps someone self-select.** Who is this for, and what does it
  optimise for? "Zero-based budget that filters out reimbursable expenses" tells a reader
  much more than "my categories".
- **Tags that already exist.** Filters only work when setups share tags. A tag earns its
  place in the filter bar at roughly three setups; below that it returns a near-empty
  result. Detail that is true of only your setup belongs in the description instead.
- **No setup style tag.** Simple, Detailed and Comprehensive are worked out from how many
  categories your setup has, so there is nothing to pick and nothing to keep in sync.

## Submitting via pull request

1. Fork this repository.
2. Append your setup to the **end** of [`data/templates.yml`](data/templates.yml). Entries
   are ordered oldest first, so new submissions go at the bottom.
3. Run `ruby scripts/validate.rb` and fix anything it reports.
4. Open a pull request describing your setup in a sentence or two.

Validation also runs automatically on your pull request, so you do not need Ruby installed
locally — but it is a much faster feedback loop if you do.

## Submitting without GitHub

Email [team@lunchmoney.app](mailto:team@lunchmoney.app) with your category list, a name for
the setup, a short description, and how you would like to be credited. We will open the
pull request for you.

## The format

Copy this template and fill it in:

```yaml
- id: your-setup-name
  title: Your Setup Name
  author: How you want to be credited
  description: >-
    One or two sentences about what this setup is for and who it suits.
  tags:
    - Solo / single
    - Simple
  categories: |
    Income [income]
    - Paycheck [income]
    Housing
    - Rent
    - Utilities
    Groceries
    Transfers [exclude_from_budget, exclude_from_totals]
```

A complete, commented example lives in
[`examples/template.yml`](examples/template.yml).

### Field rules

- **`id`** — lowercase words separated by single hyphens, unique across the file. Pick it
  once and leave it alone; it is used in links to your setup.
- **`title`** — distinct from every other title in the file.
- **`author`** — a name, a handle, a first name and city, whatever you prefer. Use
  something you are happy to have published.
- **`description`** — up to 600 characters, written in complete sentences for someone
  deciding whether this setup fits their life. Say what the setup does and how it is
  organised, rather than answering "anything special about this?".
- **`tags`** — optional, all from the `audience` group in [`data/tags.yml`](data/tags.yml).
  Leave it out rather than reaching for a tag that does not really apply. If nothing fits,
  add a tag in the same pull request and say why. Setup style is derived, so it never
  appears here.
- **`categories`** — your category list in Lunch Money's import format (below).
- **`notes`** — optional, for context that does not belong in the description.

### Writing the categories block

Export or copy your categories one per line. A leading `-` makes a line a subcategory of
the nearest line above it that has no dash:

```yaml
categories: |
  Food
  - Groceries
  - Restaurants
  Rent
```

That is one group (`Food`, with two subcategories) and one standalone category (`Rent`).

Add properties in square brackets at the end of a line:

```yaml
categories: |
  Salary [income]
  Investments [exclude_from_budget, exclude_from_totals]
```

The three valid properties are `income`, `exclude_from_budget`, and
`exclude_from_totals`. They mean the same thing here as they do in the app.

### Things validation will reject

- A `categories` block that starts with a subcategory — the first line must be a
  top-level category.
- Duplicate ids or titles.
- Duplicate categories within the same group.
- Unknown properties or tags.
- Emoji-only or empty category names.

Emoji in category names are fine to include; the library strips them when displaying and
copying, so your setup reads cleanly for everyone.

## What happens after merge

Merging to `main` opens an automated pull request against the marketing site with the
regenerated dataset. Once that merges and deploys, your setup appears in the library.

## Removing your setup

Open a pull request deleting your entry, or email
[team@lunchmoney.app](mailto:team@lunchmoney.app). No justification needed.

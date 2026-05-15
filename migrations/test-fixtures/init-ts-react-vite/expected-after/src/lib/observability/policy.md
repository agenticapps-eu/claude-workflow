<!-- agenticapps:observability:start -->
# Observability policy — fixture-vite

Materialised by `/add-observability init`. See spec §10.5.

## Trivial errors

Errors classified as "trivial" — not surfaced as alerts, but still
emitted as low-severity events for trend analysis.

- HTTP 4xx-returning errors (client-side; expected behaviour)
- Validation errors (form submission shape mismatches)
- ResizeObserver loop limit exceeded (browser-side noise)

## Redacted attributes

Attribute key substrings that are redacted from emitted events before
they leave the browser.

- password
- token
- api_key
- card_number
- cvv
- ssn
- credit_card

## Project event names

<!-- add domain events here -->
<!-- agenticapps:observability:end -->

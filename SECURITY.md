# Security policy

Не публикуйте Adapty keys, backend URLs/tokens, product/placement IDs конкретного
app, receipts/JWS, user/payment data и raw SDK errors. Для уязвимости без
безопасного public reproduction используйте GitHub Security Advisory.

Financial boundaries fail closed: cache/remote flags не подтверждают purchase,
premium access или token fulfillment; timeout/offline не становятся
success/failure без authoritative result.

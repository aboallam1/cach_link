# Firestore Data Structure

## Collections

### users/{userId}
```json
{
  "name": "Ahmed Ali",
  "email": "ahmed@example.com",
  "phone": "+201234567890",
  "gender": "Male",
  "rating": 5.0,
  "createdAt": "2024-01-01T00:00:00Z",
  "updatedAt": "2024-01-01T00:00:00Z"
}
```

### wallets/{userId}
```json
{
  "balance": 10.50,
  "currency": "EGP",
  "lastUpdated": "2024-01-01T00:00:00Z",
  "totalDeposited": 50.00,
  "totalSpent": 39.50
}
```

### transactions/{transactionId}
```json
{
  "userId": "user123",
  "partnerUserId": "user456",
  "type": "Deposit", // or "Withdraw"
  "amount": 1000.0,
  "fee": 0.003,
  "status": "pending", // pending, accepted, completed, cancelled, rejected
  "location": {
    "lat": 30.0444,
    "lng": 31.2357
  },
  "createdAt": "2024-01-01T00:00:00Z",
  "updatedAt": "2024-01-01T00:00:00Z",
  "expiresAt": "2024-01-01T00:30:00Z",
  "feeDeducted": false,
  "partnerTxId": "transaction789"
}
```

### company_wallet/main
```json
{
  "balance": 1250.75,
  "currency": "EGP",
  "totalCollected": 1250.75,
  "lastUpdated": "2024-01-01T00:00:00Z"
}
```

### wallet_transactions/{transactionId}
```json
{
  "userId": "user123",
  "type": "fee_deduction", // fee_deduction, deposit, refund
  "amount": -0.003,
  "description": "Transaction fee for TX123",
  "relatedTransactionId": "TX123",
  "balanceBefore": 10.503,
  "balanceAfter": 10.500,
  "createdAt": "2024-01-01T00:00:00Z"
}
```

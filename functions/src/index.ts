import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

const TRANSACTION_FEE = 0.003;
const COMPANY_WALLET_ID = "main";

// Cloud Function to handle transaction status changes
export const onTransactionStatusChange = functions.firestore
  .document("transactions/{transactionId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const transactionId = context.params.transactionId;

    // Only process when status changes from non-accepted to accepted
    if (before.status !== "accepted" && after.status === "accepted") {
      try {
        await processTransactionFees(transactionId, after);
      } catch (error) {
        functions.logger.error("Error processing transaction fees:", error);
        
        // Revert transaction status on error
        await change.after.ref.update({
          status: "pending",
          error: "Failed to process fees. Please try again."
        });
      }
    }

    return null;
  });

async function processTransactionFees(
  transactionId: string, 
  transactionData: any
): Promise<void> {
  const { userId, partnerUserId, partnerTxId } = transactionData;

  if (!userId || !partnerUserId) {
    throw new Error("Missing user IDs in transaction");
  }

  // Use a batch to ensure atomicity
  const batch = db.batch();

  try {
    // Get both user wallets
    const userWalletRef = db.collection("wallets").doc(userId);
    const partnerWalletRef = db.collection("wallets").doc(partnerUserId);
    const companyWalletRef = db.collection("company_wallet").doc(COMPANY_WALLET_ID);
    
    const [userWallet, partnerWallet, companyWallet] = await Promise.all([
      userWalletRef.get(),
      partnerWalletRef.get(),
      companyWalletRef.get()
    ]);

    // Check if wallets exist and have sufficient balance
    const userBalance = userWallet.exists ? userWallet.data()?.balance || 0 : 0;
    const partnerBalance = partnerWallet.exists ? partnerWallet.data()?.balance || 0 : 0;
    const companyBalance = companyWallet.exists ? companyWallet.data()?.balance || 0 : 0;

    if (userBalance < TRANSACTION_FEE) {
      throw new Error(`User ${userId} has insufficient balance for fee`);
    }

    if (partnerBalance < TRANSACTION_FEE) {
      throw new Error(`Partner ${partnerUserId} has insufficient balance for fee`);
    }

    const now = admin.firestore.FieldValue.serverTimestamp();

    // Update user wallet
    if (userWallet.exists) {
      batch.update(userWalletRef, {
        balance: admin.firestore.FieldValue.increment(-TRANSACTION_FEE),
        totalSpent: admin.firestore.FieldValue.increment(TRANSACTION_FEE),
        lastUpdated: now
      });
    } else {
      throw new Error(`User ${userId} wallet not found`);
    }

    // Update partner wallet
    if (partnerWallet.exists) {
      batch.update(partnerWalletRef, {
        balance: admin.firestore.FieldValue.increment(-TRANSACTION_FEE),
        totalSpent: admin.firestore.FieldValue.increment(TRANSACTION_FEE),
        lastUpdated: now
      });
    } else {
      throw new Error(`Partner ${partnerUserId} wallet not found`);
    }

    // Update company wallet
    if (companyWallet.exists) {
      batch.update(companyWalletRef, {
        balance: admin.firestore.FieldValue.increment(TRANSACTION_FEE * 2),
        totalCollected: admin.firestore.FieldValue.increment(TRANSACTION_FEE * 2),
        lastUpdated: now
      });
    } else {
      batch.set(companyWalletRef, {
        balance: TRANSACTION_FEE * 2,
        currency: "EGP",
        totalCollected: TRANSACTION_FEE * 2,
        lastUpdated: now
      });
    }

    // Update main transaction
    const transactionRef = db.collection("transactions").doc(transactionId);
    batch.update(transactionRef, {
      status: "completed",
      feeDeducted: true,
      completedAt: now,
      updatedAt: now
    });

    // Update partner transaction if it exists
    if (partnerTxId) {
      const partnerTxRef = db.collection("transactions").doc(partnerTxId);
      batch.update(partnerTxRef, {
        status: "completed",
        feeDeducted: true,
        completedAt: now,
        updatedAt: now
      });
    }

    // Create wallet transaction records for audit trail
    const userWalletTxRef = db.collection("wallet_transactions").doc();
    batch.set(userWalletTxRef, {
      userId,
      type: "fee_deduction",
      amount: -TRANSACTION_FEE,
      description: `Transaction fee for ${transactionId}`,
      relatedTransactionId: transactionId,
      balanceBefore: userBalance,
      balanceAfter: userBalance - TRANSACTION_FEE,
      createdAt: now
    });

    const partnerWalletTxRef = db.collection("wallet_transactions").doc();
    batch.set(partnerWalletTxRef, {
      userId: partnerUserId,
      type: "fee_deduction",
      amount: -TRANSACTION_FEE,
      description: `Transaction fee for ${transactionId}`,
      relatedTransactionId: transactionId,
      balanceBefore: partnerBalance,
      balanceAfter: partnerBalance - TRANSACTION_FEE,
      createdAt: now
    });

    // Commit all changes atomically
    await batch.commit();

    functions.logger.info(`Successfully processed fees for transaction ${transactionId}`);

  } catch (error) {
    functions.logger.error(`Error in processTransactionFees: ${error}`);
    throw error;
  }
}

// Cloud Function to initialize user wallet
export const onUserCreate = functions.firestore
  .document("users/{userId}")
  .onCreate(async (snap, context) => {
    const userId = context.params.userId;
    
    // Create initial wallet for the user
    await db.collection("wallets").doc(userId).set({
      balance: 0.0,
      currency: "EGP",
      totalDeposited: 0.0,
      totalSpent: 0.0,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp()
    });

    functions.logger.info(`Created wallet for user ${userId}`);
    return null;
  });

// Cloud Function to handle wallet deposits (called by payment gateway webhooks)
export const processWalletDeposit = functions.https.onCall(
  async (data, context) => {
    // Verify authentication
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated"
      );
    }

    const { amount, paymentReference } = data;
    const userId = context.auth.uid;

    if (!amount || amount <= 0) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Invalid amount"
      );
    }

    try {
      const walletRef = db.collection("wallets").doc(userId);
      const walletTxRef = db.collection("wallet_transactions").doc();

      await db.runTransaction(async (transaction) => {
        const wallet = await transaction.get(walletRef);
        const currentBalance = wallet.exists ? wallet.data()?.balance || 0 : 0;

        const now = admin.firestore.FieldValue.serverTimestamp();

        // Update wallet balance
        transaction.set(walletRef, {
          balance: currentBalance + amount,
          currency: "EGP",
          totalDeposited: admin.firestore.FieldValue.increment(amount),
          lastUpdated: now
        }, { merge: true });

        // Create wallet transaction record
        transaction.set(walletTxRef, {
          userId,
          type: "deposit",
          amount,
          description: `Wallet deposit via payment gateway`,
          paymentReference,
          balanceBefore: currentBalance,
          balanceAfter: currentBalance + amount,
          createdAt: now
        });
      });

      return { success: true, message: "Deposit processed successfully" };

    } catch (error) {
      functions.logger.error("Error processing wallet deposit:", error);
      throw new functions.https.HttpsError(
        "internal",
        "Failed to process deposit"
      );
    }
  }
);

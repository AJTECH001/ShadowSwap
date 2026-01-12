import { ethers } from "hardhat";
import { FhenixClient, EncryptionTypes, getPermit } from "fhenixjs";
import { PoolKey, Currency } from "@uniswap/v4-sdk";
import { CurrencyAmount, TradeType, Percent } from "@uniswap/sdk-core";

async function main() {
    console.log("🚀 Starting Uniswap V4 + Fhenix Demo...");

    // 1. Setup Environment
    const [signer] = await ethers.getSigners();
    console.log(`👤 Using signer: ${signer.address}`);

    // Initialize Fhenix Client
    // In a real browser app, 'provider' would be window.ethereum
    const provider = ethers.provider;
    const client = new FhenixClient({ provider });

    // 2. Define Pool & Hook Details
    // This implies we have a deployed hook address. For demo, we'll use a placeholder.
    // In a real flow, you'd deploy your hook first.
    const HOOK_ADDRESS = "0x" + "1".repeat(40); // Placeholder
    const TOKEN_A = "0x" + "A".repeat(40);
    const TOKEN_B = "0x" + "B".repeat(40);

    const poolKey = {
        currency0: TOKEN_A,
        currency1: TOKEN_B,
        fee: 3000, 
        tickSpacing: 60,
        hooks: HOOK_ADDRESS
    };

    console.log(`🏊 Pool Key Configured with Hook: ${poolKey.hooks}`);

    // 3. Encrypt Order Details (Client-Side)
    // This is what the frontend does before sending the transaction
    console.log("🔐 Encrypting order details...");
    
    const amountToSwap = 100n * 10n**18n; // 100 Tokens
    const isZeroForOne = true;
    const slippage = 50; // 0.5%
    const deadline = Math.floor(Date.now() / 1000) + 3600;

    // Use FhenixJS to encrypt
    // Note: Creating a permit usually requires user signature in browser. 
    // Here we might need a mock permit or just encrypt if 'permit' is optional for 'store' check.
    // Ideally: await getPermit(contractAddress, provider); 
    // We'll skip permit fetch for this script as it's a demonstration of *encryption logic*, 
    // and non-view encryption (inputs) doesn't always strictly require a permit if blindly encrypting.
    
    const encAmount = await client.encrypt(Number(amountToSwap), EncryptionTypes.uint64);
    const encDirection = await client.encrypt(isZeroForOne, EncryptionTypes.bool);
    const encSlippage = await client.encrypt(slippage, EncryptionTypes.uint32);
    const encDeadline = await client.encrypt(deadline, EncryptionTypes.uint32);

    console.log("✅ Encryption complete!");
    console.log(`   Encrypted Amount Buffer Size: ${encAmount.data.length}`);

    // 4. Encode for Hook
    // ShadowSwapHook expects: abi.encode(InEuint64, InEbool, InEuint32, InEuint32)
    const abiCoder = new ethers.AbiCoder();
    const hookData = abiCoder.encode(
        [
            "tuple(bytes data)", 
            "tuple(bytes data)", 
            "tuple(bytes data)", 
            "tuple(bytes data)"
        ],
        [encAmount, encDirection, encSlippage, encDeadline]
    );

    console.log("📦 Hook Data Encoded. Ready for Swap Router.");

    // 5. Simulate Uniswap V4 SDK Planning
    // In a real app, you'd use the UniversalRouter or V4Planner here.
    // Since we don't have the full V4 Router deployed locally, we'll demonstrate the object construction.
    
    // Example: constructing a Swap object (conceptual)
    /*
    const swap = {
        poolKey: poolKey,
        zeroForOne: true,
        amountSpecified: amountToSwap,
        takeProfit: false,
        hookData: hookData // <--- THIS is where our encrypted data goes!
    };
    */

    console.log("🎉 Demo Complete: We successfully prepared an encrypted Uniswap V4 swap!");
    console.log("   - PoolKey defined");
    console.log("   - Inputs encrypted via Fhenix");
    console.log("   - HookData encoded for transaction");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

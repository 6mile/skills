/**
 * Utility functions for Circle Wallet Skill
 */

/**
 * Validates Ethereum address format
 * @param address - The address to validate
 * @returns true if valid Ethereum address format
 */
export function isValidEthereumAddress(address: string): boolean {
  return /^0x[a-fA-F0-9]{40}$/.test(address);
}

/**
 * Resolves a wallet identifier (ID or address) to a wallet ID
 * @param identifier - Wallet ID (UUID) or wallet address (0x...)
 * @param wallets - Array of wallets to search
 * @returns Wallet ID if found, null otherwise
 */
export function resolveWalletId(identifier: string, wallets: any[]): string | null {
  // Check if it's already a wallet ID (UUID format)
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(identifier)) {
    return identifier;
  }

  // Check if it's a wallet address
  const wallet = wallets.find(w => w.address.toLowerCase() === identifier.toLowerCase());
  return wallet?.id || null;
}

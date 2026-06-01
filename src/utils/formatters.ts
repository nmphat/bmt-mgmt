/**
 * Format full name to short name for mobile display
 * Example: "Nguyễn Văn An" -> "Nguyễn Văn A."
 */
export const getShortName = (name: string): string => {
  if (!name) return 'Unknown'
  const parts = name.trim().split(' ').slice(0, 3)

  return parts.join(' ') + (parts.length > 3 ? '...' : '')
}

export const formatCurrency = (amount: number | null | undefined): string => {
  const value = amount == null || isNaN(amount as number) ? 0 : amount
  return new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(value)
}

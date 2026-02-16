/**
 * Format full name to short name for mobile display
 * Example: "Nguyễn Văn An" -> "Nguyễn Văn A."
 */
export const getShortName = (name: string): string => {
  if (!name) return 'Unknown'
  const parts = name.trim().split(' ').slice(0, 3)

  return parts.join(' ') + (parts.length > 3 ? '...' : '')
}

export const formatCurrency = (amount: number): string => {
  return new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(amount)
}

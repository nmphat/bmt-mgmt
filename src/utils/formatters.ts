/**
 * Format full name to short name for mobile display
 * Example: "Nguyễn Văn An" -> "An N."
 */
export const getShortName = (name: string): string => {
  if (!name) return 'Unknown'
  const parts = name.trim().split(' ')
  if (parts.length === 1) return parts[0] ?? ''

  // Get first name (last part)
  const first = parts[0] ?? ''
  // Get surname initial (first part)
  const second = parts[1]?.[0] ?? ''

  return `${first} ${second}.`
}

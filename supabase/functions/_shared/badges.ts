// Shared badge count utilities for edge functions
// Standardizes on the get_badge_counts RPC for consistent badge numbers

/**
 * Get the total badge count for a user using the database RPC.
 * Returns combined unread messages + unread notifications count.
 */
export async function getBadgeCount(supabase: any, userId: string): Promise<number> {
  try {
    const { data, error } = await supabase
      .rpc('get_badge_counts', { p_user_id: userId, p_include_details: false })

    if (error) {
      console.error(`Error fetching badge counts for ${userId}:`, error)
      // Fallback to manual count
      return await getBadgeCountFallback(supabase, userId)
    }

    // RPC returns { unread_notifications, unread_messages, total }
    if (data && typeof data.total === 'number') {
      return data.total
    }

    // If RPC returns a number directly
    if (typeof data === 'number') {
      return data
    }

    return await getBadgeCountFallback(supabase, userId)
  } catch (err) {
    console.error(`Exception fetching badge counts for ${userId}:`, err)
    return 0
  }
}

/**
 * Fallback badge count calculation using direct queries.
 * Used when the RPC is not available.
 */
async function getBadgeCountFallback(supabase: any, userId: string): Promise<number> {
  // Get unread notification count
  const { count: unreadNotifications } = await supabase
    .from('notifications')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId)
    .eq('read', false)

  // Get unread message count via RPC
  const { data: unreadMessages } = await supabase
    .rpc('get_unread_message_count', { p_user_id: userId })

  const notifCount = unreadNotifications ?? 0
  const msgCount = typeof unreadMessages === 'number' ? unreadMessages : 0

  return notifCount + msgCount
}

/**
 * Pre-fetch badge counts for multiple users in parallel.
 * Returns a map of userId -> badgeCount.
 */
export async function getBadgeCountsBatch(
  supabase: any,
  userIds: string[]
): Promise<Map<string, number>> {
  const results = new Map<string, number>()
  const unique = [...new Set(userIds)]

  const settled = await Promise.allSettled(
    unique.map(async (userId) => {
      const count = await getBadgeCount(supabase, userId)
      return { userId, count }
    })
  )

  for (const result of settled) {
    if (result.status === 'fulfilled') {
      results.set(result.value.userId, result.value.count)
    }
  }

  return results
}

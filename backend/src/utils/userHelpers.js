/**
 * Returns true if `other` is in `user`'s blocked list.
 * Accepts either an id string or an object with `._id`.
 */
const isBlockedBy = (user, other) => {
  const otherId = other?._id ?? other;
  return (user.blockedUsers || []).some(
    (id) => id.toString() === otherId?.toString()
  );
};

/**
 * Returns true if either user has blocked the other.
 */
const eitherBlocked = (userA, userB) =>
  isBlockedBy(userA, userB) || isBlockedBy(userB, userA);

module.exports = { isBlockedBy, eitherBlocked };

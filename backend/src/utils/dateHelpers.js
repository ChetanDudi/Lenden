/** Returns { start, end } covering today 00:00:00.000 – 23:59:59.999 */
const getTodayRange = () => {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const end = new Date();
  end.setHours(23, 59, 59, 999);
  return { start, end };
};

/** Returns { start, end } for a given month (0-indexed) and year */
const getMonthRange = (year, month) => {
  const start = new Date(year, month, 1, 0, 0, 0, 0);
  const end = new Date(year, month + 1, 0, 23, 59, 59, 999);
  return { start, end };
};

module.exports = { getTodayRange, getMonthRange };

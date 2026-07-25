const QuickTransaction = require('../models/quickTransaction');
const Transaction = require('../models/transaction');
const GroupTransaction = require('../models/groupTransaction');
const Budget = require('../models/budget');
const BudgetRecurring = require('../models/budgetRecurring');
const SavingsGoal = require('../models/savingsGoal');
const User = require('../models/user');
const AdminTip = require('../models/adminTip');

const fmt = (n) => Math.round(n).toLocaleString('en-IN');
const CAP = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const makeCatMap = (txns) => {
  const m = {};
  for (const t of txns) {
    const c = (t.category || 'other').toLowerCase();
    if (!m[c]) m[c] = { amount: 0, count: 0 };
    m[c].amount += t.amount || 0;
    m[c].count++;
  }
  return m;
};

exports.getInsights = async (req, res) => {
  try {
    const userId = req.user._id;
    const user = await User.findById(userId).select('email name').lean();
    if (!user) return res.status(404).json({ message: 'User not found' });
    const email = user.email;

    const now = new Date();
    const thisMonthStart = new Date(now.getFullYear(), now.getMonth(), 1);
    const lastMonthStart = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    const threeMonthsAgo = new Date(now.getFullYear(), now.getMonth() - 3, 1);
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

    // This week = Monday-based
    const dow = now.getDay();
    const weekStart = new Date(now);
    weekStart.setDate(now.getDate() - ((dow + 6) % 7));
    weekStart.setHours(0, 0, 0, 0);
    const lastWeekStart = new Date(weekStart);
    lastWeekStart.setDate(weekStart.getDate() - 7);
    const lastWeekEnd = new Date(weekStart);
    lastWeekEnd.setDate(weekStart.getDate() - 1);
    lastWeekEnd.setHours(23, 59, 59, 999);

    const [quickAll, secureAll, groups, budget, goals, recurringItems, adminTips] = await Promise.all([
      QuickTransaction.find({ creatorEmail: email, date: { $gte: threeMonthsAgo } }).lean(),
      Transaction.find({ $or: [{ userEmail: email }, { counterpartyEmail: email }] }).lean(),
      GroupTransaction.find({ 'members.user': userId, isActive: true }).lean(),
      Budget.findOne({ user: userId, year: now.getFullYear(), month: now.getMonth() + 1 }).lean(),
      SavingsGoal.find({ user: userId, isCompleted: false }).lean(),
      BudgetRecurring.find({ user: userId, isActive: true }).lean(),
      AdminTip.find({
        isActive: true,
        $or: [
          { targetType: 'all' },
          { targetType: 'specific', targetUser: userId },
        ],
      }).sort({ createdAt: -1 }).limit(10).lean(),
    ]);

    const mySecure = secureAll.filter((t) => t.userEmail === email);

    // Partition by period
    const inPeriod = (d, from, to) => { const dd = new Date(d); return dd >= from && (!to || dd < to); };
    const thisMonthQuick  = quickAll.filter(t => inPeriod(t.date, thisMonthStart));
    const lastMonthQuick  = quickAll.filter(t => inPeriod(t.date, lastMonthStart, thisMonthStart));
    const thisMonthSecure = mySecure.filter(t => inPeriod(t.createdAt, thisMonthStart));
    const lastMonthSecure = mySecure.filter(t => inPeriod(t.createdAt, lastMonthStart, thisMonthStart));

    const thisMonthAll = [...thisMonthQuick, ...thisMonthSecure];
    const lastMonthAll = [...lastMonthQuick, ...lastMonthSecure];
    const allTxns = [...quickAll, ...mySecure];

    const thisWeekTxns = allTxns.filter(t => inPeriod(t.date || t.createdAt, weekStart));
    const lastWeekTxns = allTxns.filter(t => {
      const d = new Date(t.date || t.createdAt);
      return d >= lastWeekStart && d <= lastWeekEnd;
    });

    // ── Category maps ──────────────────────────────────────────────────────────
    const thisCatMap = makeCatMap(thisMonthAll);
    const lastCatMap = makeCatMap(lastMonthAll);
    const allCatMap  = makeCatMap(allTxns);

    // ── Category trends ────────────────────────────────────────────────────────
    const allCats = new Set([...Object.keys(thisCatMap), ...Object.keys(lastCatMap)]);
    const categoryTrends = Array.from(allCats).map((cat) => {
      const thisAmt = thisCatMap[cat]?.amount || 0;
      const lastAmt = lastCatMap[cat]?.amount || 0;
      const change = lastAmt > 0 ? Math.round(((thisAmt - lastAmt) / lastAmt) * 100) : null;
      return { category: cat, thisMonth: Math.round(thisAmt), lastMonth: Math.round(lastAmt), change };
    }).sort((a, b) => b.thisMonth - a.thisMonth);

    // ── Monthly summary ────────────────────────────────────────────────────────
    const totalThisMonth = thisMonthAll.reduce((s, t) => s + (t.amount || 0), 0);
    const totalLastMonth = lastMonthAll.reduce((s, t) => s + (t.amount || 0), 0);
    const budgetOverall = budget?.limits?.overall || null;
    const saved = budgetOverall ? Math.max(0, budgetOverall - totalThisMonth) : null;
    const largestTxn = thisMonthAll.reduce((mx, t) => (!mx || t.amount > mx.amount) ? t : mx, null);

    // ── Per-type spending breakdown ────────────────────────────────────────────
    const spentQuick      = Math.round(thisMonthQuick.reduce((s, t) => s + (t.amount || 0), 0));
    const spentSecure     = Math.round(thisMonthSecure.reduce((s, t) => s + (t.amount || 0), 0));
    const lastSpentQuick  = Math.round(lastMonthQuick.reduce((s, t) => s + (t.amount || 0), 0));
    const lastSpentSecure = Math.round(lastMonthSecure.reduce((s, t) => s + (t.amount || 0), 0));

    // Group expense user-share this month and last month
    let spentGroup = 0, lastSpentGroup = 0;
    const groupBreakdown = {};
    for (const g of groups) {
      let thisGrp = 0, lastGrp = 0;
      for (const exp of (g.expenses || [])) {
        const d = new Date(exp.date);
        const userSplit = (exp.split || []).find(s => String(s.user) === String(userId));
        const amt = userSplit?.amount || 0;
        if (d >= thisMonthStart) thisGrp += amt;
        else if (d >= lastMonthStart) lastGrp += amt;
      }
      if (thisGrp > 0) groupBreakdown[g.title || 'Unnamed Group'] = Math.round(thisGrp);
      spentGroup += thisGrp;
      lastSpentGroup += lastGrp;
    }
    spentGroup = Math.round(spentGroup);
    lastSpentGroup = Math.round(lastSpentGroup);

    // Quick-only category breakdown
    const quickCatBreak = Object.fromEntries(
      Object.entries(makeCatMap(thisMonthQuick)).map(([k, v]) => [k, Math.round(v.amount)])
    );

    const summary = {
      thisMonth: {
        spent: Math.round(totalThisMonth) + spentGroup,
        quick: spentQuick,
        secure: spentSecure,
        group: spentGroup,
        budget: budgetOverall,
        saved,
        txnCount: thisMonthAll.length,
      },
      lastMonth: {
        spent: Math.round(totalLastMonth) + lastSpentGroup,
        quick: lastSpentQuick,
        secure: lastSpentSecure,
        group: lastSpentGroup,
        txnCount: lastMonthAll.length,
      },
      largestExpense: largestTxn ? {
        amount: largestTxn.amount,
        category: largestTxn.category || 'other',
        counterparty: largestTxn.counterpartyEmail || largestTxn.users?.find(u => u !== email) || null,
      } : null,
      categoryBreakdown: Object.fromEntries(
        Object.entries(thisCatMap).map(([k, v]) => [k, Math.round(v.amount)])
      ),
      lastMonthBreakdown: Object.fromEntries(
        Object.entries(lastCatMap).map(([k, v]) => [k, Math.round(v.amount)])
      ),
      categoryBreakdownQuick: quickCatBreak,
      groupBreakdown,
    };

    // ── Expense prediction ─────────────────────────────────────────────────────
    const daysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    const daysElapsed = now.getDate();
    const dailyRate = daysElapsed > 0 ? totalThisMonth / daysElapsed : 0;
    const predictedMonthEnd = Math.round(dailyRate * daysInMonth);
    const prediction = {
      currentSpend: Math.round(totalThisMonth),
      predictedMonthEnd,
      daysElapsed,
      daysTotal: daysInMonth,
      dailyRate: Math.round(dailyRate),
      willExceedBudget: budgetOverall ? predictedMonthEnd > budgetOverall : null,
    };

    // ── Unusual expenses ───────────────────────────────────────────────────────
    const catAvgPerTxn = {};
    for (const [cat, d] of Object.entries(allCatMap)) {
      catAvgPerTxn[cat] = d.count > 0 ? d.amount / d.count : 0;
    }
    const recentTxns = allTxns.filter(t => new Date(t.date || t.createdAt) >= sevenDaysAgo);
    const unusualExpenses = recentTxns
      .filter(t => {
        const cat = (t.category || 'other').toLowerCase();
        const avg = catAvgPerTxn[cat] || 0;
        return avg > 0 && t.amount > avg * 2.5;
      })
      .sort((a, b) => b.amount - a.amount)
      .slice(0, 3)
      .map(t => {
        const cat = (t.category || 'other').toLowerCase();
        const dateStr = (t.date || t.createdAt)?.toString().split('T')[0] ?? '';
        return {
          date: dateStr,
          amount: Math.round(t.amount),
          category: cat,
          counterparty: t.counterpartyEmail || t.users?.find(u => u !== email) || null,
          usualAvg: Math.round(catAvgPerTxn[cat] || 0),
        };
      });

    // ── Spending habits ────────────────────────────────────────────────────────
    const dowTotals = [0, 0, 0, 0, 0, 0, 0];
    const dowCounts = [0, 0, 0, 0, 0, 0, 0];
    for (const t of allTxns) {
      const d = new Date(t.date || t.createdAt);
      if (isNaN(d.getTime())) continue;
      dowTotals[d.getDay()] += t.amount || 0;
      dowCounts[d.getDay()]++;
    }
    const dowAvg = dowTotals.map((tot, i) => dowCounts[i] > 0 ? Math.round(tot / dowCounts[i]) : 0);
    const highestDow = dowAvg.indexOf(Math.max(...dowAvg));
    const weekendTotal = Math.round(dowTotals[0] + dowTotals[6]);
    const weekdayTotal = Math.round(dowTotals.slice(1, 6).reduce((s, v) => s + v, 0));

    const monthTotals = new Array(12).fill(0);
    const monthCounts = new Array(12).fill(0);
    for (const t of allTxns) {
      const d = new Date(t.date || t.createdAt);
      if (isNaN(d.getTime())) continue;
      monthTotals[d.getMonth()] += t.amount || 0;
      monthCounts[d.getMonth()]++;
    }
    const monthAvg = monthTotals.map((tot, i) => monthCounts[i] > 0 ? Math.round(tot / monthCounts[i]) : 0);
    const validMonthAvg = monthAvg.filter(v => v > 0);
    const highestMonthIdx = validMonthAvg.length > 0 ? monthAvg.indexOf(Math.max(...validMonthAvg)) : -1;

    const topCatByAmount = Object.entries(allCatMap).sort((a, b) => b[1].amount - a[1].amount)[0];

    // dowBreakdown as keyed object so frontend can iterate {day: amount}
    // getDay() returns 0=Sun,1=Mon,...,6=Sat; we use Mon-Sun order with 3-letter keys
    const DOW_KEYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const dowBreakdownMap = {};
    for (let i = 0; i < 7; i++) {
      if (dowAvg[i] > 0) dowBreakdownMap[DOW_KEYS[i]] = dowAvg[i];
    }

    const spendingHabits = {
      highestDayOfWeek: DAY_NAMES[highestDow],
      highestDayAvg: dowAvg[highestDow],
      dowBreakdown: dowBreakdownMap,
      weekendTotal,
      weekdayTotal,
      highestMonth: highestMonthIdx >= 0 ? MONTH_NAMES[highestMonthIdx] : null,
      highestMonthAvg: highestMonthIdx >= 0 ? monthAvg[highestMonthIdx] : 0,
      mostExpensiveCategory: topCatByAmount ? topCatByAmount[0] : null,
    };

    // ── Tracked subscriptions ──────────────────────────────────────────────────
    const subscriptions = recurringItems
      .filter(r => r.category === 'Subscription')
      .map(r => ({
        name: r.name,
        amount: r.amount,
        cycle: 'monthly',
        category: 'Subscription',
        dueDay: r.dueDay,
      }));

    // ── Weekly AI summary ──────────────────────────────────────────────────────
    const thisWeekSpent = thisWeekTxns.reduce((s, t) => s + (t.amount || 0), 0);
    const lastWeekSpent = lastWeekTxns.reduce((s, t) => s + (t.amount || 0), 0);
    const thisWeekCatMap = makeCatMap(thisWeekTxns);
    const lastWeekCatMap = makeCatMap(lastWeekTxns);
    const weekCatBreakdown = Object.entries(thisWeekCatMap)
      .map(([cat, d]) => {
        const lastAmt = lastWeekCatMap[cat]?.amount || 0;
        const change = lastAmt > 0 ? Math.round(((d.amount - lastAmt) / lastAmt) * 100) : null;
        return { category: cat, amount: Math.round(d.amount), lastWeek: Math.round(lastAmt), change };
      })
      .sort((a, b) => b.amount - a.amount)
      .slice(0, 5);

    const weeklyAISummary = {
      thisWeek: { spent: Math.round(thisWeekSpent), txnCount: thisWeekTxns.length },
      lastWeek: { spent: Math.round(lastWeekSpent), txnCount: lastWeekTxns.length },
      weekChange: lastWeekSpent > 0 ? Math.round(((thisWeekSpent - lastWeekSpent) / lastWeekSpent) * 100) : null,
      categoryBreakdown: weekCatBreakdown,
    };

    // ── Month comparison ───────────────────────────────────────────────────────
    const monthComparison = {
      current: { label: MONTH_NAMES[now.getMonth()], spent: Math.round(totalThisMonth), txnCount: thisMonthAll.length },
      previous: { label: MONTH_NAMES[lastMonthStart.getMonth()], spent: Math.round(totalLastMonth), txnCount: lastMonthAll.length },
      diff: Math.round(totalLastMonth - totalThisMonth),
      diffPct: totalLastMonth > 0 ? Math.round(((totalThisMonth - totalLastMonth) / totalLastMonth) * 100) : null,
    };

    // ── Saving suggestions ─────────────────────────────────────────────────────
    const catLabel = (c) => c.charAt(0).toUpperCase() + c.slice(1);
    const aiTips = categoryTrends
      .filter(ct => ct.change !== null && ct.change > 10 && ct.thisMonth > 300)
      .slice(0, 4)
      .map(ct => ({
        id:           `ai_${ct.category}`,
        source:       'ai',
        title:        `Cut ${catLabel(ct.category)} spending`,
        body:         `Your ${catLabel(ct.category)} spend rose ${ct.change}% vs last month (₹${fmt(ct.thisMonth)} vs ₹${fmt(ct.lastMonth)}). Trimming 10% could save ₹${fmt(Math.round(ct.thisMonth * 0.1))} this month.`,
        impact:       ct.change > 50 ? 'high' : ct.change > 20 ? 'medium' : 'low',
        category:     ct.category,
        currentMonth: ct.thisMonth,
        lastMonth:    ct.lastMonth,
        change:       ct.change,
        potentialSaving: Math.round(ct.thisMonth * 0.1),
      }));

    const adminTipsMapped = adminTips.map(t => ({
      id:              t._id?.toString(),
      source:          'admin',
      title:           t.title,
      body:            t.body,
      impact:          t.impact || 'medium',
      category:        t.category || 'general',
      potentialSaving: t.potentialSaving ?? null,
    }));

    const savingSuggestions = [...adminTipsMapped, ...aiTips];

    // ── Goal forecast ──────────────────────────────────────────────────────────
    const avgMonthlySpend = (totalThisMonth + totalLastMonth) / 2;
    const avgMonthlySavings = budgetOverall ? Math.max(0, budgetOverall - avgMonthlySpend) : 0;

    const goalForecast = goals.slice(0, 3).map(g => {
      const remaining = Math.max(0, g.targetAmount - g.savedAmount);
      const monthsToGoal = avgMonthlySavings > 0 ? Math.ceil(remaining / avgMonthlySavings) : null;
      return {
        goalId: g._id?.toString(),
        goalName: g.name,
        emoji: g.emoji,
        targetAmount: g.targetAmount,
        savedAmount: g.savedAmount,
        remaining,
        monthlySavingsRate: Math.round(avgMonthlySavings),
        monthsToGoal,
      };
    });

    // ── Financial health score (richer) ───────────────────────────────────────
    const savingsRatioScore = budgetOverall && budgetOverall > 0
      ? CAP(Math.round((1 - totalThisMonth / budgetOverall) * 100 + 20), 0, 100)
      : 55;

    const budgetAdherenceScore = budgetOverall && budgetOverall > 0
      ? CAP(Math.round((1 - totalThisMonth / budgetOverall) * 120 + 40), 0, 100)
      : 60;

    const overspentCatCount = categoryTrends.filter(ct => ct.change !== null && ct.change > 30).length;
    const overspendingScore = CAP(100 - overspentCatCount * 20, 0, 100);

    const pendingQuickAll = quickAll.filter(t => !t.cleared);
    const pendingPaymentsScore = CAP(100 - pendingQuickAll.length * 4, 20, 100);

    const activityTrendScore = lastMonthAll.length > 0
      ? CAP(Math.round(80 - ((thisMonthAll.length - lastMonthAll.length) / lastMonthAll.length) * 20), 30, 100)
      : 70;

    const rawHealth = Math.round(
      (savingsRatioScore + budgetAdherenceScore + overspendingScore + pendingPaymentsScore + activityTrendScore) / 5
    );
    const healthScore = {
      total: CAP(rawHealth, 0, 100),
      factors: {
        savingsRatio:   CAP(savingsRatioScore, 0, 100),
        budgetAdherence: CAP(budgetAdherenceScore, 0, 100),
        overspending:   CAP(overspendingScore, 0, 100),
        pendingPayments: CAP(pendingPaymentsScore, 0, 100),
        activityTrend:  CAP(activityTrendScore, 0, 100),
      },
    };

    // ── Insight cards ──────────────────────────────────────────────────────────
    const insights = [];

    // 1. Net balance
    const totalLent = [...quickAll.filter(t => t.role === 'lender'), ...mySecure.filter(t => t.role === 'lender')].reduce((s, t) => s + t.amount, 0);
    const totalBorrowed = [...quickAll.filter(t => t.role === 'borrower'), ...mySecure.filter(t => t.role === 'borrower')].reduce((s, t) => s + t.amount, 0);
    const net = totalLent - totalBorrowed;
    insights.push({
      id: 'net_balance', type: 'overview', severity: net >= 0 ? 'positive' : 'warning',
      icon: net >= 0 ? 'trending_up' : 'trending_down',
      title: net >= 0 ? 'You Are in the Green' : 'You Have Outstanding Debt',
      message: net >= 0
        ? `Others owe you a net of ₹${fmt(Math.abs(net))} across all transactions.`
        : `You have a net outstanding of ₹${fmt(Math.abs(net))} across all transactions.`,
      value: net,
    });

    // 2. Overdue secure transactions
    const overdue = mySecure.filter(t => !t.userCleared && t.expectedReturnDate && new Date(t.expectedReturnDate) < now);
    if (overdue.length > 0) {
      const overdueAmt = overdue.reduce((s, t) => s + (t.remainingAmount ?? t.amount), 0);
      insights.push({
        id: 'overdue', type: 'warning', severity: 'danger', icon: 'schedule',
        title: `${overdue.length} Overdue Transaction${overdue.length > 1 ? 's' : ''}`,
        message: `${overdue.length} secure transaction${overdue.length > 1 ? 's' : ''} past due, totaling ₹${fmt(overdueAmt)}.`,
        value: overdue.length,
      });
    }

    // 3. Budget warnings
    if (budget?.limits?.quick) {
      const spentQuick = thisMonthQuick.reduce((s, t) => s + t.amount, 0);
      const pct = Math.round((spentQuick / budget.limits.quick) * 100);
      if (pct >= 80) {
        insights.push({
          id: 'budget_quick', type: 'budget', severity: pct >= 100 ? 'danger' : 'warning',
          icon: 'account_balance_wallet',
          title: pct >= 100 ? 'Quick Budget Exceeded' : 'Quick Budget Nearly Full',
          message: `You've used ${pct}% (₹${fmt(spentQuick)}) of your ₹${fmt(budget.limits.quick)} quick budget this month.`,
          value: pct,
        });
      }
    }
    if (budget?.limits?.secure) {
      const spentSecure = thisMonthSecure.reduce((s, t) => s + t.amount, 0);
      const pct = Math.round((spentSecure / budget.limits.secure) * 100);
      if (pct >= 80) {
        insights.push({
          id: 'budget_secure', type: 'budget', severity: pct >= 100 ? 'danger' : 'warning',
          icon: 'account_balance_wallet',
          title: pct >= 100 ? 'Secure Budget Exceeded' : 'Secure Budget Nearly Full',
          message: `You've used ${pct}% (₹${fmt(spentSecure)}) of your ₹${fmt(budget.limits.secure)} secure budget this month.`,
          value: pct,
        });
      }
    }

    // 4. Category trend insights (top 3 significant changes)
    for (const trend of categoryTrends.slice(0, 5)) {
      if (trend.change !== null && Math.abs(trend.change) >= 15 && trend.thisMonth > 200) {
        const isUp = trend.change > 0;
        insights.push({
          id: `cat_trend_${trend.category}`, type: 'trend',
          severity: isUp && trend.change > 30 ? 'warning' : isUp ? 'info' : 'positive',
          icon: isUp ? 'trending_up' : 'trending_down',
          title: `${trend.category.charAt(0).toUpperCase() + trend.category.slice(1)} ${isUp ? 'Up' : 'Down'} ${Math.abs(trend.change)}%`,
          message: `${trend.category.charAt(0).toUpperCase() + trend.category.slice(1)} spending ${isUp ? 'increased' : 'reduced'} by ${Math.abs(trend.change)}% (₹${fmt(trend.thisMonth)} vs ₹${fmt(trend.lastMonth)} last month).`,
          value: trend.change,
        });
        if (insights.filter(i => i.id.startsWith('cat_trend')).length >= 3) break;
      }
    }

    // 5. Monthly activity trend
    const thisMonthQty = thisMonthAll.length;
    const lastMonthQty = lastMonthAll.length;
    if (lastMonthQty > 0) {
      const changePct = Math.round(((thisMonthQty - lastMonthQty) / lastMonthQty) * 100);
      insights.push({
        id: 'monthly_trend', type: 'trend',
        severity: Math.abs(changePct) > 30 ? 'warning' : 'info',
        icon: changePct >= 0 ? 'arrow_upward' : 'arrow_downward',
        title: `Activity ${changePct >= 0 ? 'Up' : 'Down'} This Month`,
        message: `Transaction count is ${Math.abs(changePct)}% ${changePct >= 0 ? 'higher' : 'lower'} than last month (${thisMonthQty} vs ${lastMonthQty}).`,
        value: changePct,
      });
    }

    // 6. Top category
    const topCat = Object.entries(allCatMap).sort((a, b) => b[1].amount - a[1].amount)[0];
    if (topCat) {
      insights.push({
        id: 'top_category', type: 'pattern', severity: 'info', icon: 'category',
        title: `Top Category: ${topCat[0].charAt(0).toUpperCase() + topCat[0].slice(1)}`,
        message: `Highest spending in ${topCat[0]}: ₹${fmt(topCat[1].amount)} across ${topCat[1].count} transaction${topCat[1].count > 1 ? 's' : ''}.`,
        value: topCat[1].amount,
      });
    }

    // 7. Top counterparty
    const cpCounts = {};
    for (const t of quickAll) { const cp = t.users?.find(u => u !== email); if (cp) cpCounts[cp] = (cpCounts[cp] || 0) + 1; }
    for (const t of mySecure) { if (t.counterpartyEmail) cpCounts[t.counterpartyEmail] = (cpCounts[t.counterpartyEmail] || 0) + 1; }
    const topCp = Object.entries(cpCounts).sort((a, b) => b[1] - a[1])[0];
    if (topCp) {
      insights.push({
        id: 'top_counterparty', type: 'pattern', severity: 'info', icon: 'person',
        title: 'Most Frequent Contact',
        message: `You transact most with ${topCp[0]} (${topCp[1]} time${topCp[1] > 1 ? 's' : ''}).`,
        value: topCp[1],
      });
    }

    // 8. Group balances
    let groupBalance = 0;
    for (const g of groups) {
      const bal = (g.balances ?? []).find(b => b.user?.toString() === userId.toString());
      if (bal) groupBalance += bal.balance;
    }
    if (groups.length > 0) {
      insights.push({
        id: 'group_balance', type: 'overview',
        severity: groupBalance > 0 ? 'positive' : groupBalance < 0 ? 'warning' : 'info',
        icon: 'group',
        title: groupBalance === 0 ? 'All Settled in Groups' : groupBalance > 0 ? 'Groups Owe You' : 'You Owe in Groups',
        message: groupBalance === 0
          ? `All settled across ${groups.length} active group${groups.length > 1 ? 's' : ''}.`
          : `Net group balance: ${groupBalance > 0 ? '+' : ''}₹${fmt(Math.abs(groupBalance))} across ${groups.length} group${groups.length > 1 ? 's' : ''}.`,
        value: groupBalance,
      });
    }

    // 9. Uncleared quick entries
    const uncleared = quickAll.filter(t => !t.cleared);
    if (uncleared.length > 0) {
      const unclearedAmt = uncleared.reduce((s, t) => s + t.amount, 0);
      insights.push({
        id: 'uncleared_quick', type: 'action',
        severity: uncleared.length > 5 ? 'warning' : 'info', icon: 'pending_actions',
        title: 'Pending Quick Entries',
        message: `${uncleared.length} quick transaction${uncleared.length > 1 ? 's' : ''} worth ₹${fmt(unclearedAmt)} are still uncleared.`,
        value: uncleared.length,
      });
    }

    // 10. Avg transaction
    const allAmounts = allTxns.map(t => t.amount || 0).filter(a => a > 0);
    if (allAmounts.length >= 3) {
      const avg = Math.round(allAmounts.reduce((s, v) => s + v, 0) / allAmounts.length);
      insights.push({
        id: 'avg_transaction', type: 'pattern', severity: 'info', icon: 'insights',
        title: 'Average Transaction Size',
        message: `Your average transaction is ₹${fmt(avg)} across ${allAmounts.length} recorded transactions.`,
        value: avg,
      });
    }

    // 11. Settlement opportunity
    const unsettledCP = {};
    for (const t of quickAll.filter(t => !t.cleared)) {
      const cp = t.users?.find(u => u !== email);
      if (!cp) continue;
      unsettledCP[cp] = (unsettledCP[cp] || 0) + (t.role === 'lender' ? t.amount : -t.amount);
    }
    const topUnsettled = Object.entries(unsettledCP).sort((a, b) => Math.abs(b[1]) - Math.abs(a[1]))[0];
    if (topUnsettled && Math.abs(topUnsettled[1]) > 0) {
      const amt = Math.abs(topUnsettled[1]);
      const isOwed = topUnsettled[1] > 0;
      insights.push({
        id: 'settle_suggestion', type: 'action', severity: 'info', icon: 'handshake',
        title: 'Settlement Opportunity',
        message: isOwed
          ? `${topUnsettled[0]} owes you ₹${fmt(amt)}. Consider requesting settlement.`
          : `You owe ${topUnsettled[0]} ₹${fmt(amt)}. Consider settling up soon.`,
        value: amt,
      });
    }

    // 12. Unusual expense insight cards
    for (const ue of unusualExpenses.slice(0, 2)) {
      insights.push({
        id: `unusual_${ue.category}`, type: 'warning', severity: 'warning', icon: 'arrow_upward',
        title: 'Unusual Expense Detected',
        message: `A ₹${fmt(ue.amount)} ${ue.category} expense is unusually high (usual avg: ₹${fmt(ue.usualAvg)} per transaction).`,
        value: ue.amount,
      });
    }

    // 13. Spending prediction
    if (prediction.willExceedBudget) {
      insights.push({
        id: 'prediction_warning', type: 'budget', severity: 'warning', icon: 'trending_up',
        title: 'On Track to Exceed Budget',
        message: `At your current pace, you'll spend ₹${fmt(prediction.predictedMonthEnd)} this month, exceeding your ₹${fmt(budgetOverall)} budget.`,
        value: prediction.predictedMonthEnd,
      });
    }

    // 14. Monthly saving achievement
    if (monthComparison.diff > 500) {
      insights.push({
        id: 'monthly_saving_achievement', type: 'positive', severity: 'positive', icon: 'trending_down',
        title: `Spent Less Than ${monthComparison.previous.label}`,
        message: `You spent ₹${fmt(monthComparison.diff)} less compared to ${monthComparison.previous.label}. Great discipline!`,
        value: monthComparison.diff,
      });
    }

    // 15. Weekend spending insight
    if (weekendTotal > weekdayTotal * 0.6 && weekendTotal > 1000) {
      insights.push({
        id: 'weekend_spending', type: 'pattern', severity: 'info', icon: 'insights',
        title: 'High Weekend Spending',
        message: `You spend ₹${fmt(weekendTotal)} on weekends vs ₹${fmt(weekdayTotal)} on weekdays over the last 3 months.`,
        value: weekendTotal,
      });
    }

    // 16. Conversational category insights (richer text)
    for (const trend of categoryTrends.filter(ct => ct.change !== null && Math.abs(ct.change) >= 20 && ct.thisMonth > 500).slice(0, 2)) {
      const isUp = trend.change > 0;
      const catName = trend.category.charAt(0).toUpperCase() + trend.category.slice(1);
      const peakDow = spendingHabits.highestDayOfWeek;
      const reduceTimes = isUp ? Math.ceil(trend.thisMonth * 0.1 / (trend.thisMonth / (thisCatMap[trend.category]?.count || 1))) : 0;
      const conversationalMessage = isUp
        ? `Your ${catName} expenses increased by ${trend.change}% compared to last month (₹${fmt(trend.thisMonth)} vs ₹${fmt(trend.lastMonth)}). Most of the increase likely happened around ${peakDow}s. Reducing ${catName} visits by ${reduceTimes > 0 ? reduceTimes : 1} time${reduceTimes > 1 ? 's' : ''} a week could save around ₹${fmt(Math.round(trend.thisMonth * 0.1))} next month.`
        : `Great news — your ${catName} spending dropped by ${Math.abs(trend.change)}% (₹${fmt(trend.lastMonth)} → ₹${fmt(trend.thisMonth)}). Keep this up and you could save an extra ₹${fmt(Math.round(trend.lastMonth * 0.1))} over the next three months.`;
      insights.push({
        id: `conversational_${trend.category}`, type: 'conversational',
        severity: isUp && trend.change > 40 ? 'warning' : isUp ? 'info' : 'positive',
        icon: isUp ? 'chat_bubble_outline' : 'sentiment_satisfied_alt',
        title: isUp ? `${catName} spending is climbing` : `${catName} spending dropped`,
        message: conversationalMessage,
        value: trend.change,
      });
    }

    // 17. Smart prediction warning (day-specific)
    if (budgetOverall && prediction.dailyRate > 0) {
      const daysLeft = prediction.daysTotal - prediction.daysElapsed;
      const remainingBudget = budgetOverall - totalThisMonth;
      if (remainingBudget > 0 && prediction.dailyRate > 0) {
        const exceedInDays = Math.ceil(remainingBudget / prediction.dailyRate);
        const exceedDate   = new Date(now.getTime() + exceedInDays * 24 * 60 * 60 * 1000);
        const exceedDay    = exceedDate.getDate();
        if (exceedInDays < daysLeft) {
          insights.push({
            id: 'smart_warning_exceed_date', type: 'budget', severity: 'warning', icon: 'warning_amber',
            title: `⚠ Budget likely exceeded by the ${exceedDay}th`,
            message: `At your current daily spend of ₹${fmt(prediction.dailyRate)}, you'll exhaust your remaining budget of ₹${fmt(Math.round(remainingBudget))} around the ${exceedDay}th — ${daysLeft - exceedInDays} days before month end.`,
            value: exceedDay,
          });
        }
      }

      // Daily spend vs normal
      const avgDailyLast3Months = allTxns.length > 0
        ? allTxns.reduce((s, t) => s + (t.amount || 0), 0) / 90
        : 0;
      if (avgDailyLast3Months > 0 && prediction.dailyRate > avgDailyLast3Months * 1.5) {
        const multiple = (prediction.dailyRate / avgDailyLast3Months).toFixed(1);
        insights.push({
          id: 'daily_spend_spike', type: 'warning', severity: 'warning', icon: 'bolt',
          title: 'Daily Spend Is Unusually High',
          message: `Your daily spending this month (₹${fmt(prediction.dailyRate)}/day) is ${multiple}× your normal daily average (₹${fmt(Math.round(avgDailyLast3Months))}/day).`,
          value: prediction.dailyRate,
        });
      }
    }

    // ── Financial personality ─────────────────────────────────────────────────
    const topCats = Object.entries(allCatMap).sort((a, b) => b[1].amount - a[1].amount);
    const topCatName = topCats[0]?.[0] || '';
    const subCount = recurringItems.filter(r => r.category === 'Subscription').length;
    const weekendRatio = (weekendTotal + weekdayTotal) > 0 ? weekendTotal / (weekendTotal + weekdayTotal) : 0;
    const savingsRatio = budgetOverall > 0 ? Math.max(0, 1 - totalThisMonth / budgetOverall) : 0;

    let personality = 'Balanced';
    let personalityEmoji = '⚖️';
    let personalityDesc = 'You maintain a healthy balance between spending and saving. Keep it up!';

    if (savingsRatio >= 0.25) {
      personality = 'Super Saver';
      personalityEmoji = '🏆';
      personalityDesc = `You saved ${Math.round(savingsRatio * 100)}% of your budget this month. You're among the most disciplined spenders!`;
    } else if (budgetOverall > 0 && totalThisMonth > budgetOverall * 1.2) {
      personality = 'Heavy Spender';
      personalityEmoji = '🛍️';
      const overPct = Math.round((totalThisMonth / budgetOverall - 1) * 100);
      personalityDesc = `You've spent ${overPct}% over budget this month. Small cutbacks in ${topCatName} could make a big difference.`;
    } else if (subCount >= 3) {
      personality = 'Subscription Lover';
      personalityEmoji = '📱';
      personalityDesc = `You have ${subCount} active subscriptions. Worth doing a monthly audit — unused ones add up fast.`;
    } else if (weekendRatio > 0.55) {
      personality = 'Weekend Shopper';
      personalityEmoji = '🛒';
      personalityDesc = `Over half your spending (${Math.round(weekendRatio * 100)}%) happens on weekends. Planning weekend budgets specifically could help.`;
    } else if (topCatName === 'food' && topCats[0][1].amount > totalThisMonth * 0.4) {
      personality = 'Foodie';
      personalityEmoji = '🍽️';
      personalityDesc = `${Math.round((topCats[0][1].amount / totalThisMonth) * 100)}% of your spending goes to food. Meal-prepping a few days a week could save ₹${fmt(Math.round(topCats[0][1].amount * 0.15))}.`;
    } else if (topCatName === 'travel') {
      personality = 'Explorer';
      personalityEmoji = '✈️';
      personalityDesc = `Travel is your top category. Consider booking in advance for better rates.`;
    }

    const financialPersonality = { personality, emoji: personalityEmoji, description: personalityDesc, topCategory: topCatName };

    // ── Personal timeline (monthly summary, last 6 months) ────────────────────
    const personalTimeline = [];
    for (let i = 5; i >= 0; i--) {
      const mStart = new Date(now.getFullYear(), now.getMonth() - i, 1);
      const mEnd   = new Date(now.getFullYear(), now.getMonth() - i + 1, 0, 23, 59, 59);
      const mTxns  = allTxns.filter(t => {
        const d = new Date(t.date || t.createdAt);
        return d >= mStart && d <= mEnd;
      });
      const mBudget = await Budget.findOne({ user: userId, year: mStart.getFullYear(), month: mStart.getMonth() + 1 }).lean();
      const mSpent = mTxns.reduce((s, t) => s + (t.amount || 0), 0);
      const mOverall = mBudget?.limits?.overall ?? null;
      const mSaved  = mOverall ? Math.max(0, mOverall - mSpent) : null;
      let label = '';
      if (mSaved !== null && mSaved > 1000) label = `Saved ₹${fmt(mSaved)}`;
      else if (mOverall && mSpent > mOverall) label = `Overspent by ₹${fmt(Math.round(mSpent - mOverall))}`;
      else if (mTxns.length === 0) label = 'No activity';
      else label = `₹${fmt(Math.round(mSpent))} spent`;

      personalTimeline.push({
        year: mStart.getFullYear(),
        month: MONTH_NAMES[mStart.getMonth()],
        spent: Math.round(mSpent),
        budget: mOverall ? Math.round(mOverall) : null,
        saved: mSaved ? Math.round(mSaved) : null,
        txnCount: mTxns.length,
        label,
        status: mOverall ? (mSpent > mOverall ? 'overspent' : mSpent > mOverall * 0.9 ? 'near_limit' : 'good') : 'no_budget',
      });
    }

    // ── Daily spending heatmap (last 91 days) ─────────────────────────────────
    const ninetyOneDaysAgo = new Date(now.getTime() - 90 * 24 * 60 * 60 * 1000);
    const dailySpending = {};
    for (const t of quickAll) {
      const d = new Date(t.date);
      if (d < ninetyOneDaysAgo) continue;
      const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
      dailySpending[key] = (dailySpending[key] || 0) + (t.amount || 0);
    }

    res.json({
      insights,
      generatedAt: now,
      totalInsights: insights.length,
      summary,
      categoryTrends,
      unusualExpenses,
      spendingHabits,
      weeklyAISummary,
      monthComparison,
      savingSuggestions,
      goalForecast,
      healthScore,
      prediction,
      subscriptions,
      financialPersonality,
      personalTimeline,
      dailySpending,
    });
  } catch (err) {
    console.error('Insights error:', err);
    res.status(500).json({ message: 'Server error', detail: err.message });
  }
};
